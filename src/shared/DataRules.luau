--!strict
--[[
	Per-key value rules enforced by DataService:Set for every caller (gameplay and admin).
	Kept separate from DataTemplate because the template is saved into every profile.

	Number rules: Integer, Min, Max. String rules: MaxLength.
	Keys without an entry only get the type + serializability checks.
]]

export type Rule = {
	Integer: boolean?,
	Min: number?,
	Max: number?,
	MaxLength: number?,
}

local DataRules: { [string]: Rule } = {
	DataVersion = { Integer = true, Min = 0 },
	FirstLoginTime = { Integer = true, Min = 0 },
	TimePlayed = { Integer = true, Min = 0, Max = 2 ^ 40 },
}

return DataRules
