--//Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--//Modules
local Signal = require(ReplicatedStorage.Packages.Signal)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local ReplicaServer = require(ServerScriptService.ServerPackages.ReplicaServer)
local DataTemplate = require(script:WaitForChild("DataTemplate"))

--//Setup
local PlayerToken = ReplicaServer.Token("PlayerData")
local LiveVersion = 0
local TestVersion = 1
local StoreName = RunService:IsStudio() and "PlayerTest_v" .. TestVersion or "PlayerLive_v" .. LiveVersion
local PlayerStore = ProfileStore.New(StoreName, DataTemplate)

local _LeaderstatsConfig = {} --any keys from player data added here will show up in leaderstats

--/Private Functions
local DataService = {}
DataService.ProfileLoaded = Signal.new()
DataService.Profiles = {}
DataService.Replicas = {}
DataService.Leaderstats = {}

local function CreateLeaderstats(player: Player, profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local stats = {}

	for key, valueType in _LeaderstatsConfig do
		local instance = Instance.new(valueType)
		instance.Name = key
		instance.Value = profile.Data[key]
		instance.Parent = folder
		stats[key] = instance
	end

	folder.Parent = player
	DataService.Leaderstats[player] = stats
end

local function OnProfileLoad(player: Player, profile)
	if profile.Data.FirstLoginTime == "None" then
		DataService:Set(player, "FirstLoginTime", tick())
	end

	DataService:Set(player, "JoinTime", tick())
end

local function OnPlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			DataService.Profiles[player] = nil
			player:Kick("Data error occured. Please rejoin.")
		end)

		if player.Parent == Players then
			DataService.Profiles[player] = profile

			task.spawn(OnProfileLoad, player, profile)

			local replica = ReplicaServer.New({
				Token = PlayerToken,
				Tags = { UserId = player.UserId },
				Data = profile.Data,
			})

			DataService.Replicas[player] = replica
			replica:Subscribe(player)

			CreateLeaderstats(player, profile)

			DataService.ProfileLoaded:Fire(player, profile)
		else
			profile:EndSession()
		end
	else
		player:Kick("Data error occured. Please rejoin.")
	end
end

local function OnPlayerRemoving(player: Player)
	local profile = DataService.Profiles[player]
	if profile then
		DataService:Update(player, "TimePlayed", function(n)
			return n + (tick() - DataService:Get(player, "JoinTime"))
		end)

		profile:EndSession()
		DataService.Profiles[player] = nil
	end

	if DataService.Replicas[player] then
		DataService.Replicas[player]:Destroy()
		DataService.Replicas[player] = nil
	end

	DataService.Leaderstats[player] = nil
end

--//Public Functions
function DataService:init(UseMock: boolean)
	if UseMock then
		PlayerStore = PlayerStore.Mock
	end

	--for players who might have joined before init
	for _, player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

--asynchronous function to ensure dataload before use of other helper functions
function DataService:WaitForData(player: Player)
	local profile = self.Profiles[player]
	if profile then
		return profile.Data
	end

	if player.Parent ~= Players then
		return nil
	end

	local result
	local connection
	connection = self.ProfileLoaded:Connect(function(loaderPlayer, loadedProfile)
		if loaderPlayer == player then
			result = loadedProfile
			connection:Disconnect()
		end
	end)

	while result == nil and player.Parent == Players do
		task.wait()
	end

	if connection then
		connection:Disconnect()
		connection = nil
	end

	return result and result.Data or nil
end

function DataService:Get(player: Player, key: string)
	local profile = self.Profiles[player]
	if profile and profile.Data then
		return profile.Data[key]
	end
	return nil
end

function DataService:Set(player: Player, key: string, value: any): boolean
	local profile = self.Profiles[player]

	if not profile or not profile.Data then
		return false
	end

	if profile.Data[key] == nil then
		return false
	end

	profile.Data[key] = value

	if self.Replicas[player] then
		self.Replicas[player]:Set({ key }, value)
	end

	if self.Leaderstats[player] and self.Leaderstats[player][key] then
		self.Leaderstats[player][key].Value = value
	end

	return true
end

function DataService:Update(player: Player, key: string, callback): boolean
	local current = self:Get(player, key)

	if current == nil then
		return false
	end

	return self:Set(player, key, callback(current))
end

return DataService
