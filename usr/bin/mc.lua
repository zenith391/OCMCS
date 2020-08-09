package.loaded.server = nil
local server = require("server")
local json = require("json")
local uuid = require("uuid")
local filesystem = require("filesystem")
local thread = require("thread")

local loaded = {}
function api_require(name)
	if not loaded[name] then
		loaded[name] = dofile("/usr/bin/api/" .. name .. ".lua")
	end
	return loaded[name]
end

local pluginEvent = api_require("event")
local packets = api_require("packets")
local net = api_require("network")

local function generateEId()
	local max = math.pow(2, 31)
	local min = -max
	return math.floor(math.random(min, max))
end

local function writeChunkLight(stream, cx, cz, world)
	local ss = net.stringStream()
	net.writeVarInt(ss, cx)
	net.writeVarInt(ss, cz)

	net.writeVarInt(ss, 0) -- sky light mask
	net.writeVarInt(ss, 0) -- block light mask
	net.writeVarInt(ss, 0x3FFFFF) -- all empty sky light
	net.writeVarInt(ss, 0x3FFFFF) -- all empty block light

	net.writePacket(stream, {
		id = 0x25,
		data = ss.str
	})
end

local function writeChunkData(stream, cx, cz, world)
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
		biomeData[i] = 127 -- Void
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
	local palette = {
		[0] = 0,
		[8] = 1,
		[10] = 2,
		[33] = 3,
		[9] = 4
	}

	for y=0, 15 do
		for z=0, 15 do
			for x=0, 15 do
				local block = world.generator.block(cx*16+x, y, cz*16+z)
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

	net.writePacket(stream, {
		id = 0x22,
		data = ss.str
	})
end

local function sendFullChunk(stream, cx, cz, world)
	writeChunkData(stream, cx, cz, world)
	--writeChunkLight(stream, cx, cz, world)
end

local configuration = {
	maxPlayers = 50,
	world = {
		type = "flat",
		viewDistance = 8
	}
}

local serverStatus = {
	version = {
		name = "1.15.2",
		protocol = 578
	},
	players = {
		max = configuration.maxPlayers,
		online = 0,
		sample = {}
	},
	description = {
		text = "Test"
	}
}

local players = {}

local world = {
	levelType = "flat",
	renderDistance = configuration.world.viewDistance,
	spawnPosition = {0, 5, 0},
	generator = {
		height = function(x, z)
			return 3
		end,
		block = function(x, y, z)
			if y == 3 then
				return ((x % 3 == 0) and 8) or 9 -- grass block
			elseif y == 2 or y == 1 then
				return 10 -- dirt
			elseif y == 0 then
				return 33 -- bedrock
			else
				return 0 -- air
			end
		end
	},
	players = players,
	entities = {}
}

function world:broadcast(component)
	local chatPacket = packets.newChatMessagePacket(component, "chat")
	for k, player in pairs(self.players) do
		net.writePacket(player.socket, chatPacket)
	end
end

function world:setRaining(raining)
	local reason = (raining and 2) or 1
	local packet = packets.newGameStatePacket(reason, 0)
	for k, player in pairs(self.players) do
		net.writePacket(player.socket, packet)
	end
end

