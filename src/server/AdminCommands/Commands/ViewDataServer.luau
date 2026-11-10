--!strict
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Server.Services.DataService)

return function(_context, userId: number, key: string?)
	local data, isLive = DataService:GetDataSnapshot(userId)
	if data == nil then
		return ("No saved data found for UserId %d (or DataStores are unavailable)."):format(userId)
	end

	local value = if key then data[key] else data
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, value)

	return ("[%s] %d%s = %s"):format(
		if isLive then "live" else "saved",
		userId,
		if key then "." .. key else "",
		if ok then encoded else tostring(value)
	)
end
