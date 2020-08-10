-- Simple multi-threaded buffer made for OCMCS
local buffer = {}

function buffer.from(handle, err)
	if not handle then
		error(err)
	end
	local stream = {}
	stream.stream = handle
	stream.buf = ""
	stream.size = 1024
	stream.closed = false

	if handle.socket and handle.socket.finishConnect then
		handle.socket.finishConnect()
	end

	function stream:close()
		self.stream:close()
		self.closed = true
	end
	
	function stream:write(s)
		self.stream:write(s)
	end

	function stream:fillBuffer()
		if self.buf and #self.buf == 0 then
			self.buf = self.stream:read(self.size)
		end
	end

	function stream:readBuffer(len)
		local str = ""
		while #str < len do
			self:fillBuffer()
			if self.buf == nil then
				self.buf = ""
				if str:len() > 0 then
					return str
				else
					if not self.closed then
						print("CLOSE!")
						self:close()
					end
					return nil
				end
			end
			local partLen = len-#str
			if len == math.huge then
				partLen = self.size-1
			end
			local part = self.buf:sub(1, partLen)
			self.buf = self.buf:sub(partLen+1) -- cut the read part
			str = str .. part
			if self.buf == "" then
				os.sleep(0)
			end
		end
		return str
	end

	function stream:read(f)
		if type(f) == "number" then
			return self:readBuffer(f)
		end
		print("invalid mode")
		return nil, "invalid mode"
	end

	function stream:setvbuf(mode, size) end

	return stream
end

return buffer
