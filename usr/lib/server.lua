local server = {}
local internet = require("internet")
local event = require("event")
package.loaded["mt-buffer"] = nil
local mtBuffer = require("mt-buffer")

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
			if response == nil then
				error("bridge server not opened")
			end
			error("invalid listen response, got " .. tostring(response))
		end
	end

	function serverSocket:accept()
		local socketToken = self.sock:read(6)
		if not socketToken then
			error("server closed")
		end
		socketToken = socketToken:sub(2)

		local sock, err = mtBuffer.from(internet.socket(bridgeIp, commPort))
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
					if not self.closed then
						self:close()
						self.closed = true
					end
					return true
				end
			end
			return self.closed
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

	local sock, err = mtBuffer.from(internet.socket(bridgeIp, commPort))
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
