local event = api_require("event")
local packets = api_require("packets") 

event.on("player_move", function(_, player, x, y, z)
	--player.world:broadcast({
	--	text = player.name .. " moved to " .. x .. ", " .. y .. ", " .. z
	--})
end)

print("[Test Plugin] Ready!")
