--!strict
--//Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--//Modules
local Signal = require(ReplicatedStorage.Packages.Signal) :: any
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore) :: any
local ReplicaServer = require(ServerScriptService.ServerPackages.ReplicaServer) :: any
local DataTemplate = require(ReplicatedStorage.Shared.DataTemplate)
local DataRules = require(ReplicatedStorage.Shared.DataRules)

type Profile = any
type Replica = any

-- String-indexable view of the template (DataTemplate itself is typed per key)
local Template: { [string]: any } = DataTemplate :: any

--//Config
local LOAD_TIMEOUT = 30 -- seconds before a player whose data can't load is kicked
local WIPE_TIMEOUT = 30 -- seconds to wait for a local session to end before wiping
local WIPE_VERIFY_ATTEMPTS = 3
local WIPE_VERIFY_DELAY = 5 -- seconds between delete + verify attempts
local MAX_STRING_LENGTH = 10_000
local MAX_DEPTH = 32
local CURRENT_VERSION = DataTemplate.DataVersion

-- NOTE: never bump LiveVersion to "reset" data - it points every player at an empty
-- store. Change the schema with DataVersion + Migrations instead.
local LiveVersion = 0
local TestVersion = 1
local StoreName = if RunService:IsStudio() then "PlayerTest_v" .. TestVersion else "PlayerLive_v" .. LiveVersion

local PlayerToken = ReplicaServer.Token("PlayerData")
local PlayerStore: any = ProfileStore.New(StoreName, DataTemplate)

--any keys from player data added here will show up in leaderstats, e.g. { TimePlayed = "IntValue" }
local _LeaderstatsConfig: { [string]: string } = {}

--[[
	Migrations[v] upgrades data from version v to v + 1. They run on a COPY of the
	data before Reconcile; the copy is only applied if every step succeeds, so a
	buggy migration can never save half-migrated data.
]]
local Migrations: { [number]: (data: any) -> () } = {
	[0] = function(data)
		-- v0 stored FirstLoginTime as "None" and persisted a session-only JoinTime.
		if type(data.FirstLoginTime) ~= "number" then
			data.FirstLoginTime = 0
		end
		data.JoinTime = nil
	end,
}

--//Private State (never hand these tables out - all writes must go through Set/SetPath)
local Profiles: { [Player]: Profile } = {}
local Replicas: { [Player]: Replica } = {}
local Leaderstats: { [Player]: { [string]: Instance } } = {}
local TimeCommitted: { [Player]: number } = {} -- os.time() of the last TimePlayed commit
local WipesInProgress: { [number]: boolean } = {}

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- fires (player) once their data is ready

--//Helpers
local function ProfileKey(userId: number): string
	return "Player_" .. userId
end

local function DeepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = DeepCopy(v)
	end
	return copy
end

