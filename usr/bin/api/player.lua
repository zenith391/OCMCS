local player = {}
local net = api_require("network")
local packets = api_require("packets")

function player:setGamemode(gamemode)
	local packet = packets.newGameStatePacket(3, gamemode)
	net.writePacket(self.socket, packet)
end

function player:kick(chat)
	if type(chat) == "string" then
		chat = {
			text = chat
		}
	end
	net.writePacket(self.socket, packets.newDisconnectPacket(chat))
	self:disconnect()
	self.socket:close()
end

function player:send(chat)
	if type(chat) == "string" then
		chat = {
			text = chat
		}
	end

	net.writePacket(self.socket, packets.newChatMessagePacket(component))
end

function player:disconnect()
	local ss = net.stringStream()
	net.writeVarInt(ss, 4) -- remove player
	net.writeVarInt(ss, 1)
	net.writeUUID(ss, self.uuid)

	local removePacket = {
		id = 0x34, -- player info
		data = ss.str
	}

	self.world.players[self.uuid] = nil
	for k, p in pairs(self.world.players) do
		if p ~= self then
			net.writePacket(p.socket, removePacket)
		end
	end

	self.world:broadcast({
		text = self.name .. " left the game.",
		color = "yellow"
	})
end

function player:updateViewPosition()
	if not self.ocx then
		self.ocx = 0
		self.ocz = 0
	end

	local entity = self.world.entities[self.entityId]
	local cx = entity.x // 16
	local cz = entity.z // 16

	if cx ~= self.ocx or cz ~= self.ocz then
		local packet = packets.newUpdateViewPositionPacket(cx, cz)
		net.writePacket(self.socket, packet)
		self.ocx = cx
		self.ocz = cz
	end
end

function player:ensureChunksLoaded()
	local entity = self.world.entities[self.entityId]
	local ecx = entity.x // 16
	local ecz = entity.z // 16
	for cx=-2, 2 do
		for cz=-2, 2 do
			local tcx, tcz = cx+ecx, cz+ecz
			for k, loaded in pairs(self.loadedChunks) do
				if loaded.x == tcx and loaded.z == tcz then
					goto continue
				end
			end
			--print(tcx .. ", " .. tcz .. " not loaded")
			local data = packets.newChunkDataPacket(tcx, tcz, self.world)
			net.writePacket(self.socket, data)
			table.insert(self.loadedChunks, {x = tcx, z = tcz})
			::continue::
		end
	end
end

return player
