--!strict
-- Replicated to the client by Cmdr, so it must not require server-only modules.
-- Reads the server-set IsAdmin attribute (see AdminCommands/Admins.luau).
return function(registry)
	registry:RegisterHook("BeforeRun", function(context: any): string?
		if context.Executor == nil then
			return nil -- server-invoked
		end
		if context.Executor:GetAttribute("IsAdmin") ~= true then
			return "You do not have permission to run commands."
		end
		return nil
	end)

	registry:RegisterHook("AfterRun", function(context: any): string?
		if context.Executor then
			print(("[Cmdr] %s (%d) ran: %s"):format(
				context.Executor.Name,
				context.Executor.UserId,
				tostring(context.RawText or context.Name)
			))
		end
		return nil
	end)
end