local function IsFiniteNumber(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function IsValidString(s: string): boolean
	return #s <= MAX_STRING_LENGTH and utf8.len(s) ~= nil
end

--[[
	True only for values DataStores can store: finite numbers, booleans, valid
	UTF-8 strings, and tables that are either a pure array (keys exactly 1..n)
	or a pure string-keyed dictionary.
]]
local function IsSerializable(value: any, depth: number): boolean
	if depth > MAX_DEPTH then
		return false
	end

	local t = type(value)
	if t == "number" then
		return IsFiniteNumber(value)
	elseif t == "boolean" then
		return true
	elseif t == "string" then
		return IsValidString(value)
	elseif t == "table" then
		if getmetatable(value) ~= nil then
			return false
		end

		local count = 0
		local maxIndex = 0
		local hasStringKey = false

		for k, v in value do
			count += 1
			if type(k) == "string" then
				if not IsValidString(k) then
					return false
				end
				hasStringKey = true
			elseif type(k) == "number" then
				-- rejects NaN, inf, fractional and < 1 keys
				if not (k >= 1 and k % 1 == 0) then
					return false
				end
				if k > maxIndex then
					maxIndex = k
				end
			else
				return false
			end

			if not IsSerializable(v, depth + 1) then
				return false
			end
		end

		if hasStringKey then
			return maxIndex == 0 -- no mixed tables
		end
		return maxIndex == count -- no sparse arrays
	end

	return false
end

local function CheckRule(key: string, value: any): (boolean, string?)
	local rule = DataRules[key]
	if rule == nil then
		return true, nil
	end

	if type(value) == "number" then
		if rule.Integer and value % 1 ~= 0 then
			return false, "must be a whole number"
		end
		if rule.Min ~= nil and value < rule.Min then
			return false, `must be at least {rule.Min}`
		end
		if rule.Max ~= nil and value > rule.Max then
			return false, `must be at most {rule.Max}`
		end
	elseif type(value) == "string" then
		if rule.MaxLength ~= nil and #value > rule.MaxLength then
			return false, `must be at most {rule.MaxLength} characters`
		end
	end

	return true, nil
end

-- Integer >= 0, else 0 (so NaN / 0.5 / negative versions run every migration)
local function ReadVersion(data: any): number
	local raw = data.DataVersion
	if type(raw) == "number" and raw >= 0 and raw % 1 == 0 then
		return raw
	end
	return 0
end

local function ApplyMigrations(profile: Profile, fromVersion: number)
	if fromVersion >= CURRENT_VERSION then
		return
	end

	local migrated = DeepCopy(profile.Data)
	for version = fromVersion, CURRENT_VERSION - 1 do
		local step = Migrations[version]
		if step then
			step(migrated)
		end
	end
	migrated.DataVersion = CURRENT_VERSION

	-- Only reached if every step succeeded
	table.clear(profile.Data)
	for k, v in migrated do
		profile.Data[k] = v
	end
end

-- keepTimeTracking: leave TimeCommitted for the final OnSave (cleared in OnSessionEnd,
-- which ProfileStore fires after OnSave)
local function CleanupPlayer(player: Player, keepTimeTracking: boolean?)
	Profiles[player] = nil
	if not keepTimeTracking then
		TimeCommitted[player] = nil
	end
	Leaderstats[player] = nil

	local replica = Replicas[player]
	if replica then
		Replicas[player] = nil
		replica:Destroy()
	end
end

-- Adds play time since the last commit. Runs synchronously in ProfileStore's
-- OnSave (before every autosave and the final save), so a crash loses at most
-- one autosave interval of play time.
local function CommitTime(player: Player, profile: Profile)
	local last = TimeCommitted[player]
	if last == nil then
		return
	end

	local now = os.time()
	local current = profile.Data.TimePlayed
	if type(current) ~= "number" or not IsFiniteNumber(current) or current < 0 then
		current = 0
	end

	local value = current + math.max(0, now - last)
	TimeCommitted[player] = now

	local replica = Replicas[player]
	if replica then
		replica:Set({ "TimePlayed" }, value)
	else
		profile.Data.TimePlayed = value
	end
end

-- Validates and writes a top-level key. Returns (ok, reason).
local function TrySet(player: Player, key: string, value: any): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, "data is not loaded"
	end

	local template = Template[key]
	if template == nil then
		return false, `unknown key '{key}'`
	end
	if typeof(value) ~= typeof(template) then
		return false, `must be a {typeof(template)}`
	end
	if not IsSerializable(value, 0) then
		return false, "can't be saved (NaN/inf, invalid text, or a mixed/sparse table)"
	end

	local ruleOk, reason = CheckRule(key, value)
	if not ruleOk then
		return false, reason
	end

	if type(value) == "table" then
		value = DeepCopy(value) -- don't alias the caller's table into saved data
	end

	-- Replica:Set writes into replica.Data, which IS profile.Data, then replicates.
	-- Writing profile.Data first could make Replica see "no change" and skip it.
	local replica = Replicas[player]
	if replica then
		replica:Set({ key }, value)
	else
		profile.Data[key] = value
	end

	if key == "TimePlayed" then
		-- Explicit set/reset: don't add play time from before the change
		TimeCommitted[player] = os.time()
	end

	local stats = Leaderstats[player]
	local stat = stats and stats[key]
	if stat then
		(stat :: any).Value = value
	end

	return true, nil
end

local function CreateLeaderstats(player: Player, profile: Profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local stats: { [string]: Instance } = {}

	for key, valueType in _LeaderstatsConfig do
		local ok, err = pcall(function()
			local instance: any = Instance.new(valueType :: any)
			instance.Name = key
			instance.Value = profile.Data[key]
			instance.Parent = folder
			stats[key] = instance
		end)
		if not ok then
			warn(`[DataService] leaderstat {key} failed: {err}`)
		end
	end

	folder.Parent = player
	Leaderstats[player] = stats
end

local function OnProfileLoad(player: Player, profile: Profile)
	if profile.Data.FirstLoginTime == 0 then
		DataService:Set(player, "FirstLoginTime", os.time())
	end
end

-- Everything after the session lock is acquired. Called in pcall by OnPlayerAdded.
local function SetupProfile(player: Player, profile: Profile, version: number): boolean
	profile:AddUserId(player.UserId)
	ApplyMigrations(profile, version)
	profile:Reconcile()

	TimeCommitted[player] = os.time()
	profile.OnSave:Connect(function()
		CommitTime(player, profile)
	end)

	profile.OnSessionEnd:Connect(function()
		-- Fires after the final OnSave, so the last play time is already committed
		CleanupPlayer(player)
		if player.Parent == Players then
			player:Kick("Your data session ended (were you in another server?). Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return true
	end

	Profiles[player] = profile
	OnProfileLoad(player, profile)

	local replica = ReplicaServer.New({
		Token = PlayerToken,
		Tags = { UserId = player.UserId },
		Data = profile.Data,
	})
	Replicas[player] = replica
	replica:Subscribe(player)

	CreateLeaderstats(player, profile)

	DataService.ProfileLoaded:Fire(player)
	return true
end

local function OnPlayerAdded(player: Player)
	if WipesInProgress[player.UserId] then
		player:Kick("Your data is being reset. Please rejoin in a minute.")
		return
	end

	local started = os.clock()
	local profile = PlayerStore:StartSessionAsync(ProfileKey(player.UserId), {
		-- Passing Cancel disables ProfileStore's own timeout, so enforce one here.
		Cancel = function()
			return player.Parent ~= Players or os.clock() - started > LOAD_TIMEOUT
		end,
	})

	if profile == nil then
		if player.Parent == Players then
			player:Kick("Could not load your data. Please rejoin in a moment.")
		end
		return
	end

	-- Data written by a newer server version: don't Reconcile/save it with an old schema
	local version = ReadVersion(profile.Data)
	if version > CURRENT_VERSION then
		profile:EndSession()
		if player.Parent == Players then
			player:Kick("This server is out of date. Please rejoin to get the latest version.")
		end
		return
	end

	local ok, err = pcall(SetupProfile, player, profile, version)
	if not ok then
		warn(`[DataService] profile setup failed for {player.UserId}: {err}`)
		CleanupPlayer(player)
		if profile:IsActive() then
			profile:EndSession()
		end
		if player.Parent == Players then
			player:Kick("Data error occurred. Please rejoin.")
		end
	end
end

local function OnPlayerRemoving(player: Player)
	local profile = Profiles[player]
	if profile then
		profile:EndSession() -- final play time is committed in OnSave
	end
	CleanupPlayer(player, true)
end

local function WaitUntil(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not condition() do
		if os.clock() >= deadline then
			return false
		end
		task.wait(0.2)
	end
	return true
end

--[[
	Permanent erasure. The profile's contents are cleared BEFORE its session ends,
	so any save that lands after RemoveAsync writes nothing but an empty record,
	and the result is verified with GetAsync instead of assumed.
]]
local function WipeInternal(userId: number): (boolean, string)
	local key = ProfileKey(userId)

	-- 1. In this server: kick and wait for the session to end (stealing a key
	--    that's still active in this server is an error in ProfileStore).
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local profile = Profiles[player]
		player:Kick("Your data is being reset by an admin.")
		if profile then
			local ended = WaitUntil(function()
				return not profile:IsActive()
			end, WIPE_TIMEOUT)
			if not ended then
				return false, "Timed out waiting for the player's session to end. Nothing was deleted."
			end
		end
	end

	-- 2. Take the lock. Sessions in other servers end without saving further changes.
	local started = os.clock()
	local stolen = PlayerStore:StartSessionAsync(key, {
		Steal = true,
		Cancel = function()
			return os.clock() - started > LOAD_TIMEOUT
		end,
	})
	if stolen == nil then
		return false, "Timed out locking the profile (DataStores may be down). Nothing was deleted."
	end

	-- 3. Erase contents, then release.
	table.clear(stolen.Data)
	stolen:EndSession()

	-- 4. Delete and verify. Retries if a late save recreated an (empty) record.
	for _ = 1, WIPE_VERIFY_ATTEMPTS do
		task.wait(WIPE_VERIFY_DELAY)

		local removeOk, removed = pcall(function()
			return PlayerStore:RemoveAsync(key)
		end)
		if removeOk and removed then
			local getOk, remaining = pcall(function()
				return PlayerStore:GetAsync(key)
			end)
			if getOk and remaining == nil then
				return true, `Wiped all saved data for UserId {userId}.`
			end
			if getOk and remaining and next(remaining.Data) ~= nil then
				return false, "Data was saved again by another session (did the player rejoin?). Run wipedata again."
			end
			-- Empty record or failed check: try again
		end
	end

	return false, "Could not confirm deletion (DataStores may be down). The data is cleared; run wipedata again to remove the record."
end

local function ParseAs(template: any, raw: string): (boolean, any)
	local t = type(template)
	if t == "number" then
		if raw:find("[xX]") then
			return false, nil -- no hex
		end
		local n = tonumber(raw)
		return n ~= nil, n
	elseif t == "boolean" then
		if raw == "true" then
			return true, true
		elseif raw == "false" then
			return true, false
		end
		return false, nil
	elseif t == "string" then
		return true, raw
	elseif t == "table" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		return ok and type(decoded) == "table", decoded
	end
	return false, nil
end

--//Public Functions
function DataService:init(UseMock: boolean)
	if UseMock then
		PlayerStore = PlayerStore.Mock
	end

	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		warn(`[DataService] DataStore error ({storeName} / {profileKey}): {message}`)
	end)

	ProfileStore.OnCriticalToggle:Connect(function(isCritical)
		if isCritical then
			warn("[DataService] DataStores are in a critical state - saves/loads are failing repeatedly")
		else
			print("[DataService] DataStores recovered from critical state")
		end
	end)

	--for players who might have joined before init
	for _, player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function DataService:IsLoaded(player: Player): boolean
	return Profiles[player] ~= nil
end

--[[
	Yields until the player's data is loaded. Returns a read-only COPY of the data,
	or nil if the player left or their data failed to load. Write with Set/SetPath.
]]
function DataService:WaitForData(player: Player): any
	if Profiles[player] then
		return DeepCopy(Profiles[player].Data)
	end

	if player.Parent ~= Players then
		return nil
	end

	local thread = coroutine.running()
	local finished = false
	local loadedConnection: any, ancestryConnection: RBXScriptConnection

	local function finish()
		if finished then
			return
		end
		finished = true
		loadedConnection:Disconnect()
		ancestryConnection:Disconnect()
		task.spawn(thread)
	end

	loadedConnection = self.ProfileLoaded:Connect(function(loadedPlayer: Player)
		if loadedPlayer == player then
			finish()
		end
	end)
	ancestryConnection = player.AncestryChanged:Connect(function()
		if player.Parent ~= Players then
			finish()
		end
	end)

	coroutine.yield()

	local profile = Profiles[player]
	return if profile then DeepCopy(profile.Data) else nil
end

-- Returns a copy for table values; mutate with Set/SetPath, not the result.
function DataService:Get(player: Player, key: string): any
	local profile = Profiles[player]
	if profile then
		return DeepCopy(profile.Data[key])
	end
	return nil
end

-- Read a nested value (copy), e.g. GetPath(player, {"Inventory", itemId})
function DataService:GetPath(player: Player, path: { string | number }): any
	local profile = Profiles[player]
	if not profile then
		return nil
	end
	local node: any = profile.Data
	for _, segment in path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return DeepCopy(node)
end

function DataService:Set(player: Player, key: string, value: any): boolean
	local ok, reason = TrySet(player, key, value)
	if not ok and Profiles[player] then
		warn(`[DataService] rejected {key} = {tostring(value)} for {player.UserId}: {reason}`)
	end
	return ok
end

--[[
	Write a nested value and replicate it, e.g. SetPath(player, {"Inventory", itemId}, item).
	Parent tables must already exist. Pass nil to remove a nested entry.
	Rejected if the result couldn't be saved (e.g. it would make a mixed or sparse table).
]]
function DataService:SetPath(player: Player, path: { string | number }, value: any): boolean
	if #path == 0 then
		return false
	end

	local first = path[1]
	if type(first) ~= "string" then
		return false
	end
	if #path == 1 then
		return self:Set(player, first, value)
	end

	local profile = Profiles[player]
	if not profile or Template[first] == nil then
		return false
	end

	local parent: any = profile.Data
	for i = 1, #path - 1 do
		parent = parent[path[i]]
		if type(parent) ~= "table" then
			return false
		end
	end

	if type(value) == "table" then
		value = DeepCopy(value)
	end

	-- Validate the whole top-level value as it would be after the write
	local leaf = path[#path]
	local old = parent[leaf]
	parent[leaf] = value
	local valid = IsSerializable(profile.Data[first], 0)
	parent[leaf] = old

	if not valid then
		warn(`[DataService] rejected unsaveable value at {table.concat(path :: { any }, ".")} for {player.UserId}`)
		return false
	end

	local replica = Replicas[player]
	if replica then
		replica:Set(path, value)
	else
		parent[leaf] = value
	end

	return true
end

function DataService:Update(player: Player, key: string, callback: (current: any) -> any): boolean
	local current = self:Get(player, key)

	if current == nil then
		return false
	end

	return self:Set(player, key, callback(current))
end

--//Admin API (used by Cmdr server commands; never expose to remotes directly)

-- Returns (copy of data, isLive). Live data if the player is in this server,
-- otherwise the last saved data. Yields for offline players.
function DataService:GetDataSnapshot(userId: number): (any, boolean)
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and Profiles[player]
	if profile then
		return DeepCopy(profile.Data), true
	end

	local ok, saved = pcall(function()
		return PlayerStore:GetAsync(ProfileKey(userId))
	end)
	if ok and saved then
		return DeepCopy(saved.Data), false
	end
	return nil, false
end

-- Parses a raw string to the key's template type and sets it. Returns (ok, message).
function DataService:AdminSet(player: Player, key: string, raw: string): (boolean, string)
	if key == "DataVersion" then
		return false, "DataVersion is managed by migrations and can't be edited."
	end
	local template = Template[key]
	if template == nil then
		return false, `Unknown key '{key}'.`
	end

	local parsed, value = ParseAs(template, raw)
	if not parsed then
		return false, `'{raw}' is not a valid {type(template)} for {key}.`
	end

	local ok, reason = TrySet(player, key, value)
	if not ok then
		return false, `Rejected {key}: {reason}.`
	end
	return true, `Set {player.Name}.{key} = {raw}`
end

function DataService:ResetKey(player: Player, key: string): (boolean, string)
	if key == "DataVersion" then
		return false, "DataVersion can't be reset."
	end
	if Template[key] == nil then
		return false, `Unknown key '{key}'.`
	end

	local ok, reason = TrySet(player, key, DeepCopy(Template[key]))
	if not ok then
		return false, `Could not reset {key}: {reason}.`
	end
	return true, `Reset {player.Name}.{key} to default.`
end

-- Permanently deletes a player's saved data (GDPR erasure / full reset).
-- Yields up to ~1.5 minutes. Returns (ok, message).
function DataService:WipeAsync(userId: number): (boolean, string)
	if WipesInProgress[userId] then
		return false, "A wipe for this user is already running."
	end

	WipesInProgress[userId] = true
	local ok, success, message = pcall(WipeInternal, userId)
	WipesInProgress[userId] = nil

	if not ok then
		return false, `Wipe errored: {success}`
	end
	return success, message
end

return DataService
