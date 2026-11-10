--!strict
return {
	Name = "setdata",
	Aliases = { "sd" },
	Description = "Set a data key for a player in this server. Value is parsed to the key's type (number/true/false/text, JSON for tables).",
	Group = "DataAdmin",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Player in this server",
		},
		{
			Type = "dataKey",
			Name = "key",
			Description = "Data key",
		},
		{
			Type = "string",
			Name = "value",
			Description = "New value",
		},
	},
}
