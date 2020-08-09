local server = {}
local internet = require("internet")
local event = require("event")

local bridgeIp = "localhost"
local commPort = 3330

function server.open()
	local serverSocket = {}
	local state = "idle"
	local closedTokens = {}
	
	function serverSocket:listen()
		state = "listening"
		self.sock:write("l")
		local response = self.sock:read(1)
		if response ~= "l" then
			error("invalid listen response, got " .. tostring(response))
		end
	end

	function serverSocket:accept()
		local socketToken = self.sock:read(6)
		if not socketToken then
			error("server closed")
		end
		socketToken = socketToken:sub(2)

		local sock, err = internet.open(bridgeIp, commPort)
		if not sock then
			error(err)
		end
		sock.stream.socket.finishConnect()
		sock:setvbuf("no")
		sock:write(socketToken .. "\0")
		sock.token = socketToken
		sock.closed = false
		sock.isClosed = function(self)
			for _, tok in pairs(closedTokens) do
				if tok == self.token then
					if not sock.closed then
						sock:close()
						sock.closed = true
					end
					return true
				end
			end
			return false
		end
		local resp = sock:read(1)
		if resp == "n" then
			error("invalid token")
		end
		state = "idle"
		return sock
	end

	function serverSocket:bind(token)
		state = "binding"
		self.sock:write(token .. "\0")
		local resp = self.sock:read(1)
		if resp == "n" then
			error("invalid token")
		end
		state = "idle"
	end

	function serverSocket:pollState()
		local data = self.sock.stream:read(6) -- close packets are always 6 bytes long
		if data then
			if data:sub(1,1) == "d" then -- close socket
				table.insert(closedTokens, data:sub(2))
			end
		end
	end

	function serverSocket:close()
		self.sock:close()
	end

	local sock, err = internet.open(bridgeIp, commPort)
	if not sock then
		error(err)
	end
	sock.stream.socket.finishConnect()
	sock:setvbuf("no")
	serverSocket.sock = sock

	event.listen("internet_ready", function(_, _, socketId)
		if state == "idle" and socketId == sock.stream.socket.id() then
			serverSocket:pollState()
		end
	end)

	return serverSocket
end

return server
