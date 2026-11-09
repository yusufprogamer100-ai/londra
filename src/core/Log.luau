--!strict
-- Levelled logger with a fixed size ring buffer. A logger that grows without
-- bound is a memory leak with extra steps.

local Runtime = require("./Runtime")

local Log = {}

local LEVELS = {
	debug = 10,
	info = 20,
	warn = 30,
	error = 40,
	off = 100,
}

local BUFFER_LIMIT = 100

Log.level = "warn"
Log.buffer = {}
Log.listeners = {}

local function emit(level: string, message: string)
	local entry = {
		level = level,
		message = message,
		clock = os.clock(),
	}
	table.insert(Log.buffer, entry)
	while #Log.buffer > BUFFER_LIMIT do
		table.remove(Log.buffer, 1)
	end
	for _, listener in ipairs(Log.listeners) do
		local ok = pcall(listener, entry)
		if not ok then
			continue
		end
	end
end

function Log.write(level: string, message: string)
	if (LEVELS[level] or 0) < (LEVELS[Log.level] or 0) then
		return
	end
	emit(level, message)
	if level == "error" or level == "warn" then
		local ok, warnFn = pcall(function()
			return Runtime.warn
		end)
		if ok and type(warnFn) == "function" then
			warnFn("[Londra/" .. level .. "] " .. message)
			return
		end
	end
	print("[Londra/" .. level .. "] " .. message)
end

local function format(message: any, ...): string
	if select("#", ...) == 0 then
		return tostring(message)
	end
	local ok, result = pcall(string.format, tostring(message), ...)
	return ok and result or tostring(message)
end

function Log.debug(message: any, ...)
	Log.write("debug", format(message, ...))
end

function Log.info(message: any, ...)
	Log.write("info", format(message, ...))
end

function Log.warn(message: any, ...)
	Log.write("warn", format(message, ...))
end

function Log.error(message: any, ...)
	Log.write("error", format(message, ...))
end

function Log.onEntry(listener: (any) -> ()): any
	table.insert(Log.listeners, listener)
	return {
		Disconnect = function()
			for index = #Log.listeners, 1, -1 do
				if Log.listeners[index] == listener then
					table.remove(Log.listeners, index)
					break
				end
			end
		end,
	}
end

function Log.dump(): { any }
	return table.clone(Log.buffer)
end

function Log.clear()
	table.clear(Log.buffer)
end

return Log
