--!strict
--[[
	Admin list. This is the ONLY place admins are defined.

	Lives in ServerScriptService, so it never replicates to clients (players
	can't see who the admins are). Changes take effect for players who join
	after the server starts with the new list (i.e. after you publish).

	Find a UserId in a player's profile URL: roblox.com/users/<UserId>/profile
]]

export type AdminList = {
	-- Also treat the game's owner as admin (user-owned games only).
	IncludeGameOwner: boolean,
	-- UserId -> note (the note is just for you, e.g. their username)
	Admins: { [number]: string },
}

local AdminList: AdminList = {
	IncludeGameOwner = true,

	Admins = {
		-- [123456789] = "MyUsername",
		-- [987654321] = "TrustedModerator",
	},
}

return AdminList
