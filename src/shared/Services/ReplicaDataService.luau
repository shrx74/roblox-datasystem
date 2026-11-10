--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local ReplicaClient = require(Packages:WaitForChild("ReplicaClient")) :: any
local Signal = require(Packages:WaitForChild("Signal")) :: any

type Callback = (newValue: any, oldValue: any, path: { any }?) -> ()

local ReplicaDataService = {} :: { [string]: any }

function ReplicaDataService:init()
	self.replicaLoaded = Signal.new()
	self.callbacks = {}

	local function notify(key: string, newval: any, oldval: any, path: { any }?)
		local list: { Callback }? = self.callbacks[key]
		if not list then
			return
		end
		-- iterate a copy so callbacks can unsubscribe themselves
		for _, callback in table.clone(list) do
			task.spawn(callback, newval, oldval, path)
		end
	end

	ReplicaClient.OnNew("PlayerData", function(replica)
		self.replicaData = replica.Data
		self.replicaLoaded:Fire()

		-- top-level Set: callback(newValue, oldValue)
		for key, _ in self.replicaData do
			replica:OnSet({ key }, function(newval, oldval)
				notify(key, newval, oldval, nil)
			end)
		end

		-- nested changes (DataService:SetPath / table ops): callback(currentTopLevelValue, nil, path)
		replica:OnChange(function(_action, path)
			if #path > 1 then
				local key = path[1]
				notify(key, self.replicaData[key], nil, path)
			end
		end)
	end)

	ReplicaClient.RequestData()
end

-- Returns a function that unsubscribes the callback.
function ReplicaDataService:Subscribe(key: string, callback: Callback): () -> ()
	self:WaitForReplica()

	if self.replicaData[key] == nil then
		warn("method subscribe called on invalid key " .. key)
		return function() end
	end

	self.callbacks[key] = self.callbacks[key] or {}
	table.insert(self.callbacks[key], callback)

	return function()
		local list = self.callbacks[key]
		local index = list and table.find(list, callback)
		if index then
			table.remove(list, index)
		end
	end
end

function ReplicaDataService:Get(key: string)
	self:WaitForReplica()

	if self.replicaData[key] == nil then
		warn("Key " .. key .. " not found in player replica data.")
		return
	end

	return self.replicaData[key]
end

function ReplicaDataService:WaitForReplica()
	if self.replicaData then
		return self.replicaData
	end

	self.replicaLoaded:Wait()

	return self.replicaData
end

return ReplicaDataService
