--!strict
-- Dependency free event. Listeners are isolated: one failure never stops the
-- rest of the chain, and iteration happens over a snapshot so a listener may
-- disconnect itself safely.

local Guard = require("./Guard")

local Signal = {}
Signal.__index = Signal

function Signal.new(name: string?)
	return setmetatable({
		_handlers = {},
		_name = name or "signal",
		_destroyed = false,
	}, Signal)
end

function Signal:Connect(fn: (...any) -> ...any): any
	assert(type(fn) == "function", "Signal:Connect expects a function")

	if self._destroyed then
		return {
			Connected = false,
			Disconnect = function() end,
		}
	end

	local signal = self
	local handler = { fn = fn, alive = true }
	table.insert(self._handlers, handler)

	local connection = { Connected = true }

	function connection:Disconnect()
		if not handler.alive then
			return
		end
		handler.alive = false
		connection.Connected = false
		for index = #signal._handlers, 1, -1 do
			if signal._handlers[index] == handler then
				table.remove(signal._handlers, index)
				break
			end
		end
	end

	return connection
end

function Signal:Once(fn: (...any) -> ...any): any
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		return fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	if self._destroyed then
		return
	end
	local snapshot = table.clone(self._handlers)
	for _, handler in ipairs(snapshot) do
		if handler.alive then
			Guard.call(handler.fn, ...)
		end
	end
end

function Signal:GetCount(): number
	return #self._handlers
end

function Signal:DisconnectAll()
	for _, handler in ipairs(self._handlers) do
		handler.alive = false
	end
	table.clear(self._handlers)
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:DisconnectAll()
end

return Signal