local packetHandlers = {
	[0x00] = function(stream, socket, client)
		if client.state == 0 then
			local ver = net.readVarInt(stream)
			local address = net.readString(stream)
			local port = net.readUnsignedShort(stream)
			local nextState = net.readVarInt(stream)
			client.state = nextState
		elseif client.state == 1 then
			local ss = net.stringStream()
			net.writeString(ss, json.encode(serverStatus))
			net.writePacket(socket, {
				id = 0x00, -- response
				data = ss.str
			})
		elseif client.state == 2 then
			local name = net.readString(stream)
			print(name .. " is logging in..")
			local ss = net.stringStream()
			local id = uuid.next()
			print("Attributing UUID " .. id .. " to " .. name)
			net.writeString(ss, id)
			net.writeString(ss, name)
			net.writePacket(socket, {
				id = 0x02, -- login success
				data = ss.str
			})

			ss = net.stringStream()
			local eid = generateEId()
			local gamemode = 1
			local dimension = 0
			players[id] = setmetatable({
				uuid = id,
				name = name,
				gamemode = gamemode,
				dimension = dimension,
				entityId = eid,
				socket = socket,
				world = world
			}, {__index = api_require("player")})
			world.entities[eid] = {
				x = world.spawnPosition.x,
				y = world.spawnPosition.y,
				z = world.spawnPosition.z
			}
			client.player = players[id]
			net.writeInt(ss, eid)
			net.writeUnsignedByte(ss, gamemode)
			net.writeInt(ss, dimension)
			net.writeLong(ss, 0) -- not init the hashed seed
			net.writeUnsignedByte(ss, serverStatus.players.max)
			net.writeString(ss, world.levelType)
			net.writeVarInt(ss, world.renderDistance)
			net.writeBoolean(ss, false) -- debug info is not reduced
			net.writeBoolean(ss, true) -- respawn screen disabled
			net.writePacket(socket, {
				id = 0x26, -- join game
				data = ss.str
			})

			ss = net.stringStream()
			net.writeString(ss, "OCMCS")
			net.writePacket(socket, packets.newPluginMessagePacket("minecraft:brand", ss.str))

			net.writePacket(socket, packets.newPlayerAbilitiesPacket({
				flags = 0x01 | 0x04, -- is creative
				flyingSpeed = 0.05,
				fovModifier = 0.1
			}))

			pluginEvent.send("player_join", players[id])

			client.state = 3
		elseif client.state == 3 then
			local teleportId = net.readVarInt(stream)
			print("Player successfully teleported with ID " .. teleportId)
		end
	end,
	[0x01] = function(stream, socket, client) -- ping
		local payload = stream:read(8)
		net.writePacket(socket, {
			id = 0x01, -- pong
			data = payload
		})
	end,
	[0x03] = function(stream, socket, client) -- chat message
		local msg = net.readString(stream)
		local name = client.player.name
		pluginEvent.send("player_chat", client.player, msg)
	end,
	[0x05] = function(stream, socket, client) -- client settings
		local function count(t)
			local n = 0
			for _ in pairs(t) do n = n + 1 end
			return n
		end

		local ss = net.stringStream()
		net.writeUnsignedByte(ss, 0) -- slot 2
		net.writePacket(socket, {
			id = 0x40, -- held item change
			data = ss.str
		})

		net.writePacket(socket, packets.newEntityStatusPacket(client.player.entityId, 28))
		net.writePacket(socket, packets.newPlayerPositionAndRotationPacket(world.spawnPosition, 0, 0))

		-- currently packet data is ignored
		ss = net.stringStream()
		net.writeVarInt(ss, 0) -- add player
		net.writeVarInt(ss, count(players))
		print(count(players) .. " players")

		for k, player in pairs(players) do
			net.writeUUID(ss, player.uuid)
			net.writeString(ss, player.name)
			net.writeVarInt(ss, 0) -- 0 properties
			net.writeVarInt(ss, player.gamemode)
			net.writeVarInt(ss, -1) -- unknown ping
			net.writeBoolean(ss, false) -- no display name
		end

		net.writePacket(socket, {
			id = 0x34,
			data = ss.str
		})

		ss = net.stringStream()
		net.writeVarInt(ss, 0)
		net.writeVarInt(ss, 0)
		net.writePacket(socket, {
			id = 0x41, -- update view position
			data = ss.str
		})

		for x=-2, 2 do
			for y=-2,2 do
				sendFullChunk(socket, x, y, world)
			end
		end

		ss = net.stringStream()
		net.writePosition(ss, world.spawnPosition)
		net.writePacket(socket, {
			id = 0x4E, -- spawn position
			data = ss.str
		})
		net.writePacket(socket, packets.newPlayerPositionAndRotationPacket(world.spawnPosition, 0, 0))
	end,
	[0x0B] = function(stream, socket, client) -- plugin message
		local identifier = net.readString(stream)
		print("Client message to channel " .. identifier)
		pluginEvent.send("plugin_channel", identifier)
	end,
	[0x11] = function(stream, socket, client) -- player position
		local x = net.readDouble(stream)
		local y = net.readDouble(stream)
		local z = net.readDouble(stream)
		local world = client.player.world
		print("Player move to " .. x .. ", " .. y .. ", " .. z)
		pluginEvent.send("player_move", client.player, x, y, z)
		pluginEvent.send("entity_move", world.entities[client.player.entityId], x, y, z)
	end,
	[0x11] = function(stream, socket, client) -- player rotation
		-- TODO read
	end,
	[0x12] = function(stream, socket, client) -- player position and rotation
		local x = net.readDouble(stream)
		local y = net.readDouble(stream)
		local z = net.readDouble(stream)
		local world = client.player.world
		pluginEvent.send("player_move", client.player, x, y, z)
		pluginEvent.send("entity_move", world.entities[client.player.entityId], x, y, z)
		print("Player move to " .. x .. ", " .. y .. ", " .. z)
	end,
	[0x13] = function(stream, socket, client) -- player rotation
		-- TODO read
	end,
	[0x14] = function(stream, socket, client) -- player movement
		local onGround = net.readBoolean(stream)
	[0x19] = function(stream, socket, client) -- player abilities
		local flags = net.readUnsignedByte(stream)
	end,
	[0x1A] = function(stream, socket, client) -- player digging
		local status = net.readVarInt(stream)
		local location = net.readPosition(stream)
		local face = net.readUnsignedByte(stream)

		local packet = packets.newAcknowledgePlayerDiggingPacket(location, 0, status, true)
		net.writePacket(socket, packet)

		if status == 2 then -- broke block

		end
	end,
	[0x1B] = function(stream, socket, client) -- entity action

	end
}

print("Starting plugins..")

for file in filesystem.list("/usr/bin/plugins") do
	dofile("/usr/bin/plugins/" .. file)
end

print("Starting server on port 25565")
local serverSocket = server.open()
serverSocket:bind("MCServerOnOC")
serverSocket:listen()

print("Listening..")
while true do
	local socket = serverSocket:accept()
	local client = {
		state = 0
	}
	while true do
		serverSocket:pollState()
		if socket:isClosed() then
			break
		end
		local packet = net.readPacket(socket)
		print("Packet ID: " .. string.format("0x%x", packet.id))
		if not packetHandlers[packet.id] then
			error("missing packet handler for id " .. string.format("0x%x", packet.id))
		end
		packetHandlers[packet.id](packet.dataStream, socket, client)
		local id = require("event").pull(0)
		print("event: " .. tostring(id))
	end
end
