local event = api_require("event")
local packets = api_require("packets") 

event.on("player_join", function(_, player)
	player.world:broadcast({
		text = player.name .. " joined the game.",
		color = "yellow"
	})
end)

event.on("player_chat", function(_, player, message)
	player.world:broadcast({
		translate = "chat.type.text",
		with = {
			{
				text = player.name,
				clickEvent = {
					action = "suggest_command",
					value = "/msg " .. player.name
				},
				hoverEvent = {
					action = "show_entity",
					value = "{id:"..player.uuid..",name:"..player.name.."}"
				},
				insertion = player.name
			},
			{
				text = message
			}
		}
	})
end)

print("[Vanilla Minecraft] Ready!")
