--!strict
-- "dataKey" argument type: autocompletes editable keys from the data template.
-- Replicated to the client, so the template lives in ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataTemplate = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DataTemplate"))

return function(registry)
	local keys = {}
	for key in DataTemplate do
		if key ~= "DataVersion" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)

	registry:RegisterType("dataKey", registry.Cmdr.Util.MakeEnumType("dataKey", keys))
end
