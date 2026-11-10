--!strict
return {
	Name = "resetkey",
	Aliases = {},
	Description = "Reset one data key to its default value for a player in this server.",
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
	},
}
