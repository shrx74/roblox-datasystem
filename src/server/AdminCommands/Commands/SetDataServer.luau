--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)

return function(_context, player: Player, key: string, value: string)
	local _, message = DataService:AdminSet(player, key, value)
	return message
end
