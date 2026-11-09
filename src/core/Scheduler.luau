--!strict
-- One heartbeat for the whole library. The connection exists only while work is
-- queued, so an idle window costs nothing.

local Runtime = require("./Runtime")
local Guard = require("./Guard")

local Scheduler = {}

local queue: { [any]: any } = {}
local queueOrder: { any } = {}
local idleQueue: { any } = {}
local timers: { any } = {}
local connection: any = nil
local elapsed = 0

local function disconnect()
	if connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
end

local function pending(): boolean
	return #queueOrder > 0 or #idleQueue > 0 or #timers > 0
end

local function step(dt: number)
	elapsed += dt or 0

	if #queueOrder > 0 then
		local batch = queueOrder
		queueOrder = {}
		for _, key in ipairs(batch) do
			local fn = queue[key]
			queue[key] = nil
			if fn ~= nil then
				Guard.call(fn)
			end
		end
	end

	if #idleQueue > 0 then
		local batch = idleQueue
		idleQueue = {}
		for _, fn in ipairs(batch) do
			Guard.call(fn)
		end
	end

	if #timers > 0 then
		local keep = {}
		for _, timer in ipairs(timers) do
			if not timer.cancelled then
				timer.remaining -= dt or 0
				if timer.remaining <= 0 then
					Guard.call(timer.fn)
				else
					table.insert(keep, timer)
				end
			end
		end
		timers = keep
	end

	if not pending() then
		disconnect()
	end
end

local function ensure()
	if connection ~= nil then
		return
	end
	local runService = Runtime.service("RunService")
	connection = runService.Heartbeat:Connect(step)
end

function Scheduler:queue(key: any, fn: () -> ())
	ensure()
	if queue[key] == nil then
		table.insert(queueOrder, key)
	end
	queue[key] = fn
end

function Scheduler:idle(fn: () -> ())
	ensure()
	table.insert(idleQueue, fn)
end

function Scheduler:after(seconds: number, fn: () -> ()): any
	ensure()
	local timer = {
		remaining = math.max(seconds, 0),
		fn = fn,
		cancelled = false,
	}
	table.insert(timers, timer)
	return {
		Cancel = function()
			timer.cancelled = true
		end,
	}
end

function Scheduler:cancel(key: any)
	if queue[key] ~= nil then
		queue[key] = nil
		for index = #queueOrder, 1, -1 do
			if queueOrder[index] == key then
				table.remove(queueOrder, index)
				break
			end
		end
	end
end

function Scheduler:now(): number
	return elapsed
end

function Scheduler:stats(): any
	return {
		queued = #queueOrder,
		idle = #idleQueue,
		timers = #timers,
		connected = connection ~= nil,
	}
end

function Scheduler:flush()
	step(0)
end

function Scheduler:stop()
	disconnect()
	table.clear(queue)
	table.clear(queueOrder)
	table.clear(idleQueue)
	table.clear(timers)
end

return Scheduler
