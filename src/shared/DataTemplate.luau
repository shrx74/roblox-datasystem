--!strict
--[[
	Default player data. Shared (ReplicatedStorage) so Cmdr's client-side
	autocomplete can list keys; it contains no secrets.

	Rules:
	- Every key's default value defines its type; DataService:Set rejects other types.
	  Extra value rules (integer, min/max) live in DataRules.luau.
	- Bump DataVersion and add a migration in DataService when renaming a key
	  or changing a key's type. Adding a new key needs no migration (Reconcile fills it).
]]

export type PlayerData = {
	DataVersion: number,
	FirstLoginTime: number, -- os.time() of first join, 0 = never set
	TimePlayed: number, -- total seconds
}

local DataTemplate: PlayerData = {
	DataVersion = 1,
	FirstLoginTime = 0,
	TimePlayed = 0,
}

return DataTemplate
