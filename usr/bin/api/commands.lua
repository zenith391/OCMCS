local commands = {}

function commands.execute(cmd, player)
	player:send("You did command : /" .. cmd)
end

return commands
