--!strict
--//Services
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

--//Modules
local Cmdr = require(ServerScriptService.ServerPackages.Cmdr) :: any
local Admins = require(script.Admins)

local AdminCommands = {}

function AdminCommands:init()
	-- Admin status must be assigned before anyone can run commands
	for _, player in Players:GetPlayers() do
		task.spawn(Admins.Assign, player)
	end
	Players.PlayerAdded:Connect(Admins.Assign)

	-- Permission hook first, so no command is ever registered without it
	Cmdr:RegisterHooksIn(script.Hooks)
	Cmdr:RegisterTypesIn(script.Types) -- before commands that use custom types
	Cmdr:RegisterDefaultCommands()
	Cmdr:RegisterCommandsIn(script.Commands)
end

return AdminCommands
