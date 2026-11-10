--!strict
--[[
	Who counts as an admin, based on AdminList.luau (no Roblox group lookups).
	The result is stored in the server-set "IsAdmin" player attribute, which the
	Cmdr permission hook reads on both client and server. Clients can't change
	server-side attributes, so the server check is authoritative.
]]

local RunService = game:GetService("RunService")

local AdminList = require(script.Parent.AdminList)

local Admins = {}

function Admins.Compute(player: Player): boolean
	-- Studio: the real logged-in developer has a positive UserId; local test
	-- clients ("Players: 2" etc.) are negative, so they can test as non-admins.
	-- Note: Team Create collaborators are also positive, so they're admins in Studio.
	if RunService:IsStudio() and player.UserId > 0 then
		return true
	end

	if AdminList.Admins[player.UserId] ~= nil then
		return true
	end

	if AdminList.IncludeGameOwner and game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end

	return false
end

function Admins.Assign(player: Player)
	player:SetAttribute("IsAdmin", Admins.Compute(player))
end

function Admins.IsAdmin(player: Player): boolean
	return player:GetAttribute("IsAdmin") == true
end

return Admins
