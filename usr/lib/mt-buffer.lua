-- Simple multi-threaded buffer made for OCMCS
local buffer = {}

function buffer.from(handle, err)
	if not handle then
		error(err)
	end
	local stream = {}
	stream.stream = handle
	stream.buf = "" -- read buffer
	stream.wbuf = "" -- unbounded write buffer
	stream.useWBuf = false -- use write buffer
	stream.size = 64*1024 -- 64 KiB
	stream.closed = false

	if handle.socket and handle.socket.finishConnect then
		handle.socket.finishConnect()
	end

	function stream:close()
		self.stream:close()
		self.closed = true
	end

	function stream:flush()
		self.stream:write(self.wbuf)
		self.wbuf = ""
	end
	
	function stream:write(s)
		if self.useWBuf then
			self.wbuf = self.wbuf .. s
		else
			self.stream:write(s)
		end
	end

	function stream:fillBuffer()
		if self.buf and #self.buf == 0 then
			if self.onBufferRefill then
				self:onBufferRefill()
			end
			self.buf = self.stream:read(self.size)
			if self.buf and #self.buf > 512 then
				print("Warning! High buffer queue: " .. #self.buf)
			end
			os.sleep(0)
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
					self:close()
					return nil
				end
			end
			local partLen = len-#str
			if len == math.huge then
				partLen = self.size-1
			end
			str = str .. self.buf:sub(1, partLen)
			self.buf = self.buf:sub(partLen+1) -- cut the read part
		end
		return str
	end

	function stream:bufferEmpty()
		return not self.buf or #self.buf == 0
	end

	function stream:read(f)
		if type(f) == "number" then
			return self:readBuffer(f)
		end
		print("invalid mode")
		return nil, "invalid mode"
	end

	function stream:setvbuf(mode, size)
		self:flush()
		if mode == "no" then
			self.useWBuf = false
		elseif mode == "full" then
			self.useWBuf = true
		end
	end

	return stream
end

return buffer
