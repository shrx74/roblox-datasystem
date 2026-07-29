local Players = game:GetService("Players")
local DataService = require(script.Services.DataService)

DataService:init(false)

Players.PlayerAdded:Connect(function(player: Player)
	DataService:WaitForData(player) --yield for player data load
end)
