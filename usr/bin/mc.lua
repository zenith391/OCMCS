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
local commands = api_require("commands")
local nextEid = 0

local function generateEId()
	nextEid = nextEid + 1
	return nextEid
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

--[[
    Implemented as described here:
    http://flafla2.github.io/2014/08/09/perlinnoise.html
]]--

local perlin = {}
perlin.p = {}

-- Hash lookup table as defined by Ken Perlin
-- This is a randomly arranged array of all numbers from 0-255 inclusive
local permutation = {151,160,137,91,90,15,
  131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
  190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
  88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
  77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
  102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
  135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
  5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
  223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
  129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
  251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
  49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
  138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
}

-- p is used to hash unit cube coordinates to [0, 255]
for i=0,255 do
    -- Convert to 0 based index table
    perlin.p[i] = permutation[i+1]
    -- Repeat the array to avoid buffer overflow in hash function
    perlin.p[i+256] = permutation[i+1]
end

-- Return range: [-1, 1]
function perlin:noise(x, y, z)
    y = y or 0
    z = z or 0

    -- Calculate the "unit cube" that the point asked will be located in
    local xi = math.floor(x)&255
    local yi = math.floor(y)&255
    local zi = math.floor(z)&255

    -- Next we calculate the location (from 0 to 1) in that cube
    x = x - math.floor(x)
    y = y - math.floor(y)
    z = z - math.floor(z)

    -- We also fade the location to smooth the result
    local u = self.fade(x)
    local v = self.fade(y)
    local w = self.fade(z)

    -- Hash all 8 unit cube coordinates surrounding input coordinate
    local p = self.p
    local A, AA, AB, AAA, ABA, AAB, ABB, B, BA, BB, BAA, BBA, BAB, BBB
    A   = p[xi  ] + yi
    AA  = p[A   ] + zi
    AB  = p[A+1 ] + zi
    AAA = p[ AA ]
    ABA = p[ AB ]
    AAB = p[ AA+1 ]
    ABB = p[ AB+1 ]

    B   = p[xi+1] + yi
    BA  = p[B   ] + zi
    BB  = p[B+1 ] + zi
    BAA = p[ BA ]
    BBA = p[ BB ]
    BAB = p[ BA+1 ]
    BBB = p[ BB+1 ]

    -- Take the weighted average between all 8 unit cube coordinates
    return self.lerp(w,
        self.lerp(v,
            self.lerp(u,
                self:grad(AAA,x,y,z),
                self:grad(BAA,x-1,y,z)
            ),
            self.lerp(u,
                self:grad(ABA,x,y-1,z),
                self:grad(BBA,x-1,y-1,z)
            )
        ),
        self.lerp(v,
            self.lerp(u,
                self:grad(AAB,x,y,z-1), self:grad(BAB,x-1,y,z-1)
            ),
            self.lerp(u,
                self:grad(ABB,x,y-1,z-1), self:grad(BBB,x-1,y-1,z-1)
            )
        )
    )
end

-- Gradient function finds dot product between pseudorandom gradient vector
-- and the vector from input coordinate to a unit cube vertex
perlin.dot_product = {
    [0x0]=function(x,y,z) return  x + y end,
    [0x1]=function(x,y,z) return -x + y end,
    [0x2]=function(x,y,z) return  x - y end,
    [0x3]=function(x,y,z) return -x - y end,
    [0x4]=function(x,y,z) return  x + z end,
    [0x5]=function(x,y,z) return -x + z end,
    [0x6]=function(x,y,z) return  x - z end,
    [0x7]=function(x,y,z) return -x - z end,
    [0x8]=function(x,y,z) return  y + z end,
    [0x9]=function(x,y,z) return -y + z end,
    [0xA]=function(x,y,z) return  y - z end,
    [0xB]=function(x,y,z) return -y - z end,
    [0xC]=function(x,y,z) return  y + x end,
    [0xD]=function(x,y,z) return -y + z end,
    [0xE]=function(x,y,z) return  y - x end,
    [0xF]=function(x,y,z) return -y - z end
}
function perlin:grad(hash, x, y, z)
    return self.dot_product[hash&0xF](x,y,z)
end

-- Fade function is used to smooth final output
function perlin.fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

function perlin.lerp(t, a, b)
    return a + t * (b - a)
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

local players = {}

local world = {
	levelType = "flat",
	renderDistance = configuration.world.viewDistance,
	spawnPosition = {0, 5, 0},
	generator = {
		height = function(x, z)
			local noise = (perlin:noise(x/16, z/16) + 1) / 2
			return math.floor(noise*16)
		end,
		block = function(x, y, z)
			if configuration.world.type == "flat" then
				if y == 3 then
					return 9
				elseif y == 2 or y == 1 then
					return 10 -- dirt
				elseif y == 0 then
					return 33 -- bedrock
				else
					return 0 -- air
				end
			else
				local noise = (perlin:noise(x/16, z/16) + 1) / 2
				local height = math.floor(noise*16)
				if y == height then
					return 9 -- grass block
				elseif y == 0 then
					return 33 -- bedrock
				elseif y < height then
					return 10 -- dirt
				else
					return 0 -- air
				end
			end
		end
	},
	changedBlocks = {},
	players = players,
	entities = {}
}

world.spawnPosition = {0, world.generator.height(0, 0)+2, 0}

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
	pluginEvent.send("entity_move", entity, x, y, z)
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
	pluginEvent.send("entity_rotate", entity, yaw, pitch)

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
			}, {__index = api_require("player")}))

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
		net.writeVarInt(ss, count(players))
		print(count(players) .. " players")

		for k, player in pairs(players) do
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
	thread.create(function()
		local client = {
			state = "handshake"
		}
		while true do
			if socket:bufferEmpty() then
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
					pcall(client.player.kick, ("Internal Server Error: " .. err))
				end
				socket:close()
				error(err)
			end
		end
	end)
end
