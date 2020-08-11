local packets = {}
local json = require("json")
local net = api_require("network")

function packets.newChunkDataPacket(cx, cz, world)
	local ss = net.stringStream()
	net.writeInt(ss, cx)
	net.writeInt(ss, cz)
	local bitMask = 0x1
	net.writeBoolean(ss, true) -- full chunk
	net.writeVarInt(ss, bitMask)

	-- TODO write heightmap
	local heightmap = net.stringStream()
	net.writeUnsignedByte(heightmap, 10) -- TAG_Compound
	net.writeNBTString(heightmap, "") -- name of root compound
	net.writeUnsignedByte(heightmap, 12) -- TAG_Long_Array
	net.writeNBTString(heightmap, "MOTION_BLOCKING")
	net.writeInt(heightmap, 36) -- 256 9-bit entries -> 36 longs
	local heights = {}
	for x=1, 16 do
		for z=1, 16 do
			table.insert(heights, world.generator.height(x, z))
		end
	end
	local bits = {}
	for i=1, 16*16 do
		local v = heights[i]
		table.insert(bits, (v & 0x100) >> 8)
		table.insert(bits, (v & 0x80) >> 7)
		table.insert(bits, (v & 0x40) >> 6)
		table.insert(bits, (v & 0x20) >> 5)
		table.insert(bits, (v & 0x10) >> 4)
		table.insert(bits, (v & 0x08) >> 3)
		table.insert(bits, (v & 0x04) >> 2)
		table.insert(bits, (v & 0x02) >> 1)
		table.insert(bits, v & 0x01)
	end
	local long = 0
	local longBits = 0
	for i=1, #bits do
		local bit = bits[i]
		long = long << 1
		long = long | bit
		longBits = longBits + 1
		if longBits == 64 then
			net.writeUnsignedLong(heightmap, long)
			long = 0
			longBits = 0
		end
	end
	net.writeUnsignedByte(heightmap, 12) -- TAG_Long_Array
	net.writeNBTString(heightmap, "WORLD_SURFACE")
	net.writeInt(heightmap, 0)
	net.writeUnsignedByte(heightmap, 0) -- TAG_End (for the compound)
	ss:write(heightmap.str)

	local biomeData = {}
	for i=1, 1024 do
		biomeData[i] = 1 -- Plains
	end

	for k, v in pairs(biomeData) do
		net.writeInt(ss, v)
	end

	local sectStream = net.stringStream()

	-- palette
	local blockStates = {}
	local nonAirBlocks = 0
	local longs = {}
	local paletteBits = 4
	local usePalette = paletteBits ~= 14
	for i=1, 4096/(64/paletteBits) do longs[i] = 0 end
	local palette = {}
	local paletteInc = 0

	-- detect palette
	for y=0, 15 do
		for z=0, 15 do
			for x=0, 15 do
				local block = world.generator.block(cx*16+x, y, cz*16+z)
				local worldName = (cx*16+x) .. "," .. y .. "," .. (cz*16+z)
				if world.changedBlocks[worldName] then
					block = world.changedBlocks[worldName].newId
				end
				if not palette[block] then
					palette[block] = paletteInc
					paletteInc = paletteInc + 1
				end
			end
		end
	end

	for y=0, 15 do
		for z=0, 15 do
			for x=0, 15 do
				local block = world.generator.block(cx*16+x, y, cz*16+z)
				local worldName = (cx*16+x) .. "," .. y .. "," .. (cz*16+z)
				if world.changedBlocks[worldName] then
					block = world.changedBlocks[worldName].newId
				end

				local index = (((y*16)+z)*16)+x
				local value = (usePalette and palette[block]) or block
				
				local startLong = (index*paletteBits) // 64
				local startOffset = (index*paletteBits) % 64
				local endLong = ((index+1)*paletteBits-1) // 64
				longs[startLong+1] = longs[startLong+1] | (value << startOffset)
				if startLong ~= endLong then
					longs[endLong+1] = value >> (64 - startOffset)
				end

				if block ~= 0 then
					nonAirBlocks = nonAirBlocks + 1
				end
			end
		end
	end

	net.writeShort(sectStream, nonAirBlocks)
	net.writeUnsignedByte(sectStream, paletteBits)

	if usePalette then
		local keyPalette = {}
		local len = 0
		for k, v in pairs(palette) do
			keyPalette[v+1] = k
			len = len + 1
		end
		net.writeVarInt(sectStream, len)
		for k, v in ipairs(keyPalette) do
			net.writeVarInt(sectStream, v)
		end
	end
	net.writeVarInt(sectStream, #longs)
	for i=1, #longs do
		net.writeUnsignedLong(sectStream, longs[i])
	end

	net.writeVarInt(ss, #sectStream.str)
	ss:write(sectStream.str)
	net.writeVarInt(ss, 0) -- 0 block entities

	return {
		id = 0x22,
		data = ss.str
	}
end

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

function packets.newDisconnectPacket(chat)
	local ss = net.stringStream()
	net.writeString(ss, json.encode(chat))
	return {
		id = 0x1B,
		data = ss.str
	}
end

function packets.newUpdateViewPositionPacket(cx, cz)
	local ss = net.stringStream()
	net.writeVarInt(ss, cx)
	net.writeVarInt(ss, cz)
	return {
		id = 0x41,
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
	net.writeAngle(ss, entity.yaw)
	net.writeAngle(ss, entity.pitch)
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
