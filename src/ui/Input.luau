--!strict
-- One global keyboard map for the whole library. Components register a key,
-- they never open their own UserInputService connection.

local Runtime = require("../core/Runtime")
local Guard = require("../core/Guard")

local Input = {}

local handlers: { any } = {}
local suspended = 0
local started = false
local captureHandler: any = nil

local function dispatch(input: any, processed: boolean)
	if suspended > 0 then
		return
	end
	if captureHandler ~= nil and input.UserInputType == Runtime.Enum.UserInputType.Keyboard then
		local handler = captureHandler
		captureHandler = nil
		Guard.call(handler, input, processed)
		return
	end
	for _, handler in ipairs(table.clone(handlers)) do
		if handler.alive and handler.key == input.KeyCode then
			if handler.force or not processed then
				Guard.call(handler.fn, input, processed)
			end
		end
	end
end

local function ensure()
	if started then
		return
	end
	started = true
	local userInput = Runtime.service("UserInputService")
	userInput.InputBegan:Connect(function(input, processed)
		dispatch(input, processed)
	end)
end

function Input.bind(key: any, fn: (any, boolean) -> (), options: any?): any
	ensure()
	local config = options or {}
	local handler = {
		key = key,
		fn = fn,
		force = config.force == true,
		alive = true,
	}
	table.insert(handlers, handler)

	local connection = { Connected = true }
	function connection:Disconnect()
		if not handler.alive then
			return
		end
		handler.alive = false
		connection.Connected = false
		for index = #handlers, 1, -1 do
			if handlers[index] == handler then
				table.remove(handlers, index)
				break
			end
		end
	end
	return connection
end

function Input.suspend()
	suspended += 1
end

function Input.capture(fn: (any, boolean) -> ()): any
	ensure()
	captureHandler = fn
	local handle = { Connected = true }
	function handle:Cancel()
		if captureHandler == fn then
			captureHandler = nil
		end
		handle.Connected = false
	end
	return handle
end

function Input.resume()
	suspended = math.max(0, suspended - 1)
end

function Input.isSuspended(): boolean
	return suspended > 0
end

function Input.reset()
	table.clear(handlers)
	suspended = 0
	captureHandler = nil
end

return Input
