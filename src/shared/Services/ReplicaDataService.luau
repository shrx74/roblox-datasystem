local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicaClient = require(ReplicatedStorage.Packages.ReplicaClient)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ReplicaDataService = {}

function ReplicaDataService:init()
	self.replicaLoaded = Signal.new()
	self.callbacks = {}

	ReplicaClient.OnNew("PlayerData", function(replica)
		self.replicaData = replica.Data
		self.replicaLoaded:Fire()

		for key, _ in self.replicaData do
			replica:OnSet({ key }, function(newval, oldval)
				if self.callbacks[key] then
					for _, callback in self.callbacks[key] do
						callback(newval, oldval)
					end
				end
			end)
		end
	end)

	ReplicaClient.RequestData()
end

function ReplicaDataService:Subscribe(key: string, callback)
	self:WaitForReplica()

	if self.replicaData[key] == nil then
		warn("method subscribe called on invalid key " .. key)
		return
	end

	self.callbacks[key] = self.callbacks[key] or {}
	table.insert(self.callbacks[key], callback)
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
