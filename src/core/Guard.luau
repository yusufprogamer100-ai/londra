--!strict
-- Error boundary. A broken user callback must never take the interface down.

local Log = require("./Log")

local Guard = {}

function Guard.call(fn: (...any) -> ...any, ...): (boolean, ...any)
	if type(fn) ~= "function" then
		Log.warn("Guard.call: expected function, got %s", type(fn))
		return false, nil
	end
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		local message = tostring(results[2])
		local trace = ""
		local ok, traceback = pcall(function()
			return debug.traceback
		end)
		if ok and type(traceback) == "function" then
			local okTrace, result = pcall(traceback, message, 2)
			if okTrace then
				trace = tostring(result)
			end
		end
		Log.error("%s", trace ~= "" and trace or message)
		return false, results[2]
	end
	return true, table.unpack(results, 2, results.n)
end

function Guard.wrap(fn: (...any) -> ...any): (...any) -> ...any
	return function(...)
		return Guard.call(fn, ...)
	end
end

function Guard.try(fn: (...any) -> ...any, fallback: any, ...): any
	local ok, result = Guard.call(fn, ...)
	if ok then
		return result
	end
	return fallback
end

return Guard
