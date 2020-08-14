package.loaded.server = nil
local server = require("server")
local json = require("json")
local uuid = require("uuid")
local filesystem = require("filesystem")
local thread = require("thread")

local loaded = {}
local basePath = "/usr/bin" -- where the server is installed

function api_require(name)
	if not loaded[name] then
		loaded[name] = dofile(basePath .. "/api/" .. name .. ".lua")
	end
	return loaded[name]
end

local pluginEvent = api_require("event")
local packets = api_require("packets")
local net = api_require("network")
local commands = api_require("commands")
local nextEid = 0

local function generateEId()
	nextEid = nextEid + 1
	return nextEid
end

local function writeChunkLight(stream, cx, cz, world)
	-- TODO: re-do
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

local configuration = {
	maxPlayers = 50,
	world = {
		type = "custom",
		viewDistance = 4
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

local world = setmetatable({
	levelType = "flat",
	renderDistance = configuration.world.viewDistance,
	spawnPosition = {0, 5, 0},
	generator = dofile(basePath .. "/generators/" .. configuration.world.type .. ".lua"),
	changedBlocks = {},
	players = {},
	entities = {}
}, {
	__index = api_require("world") -- use API provided by "world"
})
world.spawnPosition = {0, world.generator.height(0, 0)+2, 0}

local packetHandlers = {
	[0x00] = function(stream, socket, client)
		if client.state == "handshake" then
			local ver = net.readVarInt(stream)
			local address = net.readString(stream)
			local port = net.readUnsignedShort(stream)
			local nextState = net.readVarInt(stream)
			if nextState == 1 then
				client.state = "status"
			elseif nextState == 2 then
				client.state = "login"
			else
				print("invalid next state: " .. nextState)
			end
		elseif client.state == "status" then
			local ss = net.stringStream()
			local sample = {}
			for k, v in pairs(world.players) do
				table.insert(sample, {
					name = v.name,
					id = v.uuid
				})
			end
			serverStatus.players.online = #sample
			serverStatus.players.sample = sample
			net.writeString(ss, json.encode(serverStatus))
			net.writePacket(socket, {
				id = 0x00, -- response
				data = ss.str
			})
		elseif client.state == "login" then
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
			
			world.entities[eid] = {
				x = world.spawnPosition[1],
				y = world.spawnPosition[2],
				z = world.spawnPosition[3],
				id = eid,
				yaw = 0,
				pitch = 0,
				onGround = true
			}
			world:addPlayer(setmetatable({
				uuid = id,
				name = name,
				gamemode = gamemode,
				dimension = dimension,
				entityId = eid,
				socket = socket,
				world = world,
				client = client,
				inventory = {},
				loadedChunks = {},
				selectedSlot = 0
			}, {
				__index = api_require("player") -- use API provided by "player"
			}))

			client.player = world.players[id]
			for i=1, 45 do
				client.player.inventory[i] = {
					present = false
				}
			end

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

			pluginEvent.send("player_join", world.players[id])

			client.state = "play"
		elseif client.state == "play" then
			local teleportId = net.readVarInt(stream)
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
		if msg:sub(1,1) == "/" then
			commands.execute(msg:sub(2), client.player)
			return
		end
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
		net.writeVarInt(ss, count(world.players))
		print(count(world.players) .. " players")

		for k, player in pairs(world.players) do
			net.writeUUID(ss, player.uuid)
			net.writeString(ss, player.name)
			net.writeVarInt(ss, 0) -- 0 properties
			net.writeVarInt(ss, player.gamemode)
			net.writeVarInt(ss, 200) -- unknown ping
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

		client.player:ensureChunksLoaded()

		ss = net.stringStream()
		net.writePosition(ss, world.spawnPosition)
		net.writePacket(socket, {
			id = 0x4E, -- spawn position
			data = ss.str
		})
		net.writePacket(socket, packets.newPlayerPositionAndRotationPacket(world.spawnPosition, 0, 0))

		for k, p in pairs(world.players) do
			if p ~= client.player then
				local spawnPacket = packets.newSpawnPlayerPacket(p)
				net.writePacket(socket, spawnPacket)
			end
		end
	end,
	[0x0A] = function(stream, socket, client) -- close window

	end,
	[0x0B] = function(stream, socket, client) -- plugin message
		local identifier = net.readString(stream)
		print("Client message to channel " .. identifier)
		pluginEvent.send("plugin_channel", identifier)
	end,
	[0x0F] = function(stream, socket, client) -- keep alive
		-- TODO use it for ping rate
	end,
	[0x11] = function(stream, socket, client) -- player position
		local x = net.readDouble(stream)
		local y = net.readDouble(stream)
		local z = net.readDouble(stream)
		local world = client.player.world
		local entity = world.entities[client.player.entityId]
		entity.onGround = net.readBoolean(stream)
		pluginEvent.send("player_move", client.player, x, y, z)
		world:moveEntity(entity, x, y, z)
		client.player:updateViewPosition()
		client.player:ensureChunksLoaded()
	end,
	[0x12] = function(stream, socket, client) -- player position and rotation
		local x = net.readDouble(stream)
		local y = net.readDouble(stream)
		local z = net.readDouble(stream)
		local world = client.player.world
		local entity = world.entities[client.player.entityId]
		local yaw = net.readFloat(stream)
		local pitch = net.readFloat(stream)
		entity.onGround = net.readBoolean(stream)
		pluginEvent.send("player_move", client.player, x, y, z)
		world:moveEntity(entity, x, y, z)
		world:rotateEntity(entity, yaw, pitch)
		client.player:updateViewPosition()
		client.player:ensureChunksLoaded()
	end,
	[0x13] = function(stream, socket, client) -- player rotation
		local entity = client.player.world.entities[client.player.entityId]
		local yaw = net.readFloat(stream)
		local pitch = net.readFloat(stream)
		entity.onGround = net.readBoolean(stream)
		world:rotateEntity(entity, yaw, pitch)
	end,
	[0x14] = function(stream, socket, client) -- player movement
		local onGround = net.readBoolean(stream)
		world.entities[client.player.entityId].onGround = onGround
	end,
	[0x19] = function(stream, socket, client) -- player abilities
		local flags = net.readUnsignedByte(stream)
	end,
	[0x1A] = function(stream, socket, client) -- player digging
		local status = net.readVarInt(stream)
		local location = net.readPosition(stream)
		local face = net.readUnsignedByte(stream)
		local player = client.player

		local packet = packets.newAcknowledgePlayerDiggingPacket(location, 0, status, true)
		net.writePacket(socket, packet)

		if status == 2 or (status == 0 and player.gamemode == 1) then -- broke block
			client.player.world:setBlock(location, 0) -- set air
		end
	end,
	[0x1B] = function(stream, socket, client) -- entity action

	end,
	[0x23] = function(stream, socket, client) -- held item change
		local selectedSlot = net.readUnsignedShort(stream)
		client.player.selectedSlot = selectedSlot
	end,
	[0x26] = function(stream, socket, client) -- creative inventory action
		local slotId = net.readUnsignedShort(stream)
		local item = net.readSlot(stream)
		local inv = client.player.inventory
		inv[slotId] = item
	end,
	[0x2A] = function(stream, socket, client) -- animation
		local hand = net.readVarInt(stream)
		-- TODO send animation to other players
	end,
	[0x2C] = function(stream, socket, client) -- player block placement
		local hand = net.readVarInt(stream)
		local location = net.readPosition(stream)
		local face = net.readVarInt(stream)
		local item = client.player.inventory[client.player.selectedSlot+36]

		if item.present then
			if face == 0 then -- top
				location[2] = location[2] - 1
			elseif face == 1 then -- bottom
				location[2] = location[2] + 1
			elseif face == 2 then -- north
				location[3] = location[3] - 1
			elseif face == 3 then -- south
				location[3] = location[3] + 1
			elseif face == 4 then -- west
				location[1] = location[1] - 1
			elseif face == 5 then -- east
				location[1] = location[1] + 1
			end
			local blockId = item.id
			if item.id >= 8 then
				blockId = blockId + 1
			end
			if item.id >= 11 then
				blockId = blockId + 1
			end
			print("set block " .. blockId .. " (item id = " .. item.id .. ")")
			client.player.world:setBlock(location, blockId)
		end
	end,
	[0x2D] = function(stream, socket, client) -- use item
	end
}

require("event").onError = function(...)
	io.stderr:write(...)
	io.stderr:write('\n')
end

print("Starting plugins..")

for file in filesystem.list("/usr/bin/plugins") do
	dofile("/usr/bin/plugins/" .. file)
end

print("Starting server on port 25565")
local serverSocket = server.open()
serverSocket:bind("MCServerOnOC")
serverSocket:listen()

print("Listening..")
thread.create(function()
	while true do
		local packet = packets.newKeepAlivePacket()
		for k, p in pairs(world.players) do
			if p.client.state == "play" and not p.socket.closed then
				net.writePacket(p.socket, packet)
			end
		end
		os.sleep(3)
	end
end)
while true do
	local socket = serverSocket:accept()
	socket:setvbuf("full")
	thread.create(function()
		local client = {
			state = "handshake"
		}
		while true do
			if socket:bufferEmpty() then
				socket:flush() -- flush all writes when all packets are processed
				serverSocket:pollState()
			end
			if socket:isClosed() then
				if client.player then
					client.player:disconnect()
				end
				break
			end
			local ok, err = pcall(function()
				local packet = net.readPacket(socket)
				--print("Packet ID: " .. string.format("0x%x", packet.id))
				if not packetHandlers[packet.id] then
					error("missing packet handler for id " .. string.format("0x%x", packet.id))
				end
				packetHandlers[packet.id](packet.dataStream, socket, client)
			end)
			if not ok then
				if client.player then
					local ok, err = pcall(client.player.kick, client.player, "Internal Server Error: " .. err)
					if not ok then
						socket:close()
						error("error while kicking player: " .. err)
					end
				end
				socket:close()
				error(err)
			end
		end
	end)
end
