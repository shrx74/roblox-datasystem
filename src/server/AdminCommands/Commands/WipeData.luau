--!strict
return {
	Name = "wipedata",
	Aliases = {},
	Description = "PERMANENTLY delete all saved data for a player (GDPR erasure / full reset). Kicks them if online. Cannot be undone.",
	Group = "DataAdmin",
	Args = {
		{
			Type = "playerId",
			Name = "player",
			Description = "Player name or UserId",
		},
		{
			Type = "string",
			Name = "confirm",
			Description = "Type CONFIRM to proceed",
		},
	},
}
