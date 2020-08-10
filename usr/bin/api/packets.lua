local packets = {}
local json = require("json")
local net = api_require("network")

function packets.newChatMessagePacket(chat, msgType)
	local numeralType = 0
	if msgType == "system" then
		numeralType = 1
	elseif msgType == "game" then
		numeralType = 2
	end

	local ss = net.stringStream()
	net.writeString(ss, json.encode(chat))
	net.writeUnsignedByte(ss, numeralType)
	return {
		id = 0x0F,
		data = ss.str
	}
end

function packets.newGameStatePacket(reason, value)
	local ss = net.stringStream()
	net.writeUnsignedByte(ss, reason)
	net.writeFloat(ss, value)
	return {
		id = 0x1F,
		data = ss.str
	}
end

function packets.newAcknowledgePlayerDiggingPacket(location, block, status, successful)
	local ss = net.stringStream()
	net.writePosition(ss, location)
	net.writeVarInt(ss, block)
	net.writeVarInt(ss, status)
	net.writeBoolean(ss, successful)
	return {
		id = 0x08,
		data = ss.str
	}
end

function packets.newEntityStatusPacket(eid, status)
	local ss = net.stringStream()
	net.writeInt(ss, eid)
	net.writeUnsignedByte(ss, status)
	return {
		id = 0x1C,
		data = ss.str
	}
end

function packets.newPluginMessagePacket(channelId, data)
	local ss = net.stringStream()
	net.writeString(ss, channelId)
	ss:write(data)
	return {
		id = 0x19,
		data = ss.str
	}
end

function packets.newPlayerPositionAndRotationPacket(pos, yaw, pitch)
	local ss = net.stringStream()
	net.writeDouble(ss, pos[1])
	net.writeDouble(ss, pos[2])
	net.writeDouble(ss, pos[3])
	net.writeFloat(ss, yaw) -- yaw
	net.writeFloat(ss, pitch) -- pitch
	net.writeUnsignedByte(ss, 0) -- flags
	net.writeVarInt(ss, 0) -- teleport id

	return {
		id = 0x36, -- player position and look
		data = ss.str
	}
end


function packets.newPlayerAbilitiesPacket(abilities)
	local ss = net.stringStream()
	net.writeUnsignedByte(ss, abilities.flags)
	net.writeFloat(ss, abilities.flyingSpeed)
	net.writeFloat(ss, abilities.fovModifier)
	return {
		id = 0x32,
		data = ss.str
	}
end

function packets.newKeepAlivePacket(id)
	id = id or math.floor(math.random() * math.pow(1, 60))
	local ss = net.stringStream()
	net.writeLong(ss, id)
	return {
		id = 0x21,
		data = ss.str
	}
end

function packets.newEntityTeleportPacket(entity)
	local ss = net.stringStream()
	
	net.writeVarInt(ss, entity.id)
	net.writeDouble(ss, entity.x)
	net.writeDouble(ss, entity.y)
	net.writeDouble(ss, entity.z)
	net.writeAngle(ss, 0)
	net.writeAngle(ss, 0)
	net.writeBoolean(ss, entity.onGround)

	return {
		id = 0x57,
		data = ss.str
	}
end

function packets.newSpawnPlayerPacket(player)
	local ss = net.stringStream()
	local entity = player.world.entities[player.entityId]
	
	net.writeVarInt(ss, player.entityId)
	net.writeUUID(ss, player.uuid)
	net.writeDouble(ss, entity.x)
	net.writeDouble(ss, entity.y)
	net.writeDouble(ss, entity.z)
	net.writeAngle(ss, 0)
	net.writeAngle(ss, 0)

	return {
		id = 0x05,
		data = ss.str
	}
end

function packets.newBlockChangePacket(location, id)
	local ss = net.stringStream()
	
	net.writePosition(ss, location)
	net.writeVarInt(ss, id)

	return {
		id = 0x0C,
		data = ss.str
	}
end

return packets
