--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)

return function(_context, player: Player, key: string)
	local _, message = DataService:ResetKey(player, key)
	return message
end
