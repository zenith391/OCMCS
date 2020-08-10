local player = {}
local net = api_require("network")
local packets = api_require("packets")

function player:setGamemode(gamemode)
	local packet = packets.newGameStatePacket(3, gamemode)
	net.writePacket(self.socket, packet)
end

function player:disconnect()
	ss = net.stringStream()
	net.writeVarInt(ss, 4) -- remove player
	net.writeVarInt(ss, 1)
	net.writeUUID(ss, self.uuid)

	local removePacket = {
		id = 0x34, -- player info
		data = ss.str
	}

	for k, p in pairs(self.world.players) do
		if p == self then
			--self.world.players[k] = nil
		else
			net.writePacket(p.socket, removePacket)
		end
	end
end

return player
