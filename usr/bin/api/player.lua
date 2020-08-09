local player = {}
local net = api_require("network")
local packets = api_require("packets")

function player:setGamemode(gamemode)
	local packet = packets.newGameStatePacket(3, gamemode)
	net.writePacket(self.socket, packet)
end

return player
