--!strict
local DataService = require(script.Services.DataService)
local AdminCommands = require(script.AdminCommands)

DataService:init(false)
AdminCommands:init()

-- Other server systems: call DataService:WaitForData(player) before reading data;
-- it returns nil if the player left or their data failed to load.
