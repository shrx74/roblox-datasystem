--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)

return function(context, userId: number, confirm: string)
	if confirm ~= "CONFIRM" then
		return "Not wiped. Run again with CONFIRM as the last argument."
	end

	local executor = context.Executor
	warn(("[Cmdr] %s requested data wipe for UserId %d"):format(executor and executor.Name or "server", userId))

	local _, message = DataService:WipeAsync(userId)
	return message
end
