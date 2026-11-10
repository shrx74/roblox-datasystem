--!strict
return {
	Name = "viewdata",
	Aliases = { "vd" },
	Description = "Show a player's data. Works for offline players (read-only saved copy).",
	Group = "DataAdmin",
	Args = {
		{
			Type = "playerId",
			Name = "player",
			Description = "Player name or UserId",
		},
		{
			Type = "dataKey",
			Name = "key",
			Description = "Only show this key",
			Optional = true,
		},
	},
}
