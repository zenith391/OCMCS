local net = {}

function net.stringToStream(str)
	local pos = 1
	local stream = {
		read = function(self, len)
			local part = str:sub(pos, pos+len-1)
			pos = pos + len
			return part
		end
	}
	return stream
end

function net.stringStream()
	local stream = {
		write = function(self, value)
			self.str = self.str .. value
		end
	}
	stream.str = ""
	return stream
end

function net.readUnsignedByte(stream)
	return string.byte(stream:read(1))
end

function net.readUnsignedShort(stream)
	return (net.readUnsignedByte(stream) << 8) |
		net.readUnsignedByte(stream)
end

function net.readBoolean(stream)
	return string.byte(stream:read(1)) ~= 0
end

function net.readFloat(stream)
	return string.unpack(">f", stream:read(4))
end

function net.readDouble(stream)
	return string.unpack(">d", stream:read(8))
end

function net.readUnsignedLong(stream)
	return string.unpack(">I8", stream:read(8))
end

function net.writeUnsignedByte(stream, num)
	stream:write(string.char(num))
end

function net.writeBoolean(stream, bool)
	net.writeUnsignedByte(stream, ((bool==false) and 0) or 1)
end

function net.writeShort(stream, num)
	stream:write(string.pack(">i2", num))
end

function net.writeInt(stream, num)
	stream:write(string.pack(">i4", num))
end

function net.writeUnsignedInt(stream, num)
	stream:write(string.pack(">I4", num))
end

function net.writeUnsignedLong(stream, num)
	stream:write(string.pack(">I8", num))
end

function net.writeLong(stream, num)
	stream:write(string.pack(">i8", num))
end

function net.writeDouble(stream, num)
	stream:write(string.pack(">d", num))
end

function net.writeFloat(stream, num)
	stream:write(string.pack(">f", num))
end

function net.writeNBTString(stream, str)
	stream:write(string.pack(">I2", #str))
	stream:write(str)
end

function net.writeAngle(stream, angle)
	while angle < -180 do
		angle = angle + 360
	end
	angle = angle % 360
	local byte = math.floor((angle / 360) * 255)
	stream:write(string.char(byte))
end

function net.writeUUID(stream, uuid)
	local p1 = tonumber(uuid:sub(1,8), 16)
	local p2 = tonumber(uuid:sub(10,13) .. uuid:sub(15,18), 16)
	local p3 = tonumber(uuid:sub(20,23) .. uuid:sub(25,28), 16)
	local p4 = tonumber(uuid:sub(29), 16)
	net.writeUnsignedInt(stream, p1)
	net.writeUnsignedInt(stream, p2)
	net.writeUnsignedInt(stream, p3)
	net.writeUnsignedInt(stream, p4)
end

function net.writePosition(stream, pos)
	local num = ((pos[1] & 0x3FFFFFF) << 38) | ((pos[3] & 0x3FFFFFF) << 12) | (pos[2] & 0xFFF)
	net.writeLong(stream, num)
end

function net.readVarInt(stream)
	local result = 0
	local read = 0
	local numRead = 0
	repeat
		read = string.byte(stream:read(1))
		local value = read & 0x7F
		result = result | (value << (7 * numRead))
		numRead = numRead + 1
		if numRead > 5 then
			error("varint is too big")
		end
	until (read & 0x80) == 0
	return result, numRead
end

function net.writeVarInt(stream, value)
	if value & 0x8000000000000000 ~= 0 then -- 64-bit negative number
		value = value | 0x80000000
	end
	value = value & 0xFFFFFFFF
	repeat
		local temp = value & 0x7F
		value = value >> 7;
		if value ~= 0 then
			temp = temp | 0x80
		end
		stream:write(string.char(temp))
	until value == 0
end

function net.readNBT(stream)
	local tag = net.readUnsignedByte(stream)
	if tag == 0 then -- TAG_End
		return nil
	end
	local nameLen = net.readUnsignedShort(stream)
	local name = stream:read(nameLen)
	if tag == 10 then -- TAG_Compound
		local compound = {}
		while true do
			local val, valName = net.readNBT(stream)
			if not val then
				break
			else
				compound[valName] = val
			end
		end
		return compound, name
	end
end

function net.readSlot(stream)
	local present = net.readBoolean(stream)
	local itemID, count, nbt
	if present then
		itemID = net.readVarInt(stream)
		count = net.readUnsignedByte(stream)
		nbt = net.readNBT(stream)
	end
	return {
		present = present,
		id = itemID,
		count = count,
		nbt = nbt
	}
end

function net.readPosition(stream)
	local value = net.readUnsignedLong(stream)
	local x = value >> 38;
	local y = value & 0xFFF;
	local z = (value << 26 >> 38)
	if x >= 2^25 then x=x-2^26 end
	if y >= 2^11 then y=y-2^12 end
	if z >= 2^25 then z=z-2^26 end
	return {math.floor(x), math.floor(y), math.floor(z)}
end

function net.readString(stream)
	local size = net.readVarInt(stream)
	return stream:read(size) -- TODO convert to unicode
end

function net.writeString(stream, str)
	net.writeVarInt(stream, #str)
	stream:write(str)
end

function net.readPacket(stream)
	local length = net.readVarInt(stream)
	local packetId, byteLen = net.readVarInt(stream)
	local data = stream:read(length-byteLen)
	return {
		length = length,
		id = packetId,
		data = data,
		dataStream = net.stringToStream(data)
	}
end

function net.writePacket(stream, packet)
	local ss = net.stringStream()
	net.writeVarInt(ss, #packet.data + 1) -- length
	net.writeVarInt(ss, packet.id)
	ss:write(packet.data)
	stream:write(ss.str)
end

return net
