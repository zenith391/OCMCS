local world = {}
local net = api_require("network")
local packets = api_require("packets")
local event = api_require("event")

function world:broadcast(component)
	local chatPacket = packets.newChatMessagePacket(component, "chat")
	for k, player in pairs(self.players) do
		net.writePacket(player.socket, chatPacket)
	end
end

function world:moveEntity(entity, x, y, z)
	entity.x = x
	entity.y = y
	entity.z = z
	event.send("entity_move", entity, x, y, z)
	if not entity.lastX then
		entity.lastX = 0
		entity.lastY = 0
		entity.lastZ = 0
	end
	local dx,dy,dz = entity.x-entity.lastX, entity.y-entity.lastY, entity.z-entity.lastZ
	local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
	if dist > 0.5 then
		entity.lastX = entity.x
		entity.lastY = entity.y
		entity.lastZ = entity.z
		local movePacket = packets.newEntityTeleportPacket(entity)
		for k, player in pairs(self.players) do
			if player.entityId ~= entity.id then
				net.writePacket(player.socket, movePacket)
			end
		end
	end
end

function world:rotateEntity(entity, yaw, pitch)
	entity.yaw = yaw
	entity.pitch = pitch
	event.send("entity_rotate", entity, yaw, pitch)

	local movePacket = packets.newEntityTeleportPacket(entity)
	for k, player in pairs(self.players) do
		if player.entityId ~= entity.id then
			net.writePacket(player.socket, movePacket)
		end
	end
end

function world:addPlayer(player)
	local ss = net.stringStream()
	net.writeVarInt(ss, 0) -- add player
	net.writeVarInt(ss, 1)

	net.writeUUID(ss, player.uuid)
	net.writeString(ss, player.name)
	net.writeVarInt(ss, 0) -- 0 properties
	net.writeVarInt(ss, player.gamemode)
	net.writeVarInt(ss, -1) -- unknown ping
	net.writeBoolean(ss, false) -- no display name

	local addPacket = {
		id = 0x34, -- player info
		data = ss.str
	}
	local spawnPacket = packets.newSpawnPlayerPacket(player)

	for k, player in pairs(self.players) do
		net.writePacket(player.socket, addPacket)
		net.writePacket(player.socket, spawnPacket)
	end
	self.players[player.uuid] = player
end

function world:setBlock(location, id)
	local x,y,z = location[1], location[2], location[3]
	local name = x..","..y..","..z
	if self.changedBlocks[name] then
		self.changedBlocks[name].newId = id
	else
		self.changedBlocks[name] = {
			x = location[1],
			y = location[2],
			z = location[3],
			newId = id
		}
	end

	local changePacket = packets.newBlockChangePacket(location, id)
	for k, player in pairs(self.players) do
		net.writePacket(player.socket, changePacket)
	end
end

function world:setRaining(raining)
	local reason = (raining and 2) or 1
	local packet = packets.newGameStatePacket(reason, 0)
	for k, player in pairs(self.players) do
		net.writePacket(player.socket, packet)
	end
end

return world
