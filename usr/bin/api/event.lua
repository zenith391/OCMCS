local evt = {}
local handlers = {}

local function executeHandlers(event)
	for k, v in pairs(handlers) do
		if v.type == event.name then
			v.callback(table.unpack(event.args))
		end
	end
end

function evt.on(name, callback)
	table.insert(handlers, {
		type = name,
		callback = callback
	})
end

function evt.send(name, ...)
	local event = {
		name = name,
		args = table.pack(name, ...)
	}
	executeHandlers(event)
end

return evt
