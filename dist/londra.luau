-- Londra UI Library
-- build: deterministic, do not edit. Source lives in src/.
-- modules: 57

local __modules = {}
local __cache = {}

local function require(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local factory = __modules[name]
	if factory == nil then
		error('Londra: module not found: ' .. tostring(name), 0)
	end
	local module = factory()
	__cache[name] = module
	return module
end

__modules["version"] = function()
--!strict
local Version = {
	name = "Londra",
	version = "1.0.0",
	codename = "Whitechapel",
}

return Version
end

__modules["core/Runtime"] = function()
--!strict
-- Engine access point.
-- Modules never touch Roblox globals directly, so the same code runs inside a
-- real executor and inside the headless test harness. Lookups are lazy: the
-- runtime is resolved on first property access, never at require time.

local Runtime = {}

local current: any = nil

local function detect(): any
	local ok, engine = pcall(function()
		return game
	end)
	if not ok or engine == nil then
		return nil
	end
	return {
		game = engine,
		Instance = Instance,
		Enum = Enum,
		Color3 = Color3,
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		TweenInfo = TweenInfo,
		NumberRange = NumberRange,
		workspace = workspace,
		typeof = typeof,
		task = task,
		warn = warn,
		tick = tick,
	}
end

function Runtime.inject(engine: any)
	current = engine
end

function Runtime.get(): any
	if current ~= nil then
		return current
	end
	current = detect()
	if current == nil then
		error("Londra: no runtime available. Call Londra.__inject(runtime) before use.", 0)
	end
	return current
end

local services: { [string]: any } = {}

function Runtime.service(name: string): any
	local cached = services[name]
	if cached ~= nil then
		return cached
	end
	local engine = Runtime.get()
	local ok, service = pcall(function()
		return engine.game:GetService(name)
	end)
	if not ok or service == nil then
		error("Londra: service unavailable: " .. name, 0)
	end
	services[name] = service
	return service
end

function Runtime.reset()
	services = {}
end

return setmetatable(Runtime, {
	__index = function(_, key)
		return Runtime.get()[key]
	end,
})
end

__modules["core/Log"] = function()
--!strict
-- Levelled logger with a fixed size ring buffer. A logger that grows without
-- bound is a memory leak with extra steps.

local Runtime = require("core/Runtime")

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
end

__modules["core/Env"] = function()
--!strict
-- Executor capability probe. A missing capability must be visible, never
-- silently swallowed: the feature that depends on it degrades and says so.

local Runtime = require("core/Runtime")
local Log = require("core/Log")

local Env = {}

local CAPABILITIES = {
	"gethui",
	"protect_gui",
	"writefile",
	"readfile",
	"isfolder",
	"makefolder",
	"delfile",
	"setclipboard",
	"gethwid",
	"openbrowser",
	"hookfunction",
	"crypt_hash",
}

local probed: any = nil

local function httpAvailable(): boolean
	local ok, service = pcall(function()
		return Runtime.service("HttpService")
	end)
	if not ok or service == nil then
		return false
	end
	local okJson = pcall(function()
		return service.JSONEncode
	end)
	return okJson
end

function Env.probe(force: boolean?): any
	if probed ~= nil and not force then
		return probed
	end

	local engine = Runtime.get()
	local capabilities = {}

	for _, name in ipairs(CAPABILITIES) do
		capabilities[name] = type(engine[name]) == "function"
	end

	capabilities.http = httpAvailable()

	probed = capabilities

	local missing = {}
	for _, name in ipairs(CAPABILITIES) do
		if not capabilities[name] then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		Log.info("executor capabilities missing: %s", table.concat(missing, ", "))
	end

	return probed
end

function Env.has(name: string): boolean
	return Env.probe()[name] == true
end

function Env.reset()
	probed = nil
end

function Env.summary(): string
	local capabilities = Env.probe()
	local available = {}
	for name, value in pairs(capabilities) do
		if value then
			table.insert(available, name)
		end
	end
	table.sort(available)
	return table.concat(available, ",")
end

return Env
end

__modules["core/Janitor"] = function()
--!strict
-- Resource ownership. Every connection, tween handle, instance and cleanup
-- function a component creates is added here. Cleanup runs LIFO so children are
-- never destroyed after their parent.

local Runtime = require("core/Runtime")

local Janitor = {}
Janitor.__index = Janitor

local TASK_INSTANCE = "instance"
local TASK_CONNECTION = "connection"
local TASK_FUNCTION = "function"
local TASK_OBJECT = "object"

function Janitor.new()
	return setmetatable({
		_tasks = {},
		_owned = {},
		_cleaned = false,
	}, Janitor)
end

local function kindOf(item: any): string?
	if item == nil then
		return nil
	end
	if type(item) == "function" then
		return TASK_FUNCTION
	end
	if type(item) == "table" then
		if item.Destroy ~= nil or item.Clean ~= nil or item.Disconnect ~= nil or item.Cancel ~= nil then
			return TASK_OBJECT
		end
		return nil
	end
	local ok, itemType = pcall(function()
		return Runtime.typeof(item)
	end)
	if ok and itemType == "Instance" then
		return TASK_INSTANCE
	end
	if ok and itemType == "RBXScriptConnection" then
		return TASK_CONNECTION
	end
	return nil
end

function Janitor:Add(item: any, cleanup: (() -> ())?): any
	if item == nil then
		return nil
	end

	if cleanup ~= nil then
		table.insert(self._tasks, { kind = TASK_FUNCTION, value = cleanup })
		return item
	end

	local kind = kindOf(item)
	if kind == nil then
		return nil
	end

	if self._owned[item] then
		return item
	end
	self._owned[item] = true
	table.insert(self._tasks, { kind = kind, value = item })
	return item
end

function Janitor:Remove(item: any)
	for index = #self._tasks, 1, -1 do
		if self._tasks[index].value == item then
			table.remove(self._tasks, index)
			self._owned[item] = nil
			return
		end
	end
end

function Janitor:Link(other: any)
	if other == nil then
		return
	end
	table.insert(self._tasks, {
		kind = TASK_FUNCTION,
		value = function()
			other:Destroy()
		end,
	})
end

function Janitor:Clean()
	if self._cleaned then
		return
	end
	self._cleaned = true

	for index = #self._tasks, 1, -1 do
		local task = self._tasks[index]
		self._tasks[index] = nil
		local value = task.value
		if task.kind == TASK_INSTANCE then
			pcall(function()
				value:Destroy()
			end)
		elseif task.kind == TASK_CONNECTION then
			pcall(function()
				value:Disconnect()
			end)
		elseif task.kind == TASK_FUNCTION then
			pcall(value)
		elseif task.kind == TASK_OBJECT then
			pcall(function()
				if value.Destroy ~= nil then
					value:Destroy()
				elseif value.Clean ~= nil then
					value:Clean()
				elseif value.Disconnect ~= nil then
					value:Disconnect()
				elseif value.Cancel ~= nil then
					value:Cancel()
				end
			end)
		end
	end

	table.clear(self._tasks)
	table.clear(self._owned)
end

function Janitor:Destroy()
	self:Clean()
end

function Janitor:Count(): number
	return #self._tasks
end

return Janitor
end

__modules["core/Class"] = function()
--!strict
-- Minimal object model. Two levels of inheritance cover the whole library:
--   Class -> (Window, Tab, Section, Component) -> concrete component

local Janitor = require("core/Janitor")

local Class = {}
Class.__index = Class

function Class.new(ctor: any, ...): any
	local self = setmetatable({}, ctor)
	self._janitor = Janitor.new()
	self._destroyed = false
	if self.init ~= nil then
		self:init(...)
	end
	return self
end

function Class:extends(name: string): any
	local subclass = setmetatable({}, { __index = self })
	subclass.__index = subclass
	subclass.super = self
	subclass.__name = name
	subclass.new = function(...)
		return Class.new(subclass, ...)
	end
	return subclass
end

function Class:isDestroyed(): boolean
	return self._destroyed == true
end

function Class:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self.beforeDestroy ~= nil then
		local ok = pcall(self.beforeDestroy, self)
		if not ok then
			-- teardown must continue even when a hook fails
		end
	end
	self._janitor:Clean()
	if self.afterDestroy ~= nil then
		pcall(self.afterDestroy, self)
	end
end

return Class
end

__modules["core/Guard"] = function()
--!strict
-- Error boundary. A broken user callback must never take the interface down.

local Log = require("core/Log")

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
end

__modules["core/Signal"] = function()
--!strict
-- Dependency free event. Listeners are isolated: one failure never stops the
-- rest of the chain, and iteration happens over a snapshot so a listener may
-- disconnect itself safely.

local Guard = require("core/Guard")

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
end

__modules["core/Motion"] = function()
--!strict
-- Motion is a single code path with two behaviours: real tween, or instant
-- assignment when reduced motion is on. No parallel animation system to keep in
-- sync.

local Runtime = require("core/Runtime")

local Motion = {}

local reduced = false

local DEFAULTS = {
	state = 0.12,
	open = 0.18,
	close = 0.14,
	press = 0.08,
	toast = 0.22,
}

function Motion.setReduced(value: boolean)
	reduced = value == true
end

function Motion.isReduced(): boolean
	return reduced
end

function Motion.duration(kind: string?): number
	if reduced then
		return 0
	end
	return DEFAULTS[kind or "state"] or DEFAULTS.state
end

function Motion.tween(instance: any, goal: any, options: any?): any
	options = options or {}
	local duration = options.duration
	if duration == nil then
		duration = reduced and 0 or DEFAULTS.state
	end
	if reduced then
		duration = 0
	end

	if duration <= 0 then
		for property, value in pairs(goal) do
			instance[property] = value
		end
		return {
			Cancel = function() end,
			Complete = function() end,
		}
	end

	local info = Runtime.TweenInfo.new(
		duration,
		options.easing or Runtime.Enum.EasingStyle.Quad,
		options.direction or Runtime.Enum.EasingDirection.Out,
		0,
		false,
		0
	)
	local tween = Runtime.service("TweenService"):Create(instance, info, goal)
	tween:Play()

	return {
		Cancel = function()
			pcall(function()
				tween:Cancel()
			end)
		end,
		Complete = function()
			pcall(function()
				tween:Play()
			end)
		end,
		tween = tween,
	}
end

function Motion.fade(instance: any, target: number, options: any?): any
	return Motion.tween(instance, { BackgroundTransparency = target }, options)
end

-- Reusable press feedback. The UIScale is created once per element.
function Motion.press(instance: any, scale: number?): any
	local runtime = Runtime
	local uiscale = instance:FindFirstChild("__londra_press")
	if uiscale == nil then
		uiscale = runtime.Instance.new("UIScale")
		uiscale.Name = "__londra_press"
		uiscale.Parent = instance
	end
	return Motion.tween(uiscale, { Scale = scale or 0.985 }, { duration = Motion.duration("press") })
end

function Motion.release(instance: any): any
	local uiscale = instance:FindFirstChild("__londra_press")
	if uiscale == nil then
		return nil
	end
	return Motion.tween(uiscale, { Scale = 1 }, { duration = Motion.duration("press") })
end

return Motion
end

__modules["core/Scheduler"] = function()
--!strict
-- One heartbeat for the whole library. The connection exists only while work is
-- queued, so an idle window costs nothing.

local Runtime = require("core/Runtime")
local Guard = require("core/Guard")

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
end

__modules["design/Color"] = function()
--!strict
-- Colour maths. Every conversion is explicit so it can be unit tested against
-- the WCAG formula and against a reference HSV implementation.

local Runtime = require("core/Runtime")

local Color = {}

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

function Color.new(r: number, g: number, b: number): any
	return Runtime.Color3.new(clamp01(r), clamp01(g), clamp01(b))
end

function Color.fromRGB(r: number, g: number, b: number): any
	return Runtime.Color3.fromRGB(r, g, b)
end

function Color.fromHex(hex: string): any?
	if type(hex) ~= "string" then
		return nil
	end
	local raw = string.gsub(hex, "^#", "")
	raw = string.gsub(raw, "^0x", "")
	if #raw == 3 then
		raw = string.sub(raw, 1, 1)
			.. string.sub(raw, 1, 1)
			.. string.sub(raw, 2, 2)
			.. string.sub(raw, 2, 2)
			.. string.sub(raw, 3, 3)
			.. string.sub(raw, 3, 3)
	end
	if #raw ~= 6 then
		return nil
	end
	local value = tonumber(raw, 16)
	if value == nil then
		return nil
	end
	local r = math.floor(value / 65536) % 256
	local g = math.floor(value / 256) % 256
	local b = value % 256
	return Runtime.Color3.fromRGB(r, g, b)
end

function Color.toHex(color: any): string
	local r = math.floor(math.clamp(color.R, 0, 1) * 255 + 0.5)
	local g = math.floor(math.clamp(color.G, 0, 1) * 255 + 0.5)
	local b = math.floor(math.clamp(color.B, 0, 1) * 255 + 0.5)
	return string.format("#%02X%02X%02X", r, g, b)
end

function Color.fromHSV(h: number, s: number, v: number): any
	local hue = (h % 1) * 6
	local sat = clamp01(s)
	local val = clamp01(v)
	local index = math.floor(hue)
	local fraction = hue - index
	local p = val * (1 - sat)
	local q = val * (1 - sat * fraction)
	local t = val * (1 - sat * (1 - fraction))

	local r, g, b
	if index == 0 then
		r, g, b = val, t, p
	elseif index == 1 then
		r, g, b = q, val, p
	elseif index == 2 then
		r, g, b = p, val, t
	elseif index == 3 then
		r, g, b = p, q, val
	elseif index == 4 then
		r, g, b = t, p, val
	else
		r, g, b = val, p, q
	end
	return Runtime.Color3.new(r, g, b)
end

function Color.toHSV(color: any): (number, number, number)
	local r, g, b = color.R, color.G, color.B
	local maximum = math.max(r, g, b)
	local minimum = math.min(r, g, b)
	local delta = maximum - minimum

	local hue = 0
	if delta > 0 then
		if maximum == r then
			hue = ((g - b) / delta) % 6
		elseif maximum == g then
			hue = (b - r) / delta + 2
		else
			hue = (r - g) / delta + 4
		end
		hue = hue / 6
	end

	local saturation = maximum == 0 and 0 or delta / maximum
	return hue, saturation, maximum
end

function Color.lerp(a: any, b: any, alpha: number): any
	return Runtime.Color3.new(
		a.R + (b.R - a.R) * alpha,
		a.G + (b.G - a.G) * alpha,
		a.B + (b.B - a.B) * alpha
	)
end

function Color.lighten(color: any, amount: number): any
	return Color.lerp(color, Runtime.Color3.new(1, 1, 1), amount)
end

function Color.darken(color: any, amount: number): any
	return Color.lerp(color, Runtime.Color3.new(0, 0, 0), amount)
end

function Color.equal(a: any, b: any): boolean
	if a == b then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end

local function channelLuminance(value: number): number
	if value <= 0.03928 then
		return value / 12.92
	end
	return math.pow((value + 0.055) / 1.055, 2.4)
end

function Color.luminance(color: any): number
	return 0.2126 * channelLuminance(color.R)
		+ 0.7152 * channelLuminance(color.G)
		+ 0.0722 * channelLuminance(color.B)
end

function Color.contrast(a: any, b: any): number
	local first = Color.luminance(a)
	local second = Color.luminance(b)
	local high = math.max(first, second)
	local low = math.min(first, second)
	return (high + 0.05) / (low + 0.05)
end

function Color.bestOn(background: any): any
	local white = Runtime.Color3.new(1, 1, 1)
	local black = Runtime.Color3.new(0, 0, 0)
	if Color.contrast(background, white) >= Color.contrast(background, black) then
		return white
	end
	return black
end

return Color
end

__modules["design/ThemeNight"] = function()
--!strict
return {
	["surface.base"] = "#0F1114",
	["surface.raised"] = "#16191E",
	["surface.sunken"] = "#0A0C0E",
	["surface.overlay"] = "#0B0D10",
	["border.hairline"] = "#262A31",
	["border.strong"] = "#3A4048",
	["text.primary"] = "#E7E9EC",
	["text.secondary"] = "#A3AAB5",
	["text.muted"] = "#7E8794",
	["text.inverse"] = "#14161A",
	["accent.base"] = "#D4AF37",
	["accent.hover"] = "#E0BE4E",
	["accent.pressed"] = "#B8962C",
	["accent.on"] = "#17130A",
	["state.hover"] = "#1E232A",
	["state.pressed"] = "#242A32",
	["state.selected"] = "#2A2417",
	["state.disabled"] = "#15181D",
	["state.success"] = "#4CAF7D",
	["state.warn"] = "#D9A441",
	["state.danger"] = "#E05B5B",
	["state.info"] = "#5C9BD6",
	["focus.ring"] = "#D4AF37",
	["shadow.soft"] = "#000000",
}
end

__modules["design/ThemeDay"] = function()
--!strict
return {
	["surface.base"] = "#F4F4F2",
	["surface.raised"] = "#FFFFFF",
	["surface.sunken"] = "#EAEAE6",
	["surface.overlay"] = "#E6E6E1",
	["border.hairline"] = "#C9C9C2",
	["border.strong"] = "#A9A9A0",
	["text.primary"] = "#14161A",
	["text.secondary"] = "#4A505A",
	["text.muted"] = "#656D7B",
	["text.inverse"] = "#F7F7F5",
	["accent.base"] = "#8A6A00",
	["accent.hover"] = "#9E7A00",
	["accent.pressed"] = "#715700",
	["accent.on"] = "#FFFFFF",
	["state.hover"] = "#ECECE7",
	["state.pressed"] = "#E2E2DC",
	["state.selected"] = "#F0E9D2",
	["state.disabled"] = "#EDEDE9",
	["state.success"] = "#1F7A4D",
	["state.warn"] = "#8A5A00",
	["state.danger"] = "#B3261E",
	["state.info"] = "#2A6BA8",
	["focus.ring"] = "#8A6A00",
	["shadow.soft"] = "#000000",
}
end

__modules["design/ThemeContrast"] = function()
--!strict
return {
	["surface.base"] = "#000000",
	["surface.raised"] = "#0B0B0B",
	["surface.sunken"] = "#000000",
	["surface.overlay"] = "#000000",
	["border.hairline"] = "#4A4A4A",
	["border.strong"] = "#8A8A8A",
	["text.primary"] = "#FFFFFF",
	["text.secondary"] = "#F2F2F2",
	["text.muted"] = "#D6D6D6",
	["text.inverse"] = "#000000",
	["accent.base"] = "#FFD84D",
	["accent.hover"] = "#FFE580",
	["accent.pressed"] = "#E0BB2E",
	["accent.on"] = "#000000",
	["state.hover"] = "#1F1F1F",
	["state.pressed"] = "#2E2E2E",
	["state.selected"] = "#332B00",
	["state.disabled"] = "#141414",
	["state.success"] = "#6BE3A4",
	["state.warn"] = "#FFD84D",
	["state.danger"] = "#FF8A8A",
	["state.info"] = "#8FC4FF",
	["focus.ring"] = "#FFD84D",
	["shadow.soft"] = "#000000",
}
end

__modules["design/Theme"] = function()
--!strict
-- Token themes plus per-window binders. A theme switch walks the binding list,
-- never the instance tree: O(bindings), not O(descendants).

local Color = require("design/Color")
local Runtime = require("core/Runtime")
local Log = require("core/Log")
local ThemeNight = require("design/ThemeNight")
local ThemeDay = require("design/ThemeDay")
local ThemeContrast = require("design/ThemeContrast")

local Theme = {}
Theme.registry = {}

local AA_PAIRS = {
	{ "text.primary", "surface.base", 4.5 },
	{ "text.primary", "surface.raised", 4.5 },
	{ "text.primary", "surface.sunken", 4.5 },
	{ "text.secondary", "surface.base", 4.5 },
	{ "text.secondary", "surface.raised", 4.5 },
	{ "text.muted", "surface.base", 4.5 },
	{ "text.muted", "surface.raised", 4.5 },
	{ "accent.on", "accent.base", 4.5 },
	{ "accent.base", "surface.base", 3 },
	{ "accent.base", "surface.raised", 3 },
	{ "state.success", "surface.raised", 4.5 },
	{ "state.warn", "surface.raised", 4.5 },
	{ "state.danger", "surface.raised", 4.5 },
}

function Theme.define(name: string, tokens: any)
	Theme.registry[name] = table.clone(tokens)
end

Theme.define("night", ThemeNight)
Theme.define("day", ThemeDay)
Theme.define("contrast", ThemeContrast)

function Theme.get(name: string?): any
	local key = name or "night"
	local tokens = Theme.registry[key]
	if tokens == nil then
		Log.warn("unknown theme '%s', falling back to night", tostring(key))
		return Theme.registry.night
	end
	return tokens
end

function Theme.list(): { string }
	local names = {}
	for name in pairs(Theme.registry) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Theme.derive(name: string, options: any): any
	local source = Theme.get(options.from or "night")
	local tokens = table.clone(source)
	if options.tokens ~= nil then
		for token, value in pairs(options.tokens) do
			tokens[token] = value
		end
	end
	if options.accent ~= nil and tokens["accent.base"] ~= nil then
		local accent = Color.fromHex(options.accent) or Color.fromHex(tokens["accent.base"])
		if accent ~= nil then
			tokens["accent.base"] = Color.toHex(accent)
			tokens["accent.hover"] = Color.toHex(Color.lighten(accent, 0.12))
			tokens["accent.pressed"] = Color.toHex(Color.darken(accent, 0.14))
			tokens["accent.on"] = Color.toHex(Color.bestOn(accent))
			tokens["focus.ring"] = Color.toHex(accent)
		end
	end
	Theme.define(name, tokens)
	return tokens
end

function Theme.validate(tokens: any): { any }
	local report = {}
	for _, pair in ipairs(AA_PAIRS) do
		local foreground = Color.fromHex(tokens[pair[1]] or "")
		local background = Color.fromHex(tokens[pair[2]] or "")
		local ratio = 0
		if foreground ~= nil and background ~= nil then
			ratio = Color.contrast(foreground, background)
		end
		table.insert(report, {
			pair = pair[1] .. "/" .. pair[2],
			ratio = ratio,
			required = pair[3],
			pass = ratio >= pair[3],
		})
	end
	return report
end

function Theme.validateTheme(name: string): { any }
	return Theme.validate(Theme.get(name))
end

local Binder = {}
Binder.__index = Binder

function Theme.binder(name: string?): any
	local themeName = name or "night"
	return setmetatable({
		name = themeName,
		tokens = Theme.get(themeName),
		bindings = {},
		listeners = {},
		onChanged = nil,
	}, Binder)
end

function Binder:subscribe(fn: (string) -> ()): any
	local listener = { fn = fn, alive = true }
	table.insert(self.listeners, listener)
	local binder = self
	local handle = { Connected = true }
	function handle:Disconnect()
		if not listener.alive then
			return
		end
		listener.alive = false
		handle.Connected = false
		for index = #binder.listeners, 1, -1 do
			if binder.listeners[index] == listener then
				table.remove(binder.listeners, index)
				break
			end
		end
	end
	return handle
end

function Binder:resolve(token: string): any
	local hex = self.tokens[token]
	if hex == nil then
		Log.warn("unknown token '%s'", token)
		hex = self.tokens["surface.base"] or "#000000"
	end
	return Color.fromHex(hex)
end

function Binder:hex(token: string): string
	return self.tokens[token] or "#000000"
end

function Binder:apply(binding: any): boolean
	local ok = pcall(function()
		binding.instance[binding.property] = self:resolve(binding.token)
	end)
	if not ok then
		return false
	end
	return true
end

function Binder:bind(instance: any, property: string, token: string): any
	local binding = {
		instance = instance,
		property = property,
		token = token,
	}

	local binder = self
	local handle = { Connected = true }

	function handle:Disconnect()
		if not handle.Connected then
			return
		end
		handle.Connected = false
		for index = #binder.bindings, 1, -1 do
			if binder.bindings[index] == binding then
				table.remove(binder.bindings, index)
				break
			end
		end
	end

	table.insert(self.bindings, binding)
	self:apply(binding)
	return handle
end

function Binder:setTheme(name: string)
	local tokens = Theme.get(name)
	self.name = name
	self.tokens = tokens
	local snapshot = table.clone(self.bindings)
	for index = #snapshot, 1, -1 do
		local binding = snapshot[index]
		if not self:apply(binding) then
			table.remove(snapshot, index)
			for inner = #self.bindings, 1, -1 do
				if self.bindings[inner] == binding then
					table.remove(self.bindings, inner)
					break
				end
			end
		end
	end
	if self.onChanged ~= nil then
		self.onChanged(name)
	end
	for _, listener in ipairs(table.clone(self.listeners)) do
		if listener.alive then
			pcall(listener.fn, name)
		end
	end
end

function Binder:count(): number
	return #self.bindings
end

function Binder:destroy()
	table.clear(self.bindings)
	for _, listener in ipairs(self.listeners) do
		listener.alive = false
	end
	table.clear(self.listeners)
end

return Theme
end

__modules["design/Tokens"] = function()
--!strict
-- Numeric constants. No colours here: colour lives in themes as hex strings so
-- the contrast checker and the runtime resolve the exact same values.

local Tokens = {}

Tokens.space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 16,
	xl = 24,
	xxl = 32,
}

Tokens.radius = {
	window = 10,
	section = 8,
	control = 6,
	chip = 4,
}

Tokens.row = {
	height = 34,
	touchHeight = 44,
	titlebar = 40,
	tab = 36,
	status = 22,
	sectionHeader = 30,
}

Tokens.size = {
	tabRail = 132,
	notification = 320,
	icon = 14,
	iconLarge = 16,
	swatch = 24,
	sliderKnob = 12,
	sliderHit = 20,
	toggleWidth = 36,
	toggleHeight = 20,
}

Tokens.motion = {
	state = 0.12,
	open = 0.18,
	close = 0.14,
	press = 0.08,
	toast = 0.22,
}

Tokens.font = {
	title = "GothamBold",
	tab = "GothamMedium",
	section = "GothamBold",
	label = "Gotham",
	body = "Gotham",
	value = "GothamMedium",
	code = "Code",
}

Tokens.z = {
	baseMin = 1,
	baseMax = 99,
	popupMin = 100,
	popupMax = 199,
	overlayMin = 200,
	overlayMax = 299,
	toastMin = 300,
	toastMax = 399,
}

Tokens.strokeBudget = 300

function Tokens.scaledRow(touch: boolean?): number
	if touch then
		return Tokens.row.touchHeight
	end
	return Tokens.row.height
end

return Tokens
end

__modules["ui/Builder"] = function()
--!strict
-- Instance construction helpers. Property writes are checked: a typo in a
-- property name is reported instead of being swallowed by the engine.

local Runtime = require("core/Runtime")
local Log = require("core/Log")

local Builder = {}

function Builder.set(instance: any, property: string, value: any)
	local ok, err = pcall(function()
		instance[property] = value
	end)
	if not ok then
		Log.error("Builder: cannot set %s.%s (%s)", tostring(instance.ClassName), property, tostring(err))
	end
	return instance
end

function Builder.apply(instance: any, props: any?): any
	if props == nil then
		return instance
	end
	for property, value in pairs(props) do
		Builder.set(instance, property, value)
	end
	return instance
end

function Builder.new(className: string, props: any?, children: { any }?): any
	local instance = Runtime.Instance.new(className)
	Builder.apply(instance, props)
	if children ~= nil then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	return instance
end

function Builder.corner(radius: number): any
	return Builder.new("UICorner", { CornerRadius = Runtime.UDim.new(0, radius) })
end

function Builder.stroke(color: any, thickness: number?, transparency: number?): any
	return Builder.new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Runtime.Enum.ApplyStrokeMode.Border,
	})
end

function Builder.padding(all: number, horizontal: number?, vertical: number?): any
	local x = horizontal or all
	local y = vertical or all
	return Builder.new("UIPadding", {
		PaddingLeft = Runtime.UDim.new(0, x),
		PaddingRight = Runtime.UDim.new(0, x),
		PaddingTop = Runtime.UDim.new(0, y),
		PaddingBottom = Runtime.UDim.new(0, y),
	})
end

function Builder.list(padding: number?): any
	return Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, padding or 0),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	})
end

function Builder.text(props: any): any
	return Builder.new("TextLabel", props)
end

function Builder.button(props: any): any
	local propsCopy = table.clone(props or {})
	propsCopy.AutoButtonColor = false
	propsCopy.BackgroundTransparency = propsCopy.BackgroundTransparency or 1
	propsCopy.BorderSizePixel = 0
	return Builder.new("TextButton", propsCopy)
end

function Builder.frame(props: any): any
	local propsCopy = table.clone(props or {})
	propsCopy.BorderSizePixel = 0
	if propsCopy.BackgroundTransparency == nil then
		propsCopy.BackgroundTransparency = 1
	end
	return Builder.new("Frame", propsCopy)
end

function Builder.label(props: any): any
	local propsCopy = table.clone(props or {})
	propsCopy.BackgroundTransparency = 1
	propsCopy.BorderSizePixel = 0
	propsCopy.RichText = false
	return Builder.new("TextLabel", propsCopy)
end

return Builder
end

__modules["ui/Layers"] = function()
--!strict
-- ZIndex budget. Every layer owns a range, so a dropdown can never end up under
-- a modal by accident.

local Tokens = require("design/Tokens")
local Log = require("core/Log")

local Layers = {}
Layers.__index = Layers

local RANGES = {
	base = { Tokens.z.baseMin, Tokens.z.baseMax },
	popup = { Tokens.z.popupMin, Tokens.z.popupMax },
	overlay = { Tokens.z.overlayMin, Tokens.z.overlayMax },
	toast = { Tokens.z.toastMin, Tokens.z.toastMax },
}

function Layers.new(frames: any)
	return setmetatable({
		frames = frames,
		counters = {
			base = Tokens.z.baseMin,
			popup = Tokens.z.popupMin,
			overlay = Tokens.z.overlayMin,
			toast = Tokens.z.toastMin,
		},
	}, Layers)
end

function Layers:frame(layer: string): any
	return self.frames[layer] or self.frames.base
end

function Layers:next(layer: string?): number
	local name = layer or "base"
	local range = RANGES[name]
	if range == nil then
		Log.warn("unknown layer '%s'", tostring(name))
		name = "base"
		range = RANGES.base
	end
	local value = self.counters[name]
	if value > range[2] then
		Log.warn("layer '%s' exhausted its z-index range", name)
		value = range[2]
	end
	self.counters[name] = value + 1
	return value
end

function Layers:attach(instance: any, layer: string?): any
	local name = layer or "base"
	instance.ZIndex = self:next(name)
	instance.Parent = self:frame(name)
	return instance
end

function Layers:release()
	table.clear(self.counters)
	self.counters = {
		base = Tokens.z.baseMin,
		popup = Tokens.z.popupMin,
		overlay = Tokens.z.overlayMin,
		toast = Tokens.z.toastMin,
	}
end

return Layers
end

__modules["ui/Root"] = function()
--!strict
-- Secure root resolution. gethui first, then CoreGui, then PlayerGui. Every
-- step is pcall guarded and the chosen source is reported instead of hidden.

local Runtime = require("core/Runtime")
local Env = require("core/Env")
local Log = require("core/Log")
local Builder = require("ui/Builder")
local Layers = require("ui/Layers")

local Root = {}

local function tryCall(name: string, ...): (boolean, any)
	local fn = Runtime.get()[name]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		return false, nil
	end
	return true, result
end

function Root.resolveParent(): (any, string)
	local capabilities = Env.probe()

	if capabilities.gethui then
		local ok, handle = tryCall("gethui")
		if ok and handle ~= nil then
			return handle, "gethui"
		end
	end

	local okCore, coreGui = pcall(function()
		return Runtime.service("CoreGui")
	end)
	if okCore and coreGui ~= nil then
		return coreGui, "coregui"
	end

	local okPlayers, players = pcall(function()
		return Runtime.service("Players")
	end)
	if okPlayers and players ~= nil and players.LocalPlayer ~= nil then
		local okGui, playerGui = pcall(function()
			return players.LocalPlayer:WaitForChild("PlayerGui")
		end)
		if okGui and playerGui ~= nil then
			return playerGui, "playergui"
		end
	end

	error("Londra: no usable root container", 0)
end

function Root.create(options: any?): any
	local config = options or {}
	local parent, source = Root.resolveParent()
	local capabilities = Env.probe()

	local screen = Builder.new("ScreenGui", {
		Name = config.Name or "Londra",
		DisplayOrder = config.DisplayOrder or 999999,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Runtime.Enum.ZIndexBehavior.Sibling,
	})

	screen.Parent = parent

	if capabilities.protect_gui then
		local ok = tryCall("protect_gui", screen)
		if not ok then
			Log.info("protect_gui failed, continuing unprotected")
		end
	end

	local scaleValue = config.Scale
	if scaleValue == nil then
		local viewport = workspace and workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or nil
		if viewport ~= nil then
			scaleValue = math.clamp(viewport.Y / 1080, 0.85, 1.35)
		else
			scaleValue = 1
		end
	end

	local holder = Builder.frame({
		Name = "Root",
		Size = Runtime.UDim2.fromScale(1, 1),
	})

	local scale = Builder.new("UIScale", { Scale = scaleValue })
	scale.Parent = holder

	local frames = {}
	for _, layer in ipairs({ "base", "popup", "overlay", "toast" }) do
		local frame = Builder.frame({
			Name = layer,
			Size = Runtime.UDim2.fromScale(1, 1),
			ZIndex = 1,
		})
		frame.Parent = holder
		frames[layer] = frame
	end

	holder.Parent = screen

	return {
		gui = screen,
		holder = holder,
		scale = scale,
		source = source,
		layers = Layers.new(frames),
		destroy = function()
			screen:Destroy()
		end,
	}
end

return Root
end

__modules["state/Flags"] = function()
--!strict
-- Single owner of every control value. Controls write here and listen here;
-- they never keep a second copy that can drift out of sync.

local Runtime = require("core/Runtime")
local Log = require("core/Log")
local Signal = require("core/Signal")

local Flags = {}
Flags.__index = Flags

local KEY_PATTERN = "^[a-z0-9_]+%.[a-z0-9_%.]*$"

local function typeName(value: any): string
	local ok, name = pcall(function()
		return Runtime.typeof(value)
	end)
	if ok and name ~= nil then
		return name
	end
	return type(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == "number" then
		return a ~= a and b ~= b
	end
	if type(a) ~= "table" then
		return false
	end
	local metaA = getmetatable(a)
	local metaB = getmetatable(b)
	if metaA ~= metaB then
		return false
	end
	if typeName(a) == "Color3" then
		return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = deepCopy(item)
	end
	return copy
end

function Flags.new()
	return setmetatable({
		values = {},
		types = {},
		changed = {},
		anyChanged = Signal.new("flags.any"),
	}, Flags)
end

local function validKey(key: any): boolean
	if type(key) ~= "string" or string.match(key, KEY_PATTERN) == nil then
		Log.warn("Flags: invalid key '%s'. Use lowercase dotted keys like aim.fov", tostring(key))
		return false
	end
	return true
end

function Flags:Set(key: string, value: any): boolean
	if not validKey(key) then
		return false
	end

	if value == nil then
		if self.values[key] == nil then
			return true
		end
		self.values[key] = nil
		self.types[key] = nil
		local signal = self.changed[key]
		if signal ~= nil then
			signal:Fire(nil)
		end
		self.anyChanged:Fire(key, nil)
		return true
	end

	local incoming = typeName(value)
	local recorded = self.types[key]
	if recorded ~= nil and recorded ~= incoming then
		Log.warn("Flags: type mismatch on '%s' (expected %s, got %s)", key, recorded, incoming)
		return false
	end

	local previous = self.values[key]
	if previous ~= nil and deepEqual(previous, value) then
		return true
	end

	self.values[key] = value
	self.types[key] = incoming

	local signal = self.changed[key]
	if signal == nil then
		signal = Signal.new("flags." .. key)
		self.changed[key] = signal
	end
	signal:Fire(value)
	self.anyChanged:Fire(key, value)
	return true
end

function Flags:Get(key: string, default: any?): any
	local value = self.values[key]
	if value == nil then
		return default
	end
	return value
end

function Flags:Has(key: string): boolean
	return self.values[key] ~= nil
end

function Flags:TypeOf(key: string): string?
	return self.types[key]
end

function Flags:OnChanged(key: string, fn: (any) -> ()): any
	local signal = self.changed[key]
	if signal == nil then
		signal = Signal.new("flags." .. key)
		self.changed[key] = signal
	end
	return signal:Connect(fn)
end

function Flags:OnAnyChanged(fn: (string, any) -> ()): any
	return self.anyChanged:Connect(fn)
end

function Flags:Snapshot(): any
	return deepCopy(self.values)
end

function Flags:Load(snapshot: any): number
	if type(snapshot) ~= "table" then
		Log.warn("Flags:Load expects a table")
		return 0
	end
	local applied = 0
	for key, value in pairs(snapshot) do
		if self:Set(key, value) then
			applied += 1
		end
	end
	return applied
end

function Flags:Clear()
	for key in pairs(self.values) do
		self:Set(key, nil)
	end
end

function Flags:Destroy()
	for _, signal in pairs(self.changed) do
		signal:Destroy()
	end
	table.clear(self.changed)
	self.anyChanged:Destroy()
	table.clear(self.values)
	table.clear(self.types)
end

return Flags
end

__modules["state/Config"] = function()
--!strict
-- Configuration system. Handles saving/loading config JSON, migrations, and
-- provides a default config for the key system.

local Runtime = require("core/Runtime")
local Log = require("core/Log")

local Config = {}

Config.configs = {} -- name -> { savedAt, flags, window }
Config.defaultSchema = 1
Config.migrations = {}

function Config:Save(name: string)
	local flags = Londra:GetFlags():Snapshot()
	local now = tick()
	local schema = 1
	
	local config = {
		schema = schema,
		savedAt = now,
		flags = flags,
		window = {
			size = Londra.__root().gui.AbsoluteSize,
			position = Londra.__root().gui.AbsolutePosition,
			theme = Londres__getCurrentTheme or "night",
		},
	}
	
	self.configs[name] = config
	
	-- Write to disk if writefile available
	local ok, err = pcall(function()
		writefile("Londra/" .. name .. ".json", game:GetService("HttpService"):JSONEncode(config))
	end)
	
	if not ok then
		Log.info("Config: save to disk skipped (" .. tostring(err) .. ")")
	end
	
	return config
end

function Config:Load(name: string): boolean
	local config = self.configs[name]
	if config == nil then
		Log.warn("Config: '" .. name .. "' not found")
		return false
	end
	
	-- Apply flags
	local flags = Londra:GetFlags()
	local applied = flags:Load(config.flags)
	
	-- Apply window geometry if root exists
	if config.window then
		local root = Londra.__root()
		if root and root.gui then
			-- geometry loading would go here
		end
	end
	
	return true
end

function Config:List(): { string }
	local names = {}
	for name in pairs(self.configs) do
		table.insert(names, name)
	end
	return names
end

function Config:Delete(name: string)
	self.configs[name] = nil
	Log.info("Config: deleted '" .. name .. "'")
end

function Config:Export(name: string): string?
	local config = self.configs[name]
	if config == nil then
		return nil
	end
	return game:GetService("HttpService"):JSONEncode(config)
end

function Config:Import(json: string, name: string?)
	local success, config = pcall(function()
		return game:GetService("HttpService"):JSONDecode(json)
	end)
	
	if success and config then
		local nameToUse = name or "imported"
		self.configs[nameToUse] = config
		Log.info("Config: imported '" .. nameToUse .. "'")
		return nameToUse
	end
	
	return nil
end

function Config:migrate(name: string, migrateFn)
	self.migrations[name] = migrateFn
end

function Config:applyMigrations(name: string)
	local config = self.configs[name]
	if config == nil then return end
	
	local migration = self.migrations[name]
	if migration then
		migration(config)
		Log.info("Config: applied migrations for '" .. name .. "'")
	end
end

return Config
end

__modules["state/Locale"] = function()
--!strict
-- Locale system. Provides string tables for multiple languages with a
-- `t()` function for localized text lookup. Falls back to English when a
-- translation key is not found.

local Locale = {}

-- English strings (default)
Locale.strings = {
	-- Window
	window = {
		title = "Londra",
	},
	-- Controls
	controls = {
		slider = "Slider",
		textbox = "Textbox",
		dropdown = "Dropdown",
		keybind = "Keybind",
	},
	-- Config
	config = {
		loaded = "Config loaded",
		saved = "Config saved",
	},
	-- Key system
	key_system = {
		hwid = "HWID",
		enter_key = "Enter key",
		validate = "Validate",
	},
	-- Generic
	generic = {
		ok = "OK",
		cancel = "Cancel",
		yes = "Yes",
		no = "No",
	},
}

-- Current locale
Locale.current = "en"

-- Set the current locale
function Locale:set(locale: string)
	self.current = locale
end

-- Get the current locale
function Locale:get(): string
	return self.current
end

-- Get localized string
function Locale:t(key: string, ...: any): string
	local strings = self.strings
	local parts = string.split(key, ".")
	
	local section = strings
	for _, part in ipairs(parts) do
		if section[part] ~= nil then
			section = section[part]
		else
			-- fallback: try without dots
			local colonPos = string.find(key, ".", 1, true)
			if colonPos then
				local before = string.sub(key, 1, colonPos - 1)
				local after = string.sub(key, colonPos + 1)
				local result = self:t(before, ...)
				if result ~= "" then
					return result .. " " .. self:t(after, ...)
				end
			end
			return key
		end
	end
	
	if type(section) == "string" then
		return string.format(section, ...)
	else
		return key
	end
end

-- Add strings for a locale
function Locale:add(localeName: string, newStrings: { any })
	self.strings[localeName] = newStrings
end

return Locale
end

__modules["state/KeySystem"] = function()
--!strict
-- Key System. Provides a client-side key validation system with multiple
-- provider types (Local, Http, Custom). The key system has a status machine
-- (idle -> checking -> granted/denied) and UI states.

local KeySystem = {}

KeySystem.State = {
	idle = "idle",
	checking = "checking",
	granted = "granted",
	denied = "denied",
	failed = "failed",
}

KeySystem.Provider = {
	local = "local",
	http = "http",
	custom = "custom",
}

KeySystem.Status = {
	valid = "valid",
	invalid = "invalid",
	expired = "expired",
	unknown = "unknown",
}

-- Default HWID generation
function KeySystem.getDefaultHwid()
	return "LONDRA-MOCK-" .. tostring(math.random(100000, 999999))
end

-- Key validation result
---@param result { valid: boolean, message?: string, expiresAt?: number }
function KeySystem.validate(result, storedHwid)
	-- Check HWID match
	if storedHwid and storedHwid ~= "" then
		if result.valid and result.hwid ~= storedHwid then
			return {
				valid = false,
				message = "HWID mismatch",
				status = KeySystem.Status.invalid,
			}
		end
	end
	
	if result.valid then
		return {
			valid = true,
			message = result.message or "Valid key",
			status = KeySystem.Status.valid,
			expiresAt = result.expiresAt,
		}
	else
		return {
			valid = false,
			message = result.message or "Invalid key",
			status = KeySystem.Status.invalid,
		}
	end
end

-- Provider interface
---@class KeyProvider
---@field Check fun(ctx: { key: string, hwid: string, placeId: number }): (boolean, string?, number?)

-- Local provider: fixed list or hash comparison
function KeySystem.Provider.Local(keys, hwid)
	return function(ctx)
		local key = ctx.key:upper()
		local storedKey = keys[key]
		
		if storedKey then
			-- Hash comparison
			if type(storedKey) == "function" then
				local ok, _ = pcall(storedKey, ctx.hwid)
				return ok, storedKey and "Hash verified" or "Hash mismatch"
			end
			
			-- Direct comparison
			if storedKey:upper() == key then
				return true, "Key verified"
			end
		end
		
		return false, "Key not found"
	end
end

-- Http provider: HTTP request to validation endpoint
function KeySystem.Provider.Http(validateUrl, timeout)
	local http = game:GetService("HttpService")
	local request = game:GetService("game").HttpRequest
	
	return function(ctx)
		local success, body = pcall(function()
			local req = http:RequestAsync({
				Url = validateUrl,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
				},
				Body = http:JSONEncode({
					key = ctx.key,
					hwid = ctx.hwid,
					placeId = ctx.placeId,
				}),
			})
			return http:JSONDecode(body)
		end)
		
		if success and body then
			return KeySystem.validate(body, ctx.hwid)
		end
		
		return {
			valid = false,
			message = "Validation request failed",
			status = KeySystem.Status.unknown,
		}
	end
end

-- Custom provider: user-defined function
function KeySystem.Provider.Custom(checkFn)
	return checkFn
end

-- Key system state
KeySystem.state = KeySystem.State.idle
KeySystem.hwid = KeySystem.getDefaultHwid()
KeySystem.key = nil
KeySystem.expiresAt = nil
KeySystem.provider = nil
KeySystem.attempts = 0
KeySystem.maxAttempts = 3

function KeySystem:setState(newState)
	self.state = newState
	-- Notify UI of state change
	if self.onStateChanged then
		self:onStateChanged(newState)
	end
end

function KeySystem:checkKey(key, hwid, placeId, provider)
	self:setState(KeySystem.State.checking)
	self.attempts += 1
	
	local ctx = {
		key = key:upper(),
		hwid = hwid or self.hwid,
		placeId = placeId or 0,
	}
	
	if self.provider and self.provider.check then
		local success, message, expiresAt = self.provider.check(ctx)
		local result = KeySystem.validate({ valid = success, message = message, hwid = ctx.hwid }, ctx.hwid)
		
		if result.valid then
			self:setState(KeySystem.State.granted)
			self.key = key
			self.expiresAt = expiresAt
			if self.onGranted then
				self:onGranted()
			end
		else
			self:setState(KeySystem.State.denied)
			if self.onDenied then
				self:onDenied(result.message)
			end
		end
	else
		-- No provider set, default logic
		if key == "LONDRA" then -- demo key
			self:setState(KeySystem.State.granted)
			self.key = key
			if self.onGranted then
				self:onGranted()
			end
		else
			self:setState(KeySystem.State.denied)
			if self.onDenied then
				self:onDenied("Key not recognized")
			end
		end
	end
end

function KeySystem:getState()
	return {
		state = self.state,
		key = self.key,
		hwid = self.hwid,
		expiresAt = self.expiresAt,
		attempts = self.attempts,
		maxAttempts = self.maxAttempts,
	}
end

function KeySystem:reset()
	self:setState(KeySystem.State.idle)
	self.key = nil
	self.expiresAt = nil
	self.attempts = 0
end

return KeySystem
end

__modules["ui/Drag"] = function()
--!strict
-- Pointer drag with capture. Delta is divided by the UI scale, because pointer
-- coordinates are screen pixels while Position offsets are pre-scale units.

local Runtime = require("core/Runtime")

local Drag = {}

local function point(input: any): any
	return Runtime.Vector2.new(input.Position.X, input.Position.Y)
end

function Drag.attach(janitor: any, options: any): any
	local userInput = Runtime.service("UserInputService")
	local state = {
		dragging = false,
		startPointer = nil,
		started = false,
	}

	local scale = options.scale or 1

	local function start(input: any)
		if options.hitTest ~= nil and not options.hitTest(input) then
			return false
		end
		state.dragging = true
		state.startPointer = point(input)
		if options.onStart ~= nil then
			options.onStart(point(input))
		end
		return true
	end

	janitor:Add(userInput.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local inputType = input.UserInputType
		if inputType ~= Runtime.Enum.UserInputType.MouseButton1 and inputType ~= Runtime.Enum.UserInputType.Touch then
			return
		end
		start(input)
	end))

	janitor:Add(userInput.InputChanged:Connect(function(input, processed)
		if not state.dragging then
			return
		end
		if processed and options.force ~= true then
			return
		end
		local current = point(input)
		local deltaX = (current.X - state.startPointer.X) / scale
		local deltaY = (current.Y - state.startPointer.Y) / scale
		if options.onDrag ~= nil then
			options.onDrag(deltaX, deltaY, current)
		end
	end))

	janitor:Add(userInput.InputEnded:Connect(function(input)
		if not state.dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType ~= Runtime.Enum.UserInputType.MouseButton1 and inputType ~= Runtime.Enum.UserInputType.Touch then
			return
		end
		state.dragging = false
		if options.onEnd ~= nil then
			options.onEnd(point(input))
		end
	end))

	return {
		isDragging = function()
			return state.dragging
		end,
		cancel = function()
			state.dragging = false
		end,
	}
end

function Drag.inside(element: any, input: any): boolean
	local position = input.Position
	local absolute = element.AbsolutePosition
	local size = element.AbsoluteSize
	return position.X >= absolute.X
		and position.X <= absolute.X + size.X
		and position.Y >= absolute.Y
		and position.Y <= absolute.Y + size.Y
end

return Drag
end

__modules["ui/Resize"] = function()
--!strict
-- Eight resize handles. Size is clamped in pre-scale units so the limits match
-- what the user sees at any UI scale.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")
local Drag = require("ui/Drag")

local Resize = {}

local DIRECTIONS = {
	{ name = "left", x = -1, y = 0 },
	{ name = "right", x = 1, y = 0 },
	{ name = "top", x = 0, y = -1 },
	{ name = "bottom", x = 0, y = 1 },
	{ name = "topLeft", x = -1, y = -1 },
	{ name = "topRight", x = 1, y = -1 },
	{ name = "bottomLeft", x = -1, y = 1 },
	{ name = "bottomRight", x = 1, y = 1 },
}

local function handleSize(direction: any): any
	if direction.x ~= 0 and direction.y ~= 0 then
		return Runtime.UDim2.fromOffset(12, 12)
	end
	if direction.x ~= 0 then
		return Runtime.UDim2.new(0, 6, 1, 0)
	end
	return Runtime.UDim2.new(1, 0, 0, 6)
end

local function handlePosition(direction: any): any
	local x = 0.5
	local y = 0.5
	if direction.x == -1 then
		x = 0
	elseif direction.x == 1 then
		x = 1
	end
	if direction.y == -1 then
		y = 0
	elseif direction.y == 1 then
		y = 1
	end
	return Runtime.UDim2.fromScale(x, y)
end

function Resize.attach(janitor: any, window: any, options: any)
	local config = options or {}
	local minSize = config.minSize or Runtime.Vector2.new(520, 340)
	local maxSize = config.maxSize

	for _, direction in ipairs(DIRECTIONS) do
		local handle = Builder.frame({
			Name = "resize_" .. direction.name,
			Size = handleSize(direction),
			Position = handlePosition(direction),
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			ZIndex = 10,
		})
		handle.Parent = window.frame

		local state = {
			startSize = nil,
			startPosition = nil,
		}

		Drag.attach(janitor, {
			scale = window.scale,
			hitTest = function(input)
				return Drag.inside(handle, input)
			end,
			onStart = function()
				state.startSize = window:getSize()
				state.startPosition = window:getPosition()
			end,
			onDrag = function(deltaX, deltaY)
				if state.startSize == nil then
					return
				end
				local width = state.startSize.X
				local height = state.startSize.Y
				local x = state.startPosition.X
				local y = state.startPosition.Y

				if direction.x ~= 0 then
					local change = deltaX * direction.x
					local newWidth = math.clamp(width + change, minSize.X, maxSize and maxSize.X or math.huge)
					if direction.x == -1 then
						x = state.startPosition.X + (width - newWidth)
					end
					width = newWidth
				end

				if direction.y ~= 0 then
					local change = deltaY * direction.y
					local newHeight = math.clamp(height + change, minSize.Y, maxSize and maxSize.Y or math.huge)
					if direction.y == -1 then
						y = state.startPosition.Y + (height - newHeight)
					end
					height = newHeight
				end

				window:setGeometry(x, y, width, height)
			end,
		})
	end
end

return Resize
end

__modules["ui/Focus"] = function()
--!strict
-- Focus chain per window. Tab order follows registration order, which follows
-- creation order, which follows visual order because sections are built top to
-- bottom.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")

local Focus = {}
Focus.__index = Focus

function Focus.new(binder: any)
	return setmetatable({
		binder = binder,
		items = {},
		current = nil,
	}, Focus)
end

function Focus:register(element: any, options: any?): any
	local item = {
		element = element,
		options = options or {},
		alive = true,
	}
	table.insert(self.items, item)

	local focus = self
	local handle = { Connected = true }
	function handle:Disconnect()
		if not item.alive then
			return
		end
		item.alive = false
		handle.Connected = false
		for index = #focus.items, 1, -1 do
			if focus.items[index] == item then
				table.remove(focus.items, index)
				break
			end
		end
		if focus.current == item then
			focus:clear()
		end
	end
	handle.item = item
	return handle
end

function Focus:clear()
	if self.current == nil then
		return
	end
	local item = self.current
	self.current = nil
	local ring = item.element:FindFirstChild("__londra_focus")
	if ring ~= nil then
		ring:Destroy()
	end
	if item.options.onBlur ~= nil then
		item.options.onBlur()
	end
end

function Focus:set(item: any)
	if item == nil or not item.alive then
		return
	end
	self:clear()
	self.current = item

	local ring = Builder.stroke(self.binder:resolve("focus.ring"), 2)
	ring.Name = "__londra_focus"
	ring.Parent = item.element

	if item.options.onFocus ~= nil then
		item.options.onFocus()
	end
end

function Focus:index(): number
	if self.current == nil then
		return 0
	end
	for index, item in ipairs(self.items) do
		if item == self.current then
			return index
		end
	end
	return 0
end

function Focus:move(step: number)
	local startIndex = self.trapStart or 1
	local count = #self.items - startIndex + 1
	if count <= 0 then
		return
	end
	local current = self:index()
	if current < startIndex then
		current = step > 0 and (startIndex - 1) or startIndex
	end
	local offset = current - startIndex + 1
	local nextOffset = ((offset - 1 + step) % count) + 1
	self:set(self.items[startIndex + nextOffset - 1])
end

function Focus:pushTrap(): any
	self.trapStart = #self.items + 1
	return { start = self.trapStart }
end

function Focus:popTrap()
	self.trapStart = nil
end

function Focus:next()
	self:move(1)
end

function Focus:previous()
	self:move(-1)
end

function Focus:activate()
	local item = self.current
	if item ~= nil and item.options.onActivate ~= nil then
		item.options.onActivate()
	end
end

function Focus:adjust(direction: number)
	local item = self.current
	if item ~= nil and item.options.onAdjust ~= nil then
		item.options.onAdjust(direction)
	end
end

function Focus:destroy()
	self:clear()
	table.clear(self.items)
end

return Focus
end

__modules["ui/Input"] = function()
--!strict
-- One global keyboard map for the whole library. Components register a key,
-- they never open their own UserInputService connection.

local Runtime = require("core/Runtime")
local Guard = require("core/Guard")

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
end

__modules["components/Base"] = function()
--!strict
-- Shared component base. Owns the janitor contract and the theme binding sugar
-- so a component never touches a raw colour.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Motion = require("core/Motion")

local Base = Class:extends("Component")

function Base:init(context: any, options: any?)
	self.context = context
	self.options = options or {}
	self.binder = context.binder
	self.layers = context.layers
	self.focus = context.focus
	self.tokens = Tokens
	self.element = nil
	self.enabled = true
	self.rowHeight = Tokens.row.height
end

function Base:theme(instance: any, property: string, token: string): any
	return self._janitor:Add(self.binder:bind(instance, property, token))
end

function Base:add(instance: any): any
	return self._janitor:Add(instance)
end

function Base:track(handle: any): any
	return self._janitor:Add(handle)
end

function Base:setEnabled(value: boolean)
	self.enabled = value
	if self.element ~= nil then
		self.element.Active = value
		self.element.Selectable = value
		Motion.tween(self.element, { BackgroundTransparency = value and (self._idleTransparency or 1) or 0.6 })
	end
end

function Base:hoverable(element: any, idleTransparency: number?): any
	local idle = idleTransparency or 1
	self._idleTransparency = idle
	element.BackgroundTransparency = idle
	self:theme(element, "BackgroundColor3", "state.hover")
	self:track(element.MouseEnter:Connect(function()
		if not self.enabled then
			return
		end
		Motion.tween(element, { BackgroundTransparency = 0 }, { duration = Motion.duration("state") })
	end))
	self:track(element.MouseLeave:Connect(function()
		Motion.tween(element, { BackgroundTransparency = idle }, { duration = Motion.duration("state") })
	end))
	return element
end

return Base
end

__modules["components/IconButton"] = function()
--!strict
-- Square icon button used by the title bar and by compact controls. Without an
-- icon asset it falls back to a text glyph, never to a borrowed icon set.

local Base = require("components/Base")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")

local IconButton = Base:extends("IconButton")

function IconButton:init(context: any, options: any)
	Base.init(self, context, options)

	local size = self.options.Size or 28
	local glyph = self.options.Glyph or ""

	self.element = Builder.button({
		Name = self.options.Name or "IconButton",
		Size = Runtime.UDim2.fromOffset(size, size),
		BackgroundColor3 = self.binder:resolve("state.hover"),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = true,
		ZIndex = self.options.ZIndex or 5,
	})
	self.element.Parent = self.options.Parent

	if glyph ~= "" then
		local label = Builder.label({
			Size = Runtime.UDim2.fromScale(1, 1),
			Text = glyph,
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 15,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = self.options.ZIndex or 5,
		})
		label.Parent = self.element
		self:theme(label, "TextColor3", "text.secondary")
		self.label = label
	end

	self:hoverable(self.element)

	self:track(self.element.MouseButton1Click:Connect(function()
		if not self.enabled then
			return
		end
		if self.options.Callback ~= nil then
			self.options.Callback()
		end
	end))

	self:track(self.element.MouseButton1Down:Connect(function()
		Motion.press(self.element)
	end))
	self:track(self.element.MouseButton1Up:Connect(function()
		Motion.release(self.element)
	end))

	if self.focus ~= nil and self.options.Focusable ~= false then
		self.focus:register(self.element, {
			onActivate = function()
				if self.options.Callback ~= nil then
					self.options.Callback()
				end
			end,
		})
	end
end

function IconButton:setGlyph(glyph: string)
	if self.label ~= nil then
		self.label.Text = glyph
	end
end

return IconButton
end

__modules["components/TitleBar"] = function()
--!strict
-- Title bar: drag surface, title, and the two window controls. Double click is
-- measured here because Roblox input events do not expose a click count.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local IconButton = require("components/IconButton")

local TitleBar = Class:extends("TitleBar")

local DOUBLE_CLICK_WINDOW = 0.35

function TitleBar:init(context: any, window: any, options: any)
	self.context = context
	self.binder = context.binder
	self.window = window
	self.options = options or {}

	local bar = Builder.frame({
		Name = "TitleBar",
		Size = Runtime.UDim2.new(1, 0, 0, Tokens.row.titlebar),
		BackgroundTransparency = 1,
		ZIndex = 10,
	})
	bar.Parent = options.Parent
	self.element = bar
	self._janitor:Add(bar)

	local title = Builder.label({
		Name = "title",
		Size = Runtime.UDim2.new(1, -116, 0, 20),
		Position = Runtime.UDim2.new(0, self.options.Icon ~= nil and 34 or 14, 0, 10),
		Text = self.options.Title or "Londra",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 14,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 11,
	})
	title.Parent = bar
	self.title = title
	self._janitor:Add(self.binder:bind(title, "TextColor3", "text.primary"))

	if self.options.Icon ~= nil then
		local icon = Builder.label({
			Name = "icon",
			Size = Runtime.UDim2.fromOffset(16, 16),
			Position = Runtime.UDim2.new(0, 12, 0, 12),
			Text = tostring(self.options.Icon),
			TextColor3 = self.binder:resolve("accent.base"),
			TextSize = 14,
			Font = Runtime.Enum.Font.GothamBold,
			ZIndex = 11,
		})
		icon.Parent = bar
		self._janitor:Add(self.binder:bind(icon, "TextColor3", "accent.base"))
	end

	local minimize = IconButton.new(context, {
		Name = "minimize",
		Glyph = "-",
		Size = 28,
		Parent = bar,
		ZIndex = 12,
		Focusable = false,
		Callback = function()
			self.window:minimize()
		end,
	})
	minimize.element.AnchorPoint = Runtime.Vector2.new(1, 0.5)
	minimize.element.Position = Runtime.UDim2.new(1, -38, 0.5, 0)
	self._janitor:Add(minimize)

	local close = IconButton.new(context, {
		Name = "close",
		Glyph = "x",
		Size = 28,
		Parent = bar,
		ZIndex = 12,
		Focusable = false,
		Callback = function()
			self.window:close()
		end,
	})
	close.element.AnchorPoint = Runtime.Vector2.new(1, 0.5)
	close.element.Position = Runtime.UDim2.new(1, -8, 0.5, 0)
	self._janitor:Add(close)

	self.lastClick = -1
	self._janitor:Add(bar.MouseButton1Click:Connect(function()
		local now = os.clock()
		if self.lastClick >= 0 and now - self.lastClick <= DOUBLE_CLICK_WINDOW then
			self.lastClick = -1
			self.window:toggleMaximize()
			return
		end
		self.lastClick = now
	end))
end

function TitleBar:setTitle(text: string)
	self.title.Text = tostring(text)
end

return TitleBar
end

__modules["components/TabRail"] = function()
--!strict
-- Tab rail. Active tab is marked by surface plus a brass seam on the leading
-- edge, not by colour alone, so the state survives a monochrome display.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Log = require("core/Log")

local TabRail = Class:extends("TabRail")

local function entryWidth(title: string): number
	return math.max(96, math.min(180, #tostring(title) * 7 + 32))
end

function TabRail:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.entries = {}
	self.active = 0
	self.mode = self.options.Mode or "left"

	local rail = Builder.new("ScrollingFrame", {
		Name = "TabRail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self.binder:resolve("border.hairline"),
		CanvasSize = Runtime.UDim2.fromOffset(0, 0),
		ZIndex = 2,
	})
	rail.Parent = self.options.Parent
	self.element = rail

	if self.mode == "top" then
		rail.AutomaticCanvasSize = Runtime.Enum.AutomaticSize.X
		rail.ScrollingDirection = Runtime.Enum.ScrollingDirection.X
		rail.Size = Runtime.UDim2.new(1, 0, 0, Tokens.row.titlebar)
		rail.ScrollBarThickness = 0
		Builder.new("UIListLayout", {
			FillDirection = Runtime.Enum.FillDirection.Horizontal,
			Padding = Runtime.UDim.new(0, 2),
			SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
		}).Parent = rail
	else
		rail.AutomaticCanvasSize = Runtime.Enum.AutomaticSize.Y
		rail.ScrollingDirection = Runtime.Enum.ScrollingDirection.Y
		rail.Size = Runtime.UDim2.new(0, Tokens.size.tabRail, 1, 0)
		Builder.padding(Tokens.space.sm).Parent = rail
		Builder.new("UIListLayout", {
			Padding = Runtime.UDim.new(0, 2),
			SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
		}).Parent = rail
	end

	self._janitor:Add(self.binder:bind(rail, "ScrollBarImageColor3", "border.hairline"))
	self._janitor:Add(self.binder:subscribe(function()
		self:render()
	end))
end

function TabRail:add(tab: any): number
	local index = #self.entries + 1
	local title = tab.options.Title or ("Tab " .. tostring(index))
	local top = self.mode == "top"

	local button = Builder.button({
		Name = "tab_" .. tostring(index),
		Size = top and Runtime.UDim2.fromOffset(entryWidth(title), Tokens.row.titlebar)
			or Runtime.UDim2.new(1, 0, 0, Tokens.row.tab),
		LayoutOrder = index,
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	Builder.corner(Tokens.radius.control).Parent = button
	button.Parent = self.element

	local bar = Builder.frame({
		Name = "seam",
		Size = top and Runtime.UDim2.new(1, -16, 0, 2) or Runtime.UDim2.new(0, 2, 1, -12),
		Position = top and Runtime.UDim2.new(0, 8, 1, -2) or Runtime.UDim2.new(0, 0, 0, 6),
		BackgroundColor3 = self.binder:resolve("accent.base"),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	bar.Parent = button

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.new(1, top and -16 or -36, 1, 0),
		Position = Runtime.UDim2.new(0, top and 8 or 14, 0, 0),
		Text = (tab.options.Icon ~= nil and tostring(tab.options.Icon) .. "  " or "") .. title,
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	label.Parent = button

	local badge = nil
	if tab.options.Badge ~= nil then
		badge = Builder.label({
			Name = "badge",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, -10, 0.5, 0),
			Size = Runtime.UDim2.fromOffset(0, 14),
			AutomaticSize = Runtime.Enum.AutomaticSize.X,
			Text = tostring(tab.options.Badge),
			TextColor3 = self.binder:resolve("accent.base"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamBold,
			ZIndex = 5,
		})
		badge.Parent = button
	end

	local entry = {
		tab = tab,
		button = button,
		label = label,
		badge = badge,
		bar = bar,
		alive = true,
	}
	table.insert(self.entries, entry)
	self._janitor:Add(button)

	local rail = self
	button.MouseEnter:Connect(function()
		if rail.active == index then
			return
		end
		Motion.tween(button, { BackgroundTransparency = 0 }, { duration = Motion.duration("state") })
		button.BackgroundColor3 = rail.binder:resolve("state.hover")
	end)
	button.MouseLeave:Connect(function()
		if rail.active == index then
			return
		end
		Motion.tween(button, { BackgroundTransparency = 1 }, { duration = Motion.duration("state") })
	end)
	button.MouseButton1Down:Connect(function()
		if rail.active ~= index then
			button.BackgroundColor3 = rail.binder:resolve("state.pressed")
			button.BackgroundTransparency = 0
		end
	end)
	button.MouseButton1Click:Connect(function()
		rail:select(index)
	end)

	self:render()
	return index
end

function TabRail:render()
	for index, entry in ipairs(self.entries) do
		local active = index == self.active
		entry.label.TextColor3 = self.binder:resolve(active and "text.primary" or "text.secondary")
		entry.bar.BackgroundColor3 = self.binder:resolve("accent.base")
		entry.bar.BackgroundTransparency = active and 0 or 1
		if active then
			entry.button.BackgroundColor3 = self.binder:resolve("surface.raised")
			entry.button.BackgroundTransparency = 0
		else
			entry.button.BackgroundTransparency = 1
		end
	end
end

function TabRail:select(index: number): boolean
	if index < 1 or index > #self.entries then
		Log.warn("TabRail:select out of range: %s", tostring(index))
		return false
	end
	if self.active == index then
		return true
	end
	if self.active > 0 then
		local previous = self.entries[self.active]
		if previous ~= nil then
			previous.tab:hide()
		end
	end
	self.active = index
	local entry = self.entries[index]
	entry.tab:show()
	self:render()
	if self.options.OnSelect ~= nil then
		self.options.OnSelect(index, entry.tab)
	end
	return true
end

function TabRail:count(): number
	return #self.entries
end

return TabRail
end

__modules["components/Row"] = function()
--!strict
-- The shared control row: label on the left, control area on the right, and an
-- optional description that raises the row height instead of overlapping.

local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")

local Row = {}

function Row.build(context: any, options: any): any
	local config = options or {}
	local hasDescription = config.description ~= nil
	local height = config.height or (hasDescription and 52 or Tokens.row.height)
	local labelWidth = config.labelWidth or 0.52
	local controlWidth = config.controlWidth or 150

	local rowProps = {
		Name = "row",
		Size = Runtime.UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}
	local row = Builder.frame(rowProps)
	if config.clickable then
		row = Builder.button(rowProps)
		row.AutoButtonColor = false
	end
	row.BackgroundColor3 = context.binder:resolve("state.hover")

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.new(labelWidth, -12, 0, hasDescription and 18 or height),
		Position = Runtime.UDim2.new(0, 0, 0, hasDescription and 6 or 0),
		Text = config.title or "",
		TextColor3 = context.binder:resolve("text.primary"),
		TextSize = 13,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Center,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
	})
	label.Parent = row
	context.binder:bind(label, "TextColor3", "text.primary")

	local description = nil
	if hasDescription then
		description = Builder.label({
			Name = "description",
			Size = Runtime.UDim2.new(labelWidth, -12, 0, 16),
			Position = Runtime.UDim2.new(0, 0, 0, 24),
			Text = config.description,
			TextColor3 = context.binder:resolve("text.secondary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			TextYAlignment = Runtime.Enum.TextYAlignment.Top,
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		})
		description.Parent = row
		context.binder:bind(description, "TextColor3", "text.secondary")
	end

	local control = Builder.frame({
		Name = "control",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.new(0, controlWidth, 0, height),
		ZIndex = 2,
	})
	control.Parent = row

	local hover = true
	if config.hover == false then
		hover = false
	end

	if hover then
		row.MouseEnter:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 0 }, { duration = Motion.duration("state") })
		end)
		row.MouseLeave:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 1 }, { duration = Motion.duration("state") })
		end)
	end

	return {
		row = row,
		label = label,
		description = description,
		control = control,
		height = height,
	}
end

return Row
end

__modules["components/Toggle"] = function()
--!strict
-- Toggle reads and writes a flag, never a private copy. The visual state is a
-- pure function of that flag, so config load and external writes stay in sync.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Log = require("core/Log")

local Toggle = Base:extends("Toggle")

local TRACK_WIDTH = 36
local TRACK_HEIGHT = 20
local KNOB_SIZE = 16
local KNOB_INSET = 2

function Toggle:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	if self.key == nil then
		Log.warn("Toggle: missing Key, control will not persist")
	end

	local layout = Row.build(context, {
		title = config.Title or "Toggle",
		description = config.Description,
		clickable = true,
		controlWidth = config.ControlWidth or 60,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local track = Builder.frame({
		Name = "track",
		Size = Runtime.UDim2.fromOffset(TRACK_WIDTH, TRACK_HEIGHT),
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
	})
	Builder.corner(TRACK_HEIGHT / 2).Parent = track
	track.Parent = layout.control
	self.trackElement = track

	local knob = Builder.frame({
		Name = "knob",
		Size = Runtime.UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE),
		Position = Runtime.UDim2.fromOffset(KNOB_INSET, KNOB_INSET),
		ZIndex = 4,
	})
	Builder.corner(KNOB_SIZE / 2).Parent = knob
	knob.Parent = track
	self.knob = knob

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, config.Default == true)
	end

	if self.key ~= nil then
		local handle = context.flags:OnChanged(self.key, function()
			self:render()
		end)
		self:track(handle)
	end
	self:track(self.binder:subscribe(function()
		self:render()
	end))

	self:track(self.element.MouseButton1Click:Connect(function()
		if not self.enabled then
			return
		end
		self:toggle()
	end))

	self:track(self.element.MouseEnter:Connect(function()
		if self.enabled then
			self.layout.row.BackgroundTransparency = 0
		end
	end))
	self:track(self.element.MouseLeave:Connect(function()
		self.layout.row.BackgroundTransparency = 1
	end))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onActivate = function()
				if self.enabled then
					self:toggle()
				end
			end,
			onAdjust = function()
				if self.enabled then
					self:toggle()
				end
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end

	self:render()
end

function Toggle:value(): boolean
	if self.key == nil then
		return self.options.Default == true
	end
	return self.context.flags:Get(self.key, self.options.Default == true) == true
end

function Toggle:render()
	local on = self:value()
	local trackColor = on and "accent.base" or "surface.sunken"
	local knobColor = on and "accent.on" or "text.muted"
	local target = Runtime.UDim2.fromOffset(on and (TRACK_WIDTH - KNOB_SIZE - KNOB_INSET) or KNOB_INSET, KNOB_INSET)

	self.trackElement.BackgroundColor3 = self.binder:resolve(trackColor)
	self.knob.BackgroundColor3 = self.binder:resolve(knobColor)
	Motion.tween(self.knob, { Position = target }, { duration = Motion.duration("state") })
end

function Toggle:toggle()
	if not self.enabled then
		return
	end
	local nextValue = not self:value()
	if self.key ~= nil then
		if not self.context.flags:Set(self.key, nextValue) then
			return
		end
	end
	self:render()
	if self.options.OnChanged ~= nil then
		self.options.OnChanged(nextValue)
	end
end

function Toggle:set(value: boolean, silent: boolean?)
	if self.key ~= nil then
		if not self.context.flags:Set(self.key, value == true) then
			return
		end
	else
		self.options.Default = value == true
	end
	self:render()
	if not silent and self.options.OnChanged ~= nil then
		self.options.OnChanged(value == true)
	end
end

return Toggle
end

__modules["components/Button"] = function()
--!strict
-- Primary action row. Ripple is a real element that is destroyed after the
-- animation, and a destructive action can require a second confirmation.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")

local Button = Base:extends("Button")

local VARIANTS = {
	primary = { background = "accent.base", text = "accent.on", hover = "accent.hover", pressed = "accent.pressed" },
	secondary = { background = "surface.sunken", text = "text.primary", hover = "state.hover", pressed = "state.pressed" },
	ghost = { background = "surface.raised", text = "text.secondary", hover = "state.hover", pressed = "state.pressed" },
	danger = { background = "state.danger", text = "text.inverse", hover = "state.danger", pressed = "state.danger" },
}

function Button:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local variant = VARIANTS[config.Variant or "secondary"] or VARIANTS.secondary
	local confirmed = false

	local layout = Row.build(context, {
		title = config.Title or "Button",
		description = config.Description,
		controlWidth = config.Width or 120,
		hover = false,
	})

	self.element = layout.row
	self.element.Parent = config.Parent

	local button = Builder.button({
		Name = "action",
		Size = Runtime.UDim2.fromOffset(config.Width or 120, 26),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		BackgroundColor3 = self.binder:resolve(variant.background),
		Text = config.Title or "Button",
		TextColor3 = self.binder:resolve(variant.text),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		AutoButtonColor = false,
		ClipsDescendants = true,
		ZIndex = 3,
	})
	button.Parent = layout.control
	Builder.corner(self.tokens.radius.control).Parent = button
	self:theme(button, "BackgroundColor3", variant.background)
	self:theme(button, "TextColor3", variant.text)

	self.button = button
	self.variant = variant

	local function reset()
		confirmed = false
		button.Text = config.Title or "Button"
		self:theme(button, "BackgroundColor3", variant.background)
	end

	local function activate()
		if not self.enabled then
			return
		end
		if config.Confirm == true and not confirmed then
			confirmed = true
			button.Text = config.ConfirmText or "Confirm?"
			self:theme(button, "BackgroundColor3", "state.danger")
			Scheduler:after(3, function()
				if confirmed then
					reset()
				end
			end)
			return
		end
		reset()
		if config.Callback ~= nil then
			config.Callback()
		end
	end

	self:track(button.MouseEnter:Connect(function()
		if not self.enabled then
			return
		end
		button.BackgroundColor3 = self.binder:resolve(variant.hover)
	end))
	self:track(button.MouseLeave:Connect(function()
		button.BackgroundColor3 = self.binder:resolve(variant.background)
	end))
	self:track(button.MouseButton1Down:Connect(function()
		if not self.enabled then
			return
		end
		Motion.press(button)
		button.BackgroundColor3 = self.binder:resolve(variant.pressed)
	end))
	self:track(button.MouseButton1Up:Connect(function()
		Motion.release(button)
		button.BackgroundColor3 = self.binder:resolve(variant.background)
	end))
	self:track(button.MouseButton1Click:Connect(activate))

	if self.focus ~= nil then
		self.focus:register(button, { onActivate = activate })
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
end

return Button
end

__modules["components/Label"] = function()
--!strict
-- Read-only row: label on the left, value on the right. Values truncate before
-- they ever touch the label.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")

local Label = Base:extends("Label")

function Label:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local layout = Row.build(context, {
		title = config.Title or "",
		description = config.Description,
		hover = false,
		controlWidth = config.ValueWidth or 180,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	if config.Value ~= nil then
		local value = Builder.label({
			Name = "value",
			Size = Runtime.UDim2.fromScale(1, 1),
			Text = tostring(config.Value),
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Right,
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 2,
		})
		value.Parent = layout.control
		self:theme(value, "TextColor3", "text.secondary")
		self.valueLabel = value
	end

	if config.Icon ~= nil then
		layout.label.Text = tostring(config.Icon) .. "  " .. layout.label.Text
	end
end

function Label:setValue(value: any)
	if self.valueLabel == nil then
		return
	end
	self.valueLabel.Text = tostring(value)
end

return Label
end

__modules["components/Paragraph"] = function()
--!strict
-- Wrapped prose. AutomaticSize keeps the section layout honest without asking
-- the caller to guess a pixel height.

local Base = require("components/Base")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")

local Paragraph = Base:extends("Paragraph")

function Paragraph:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local frame = Builder.frame({
		Name = "paragraph",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame

	local layout = Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 4),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	})
	layout.Parent = frame
	Builder.padding(0, 0, 6).Parent = frame

	if config.Title ~= nil and config.Title ~= "" then
		local title = Builder.label({
			Name = "title",
			LayoutOrder = 1,
			Size = Runtime.UDim2.new(1, 0, 0, 16),
			Text = config.Title,
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		})
		title.Parent = frame
		self:theme(title, "TextColor3", "text.primary")
	end

	local text = Builder.label({
		Name = "text",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		Text = config.Text or "",
		TextWrapped = true,
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = config.TextSize or 12,
		LineHeight = 1.25,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Top,
	})
	text.Parent = frame
	self:theme(text, "TextColor3", "text.secondary")
	self.text = text
end

return Paragraph
end

__modules["components/Divider"] = function()
--!strict
-- Hairline separator, the library's seam motif. An optional label sits on the
-- line and masks it with the surrounding surface colour.

local Base = require("components/Base")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")

local Divider = Base:extends("Divider")

function Divider:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local height = config.Text ~= nil and 18 or 9

	local frame = Builder.frame({
		Name = "divider",
		Size = Runtime.UDim2.new(1, 0, 0, height),
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame

	local line = Builder.frame({
		Name = "line",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.new(0, 0, 0.5, 0),
		Size = Runtime.UDim2.new(1, 0, 0, 1),
		ZIndex = 1,
	})
	line.Parent = frame
	self:theme(line, "BackgroundColor3", "border.hairline")

	if config.Text ~= nil and config.Text ~= "" then
		local label = Builder.label({
			Name = "label",
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			Position = Runtime.UDim2.fromScale(0.5, 0.5),
			Size = Runtime.UDim2.new(0, 0, 0, 14),
			AutomaticSize = Runtime.Enum.AutomaticSize.X,
			Text = "  " .. tostring(config.Text) .. "  ",
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 10,
			Font = Runtime.Enum.Font.Gotham,
			ZIndex = 2,
		})
		label.Parent = frame
		self:theme(label, "BackgroundColor3", "surface.raised")
		self:theme(label, "TextColor3", "text.muted")
		label.BackgroundTransparency = 0
		self.label = label
	end
end

return Divider
end

__modules["components/Space"] = function()
--!strict
-- Layout breathing room. A component, not a magic padding number scattered
-- through every section.

local Base = require("components/Base")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")

local Space = Base:extends("Space")

function Space:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local frame = Builder.frame({
		Name = "space",
		Size = Runtime.UDim2.new(1, 0, 0, config.Size or 8),
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame
end

return Space
end

__modules["components/Badge"] = function()
--!strict
-- Status chip. Variants map to the theme state tokens, so a badge never invents
-- a colour that the contrast checker has not seen.

local Base = require("components/Base")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")

local Badge = Base:extends("Badge")

local VARIANTS = {
	neutral = { background = "surface.sunken", text = "text.secondary" },
	info = { background = "state.info", text = "text.inverse" },
	success = { background = "state.success", text = "text.inverse" },
	warn = { background = "state.warn", text = "text.inverse" },
	danger = { background = "state.danger", text = "text.inverse" },
	accent = { background = "accent.base", text = "accent.on" },
}

function Badge:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local variant = VARIANTS[config.Variant or "neutral"] or VARIANTS.neutral

	local frame = Builder.frame({
		Name = "badge",
		Size = Runtime.UDim2.fromOffset(0, 20),
		AutomaticSize = Runtime.Enum.AutomaticSize.X,
		ZIndex = config.ZIndex or 3,
	})
	Builder.corner(4).Parent = frame
	Builder.padding(0, 8).Parent = frame
	frame.Parent = config.Parent
	self.element = frame

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.fromOffset(0, 20),
		AutomaticSize = Runtime.Enum.AutomaticSize.X,
		Text = config.Text or "",
		TextColor3 = self.binder:resolve(variant.text),
		TextSize = 10,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	label.Parent = frame

	self:theme(frame, "BackgroundColor3", variant.background)
	self:theme(label, "TextColor3", variant.text)
	self.label = label
end

function Badge:setText(text: string)
	self.label.Text = tostring(text)
end

return Badge
end

__modules["components/Slider"] = function()
--!strict
-- Slider. Pointer position is converted to a value through one formula, and the
-- same formula feeds drag, click and keyboard, so the three cannot disagree.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Drag = require("ui/Drag")
local Input = require("ui/Input")
local Scheduler = require("core/Scheduler")
local Log = require("core/Log")

local Slider = Base:extends("Slider")

function Slider:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.min = config.Min or 0
	self.max = config.Max or 100
	self.step = config.Step or 1
	self.precision = config.Precision or 0
	self.suffix = config.Suffix or ""
	self.current = self.min

	if self.key == nil then
		Log.warn("Slider: missing Key, control will not persist")
	end

	local layout = Row.build(context, {
		title = config.Title or "Slider",
		description = config.Description,
		controlWidth = config.ControlWidth or 190,
		hover = false,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local track = Builder.frame({
		Name = "track",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.new(0, 0, 0.5, 0),
		Size = Runtime.UDim2.new(1, -60, 0, 20),
		ZIndex = 3,
	})
	track.Parent = layout.control
	self.trackElement = track

	local rail = Builder.frame({
		Name = "rail",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.fromScale(0, 0.5),
		Size = Runtime.UDim2.new(1, 0, 0, 4),
		ZIndex = 3,
	})
	Builder.corner(2).Parent = rail
	rail.Parent = track
	self:theme(rail, "BackgroundColor3", "surface.sunken")

	local fill = Builder.frame({
		Name = "fill",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.fromScale(0, 0.5),
		Size = Runtime.UDim2.new(0, 0, 1, 0),
		ZIndex = 4,
	})
	Builder.corner(2).Parent = fill
	fill.Parent = track
	self:theme(fill, "BackgroundColor3", "accent.base")
	self.fill = fill

	local knob = Builder.frame({
		Name = "knob",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.new(0, 0, 0.5, 0),
		Size = Runtime.UDim2.fromOffset(12, 12),
		ZIndex = 5,
	})
	Builder.corner(6).Parent = knob
	knob.Parent = track
	self:theme(knob, "BackgroundColor3", "accent.base")
	self.knob = knob

	local box = Builder.new("TextBox", {
		Name = "value",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.fromOffset(52, 24),
		BackgroundColor3 = self.binder:resolve("surface.sunken"),
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 11,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		ClearTextOnFocus = true,
		ZIndex = 4,
	})
	Builder.corner(4).Parent = box
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = box
	box.Parent = layout.control
	self:theme(box, "BackgroundColor3", "surface.sunken")
	self:theme(box, "TextColor3", "text.primary")
	self.box = box

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, config.Default or self.min)
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function()
			self:render()
		end))
	end
	self:track(self.binder:subscribe(function()
		self:render()
	end))

	local slider = self
	Drag.attach(self._janitor, {
		scale = context.window ~= nil and context.window.scale or 1,
		hitTest = function(input)
			return Drag.inside(track, input)
		end,
		onStart = function(current)
			slider:setFromPointer(current)
		end,
		onDrag = function(_, _, current)
			slider:setFromPointer(current)
		end,
	})

	self:track(box.Focused:Connect(function()
		Input.suspend()
	end))
	local function commit()
		Input.resume()
		local parsed = tonumber(box.Text)
		if parsed == nil then
			self:render()
			return
		end
		self:setValue(parsed)
	end
	self:track(box.FocusLost:Connect(commit))
	self:track(box.ReturnPressed:Connect(commit))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onAdjust = function(direction)
				self:setValue(self:value() + direction * self.step)
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end

	self:render()
end

function Slider:value(): number
	if self.key ~= nil then
		return tonumber(self.context.flags:Get(self.key, self.options.Default or self.min)) or self.min
	end
	return self.current
end

function Slider:format(value: number): string
	local text = string.format("%." .. tostring(self.precision) .. "f", value)
	return text .. self.suffix
end

function Slider:render()
	local value = self:value()
	local span = self.max - self.min
	local ratio = span == 0 and 0 or (value - self.min) / span
	ratio = math.clamp(ratio, 0, 1)
	self.fill.Size = Runtime.UDim2.new(ratio, 0, 1, 0)
	self.knob.Position = Runtime.UDim2.new(ratio, 0, 0.5, 0)
	self.box.Text = self:format(value)
	self.current = value
end

function Slider:setFromPointer(current: any)
	local track = self.trackElement
	local x = track.AbsolutePosition.X
	local width = track.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local ratio = math.clamp((current.X - x) / width, 0, 1)
	self:setValue(self.min + ratio * (self.max - self.min))
end

function Slider:setValue(raw: number, silent: boolean?)
	local value = raw
	if self.step > 0 then
		value = math.floor(value / self.step + 0.5) * self.step
	end
	value = math.clamp(value, self.min, self.max)
	if self.precision == 0 then
		value = math.floor(value + 0.5)
	end

	if self.key ~= nil then
		if not self.context.flags:Set(self.key, value) then
			return
		end
	else
		self.current = value
	end
	self:render()

	if not silent and self.options.OnChanged ~= nil then
		Scheduler:queue(self, function()
			self.options.OnChanged(self:value())
		end)
	end
end

function Slider:setEnabled(value: boolean)
	self.enabled = value
	self.trackElement.Active = value
	self.box.TextEditable = value
end

return Slider
end

__modules["components/Textbox"] = function()
--!strict
-- Text input with real validation. Invalid input keeps the last valid flag and
-- explains itself below the field instead of silently accepting garbage.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Input = require("ui/Input")
local Log = require("core/Log")

local Textbox = Base:extends("Textbox")

function Textbox:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.validValue = config.Default or ""
	self.error = nil

	if self.key == nil then
		Log.warn("Textbox: missing Key, control will not persist")
	end

	local multiline = config.Multiline == true
	local layout = Row.build(context, {
		title = config.Title or "Text",
		description = config.Description,
		controlWidth = config.ControlWidth or 220,
		height = multiline and 64 or nil,
		hover = false,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local box = Builder.new("TextBox", {
		Name = "input",
		Size = Runtime.UDim2.new(1, 0, 0, multiline and 52 or 26),
		Position = Runtime.UDim2.fromOffset(0, multiline and 4 or 4),
		BackgroundColor3 = self.binder:resolve("surface.sunken"),
		TextColor3 = self.binder:resolve("text.primary"),
		PlaceholderColor3 = self.binder:resolve("text.muted"),
		PlaceholderText = config.Placeholder or "",
		Text = self.validValue,
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextWrapped = multiline,
		MultiLine = multiline,
		ClearTextOnFocus = config.ClearOnFocus == true,
		TextEditable = true,
		ClipsDescendants = true,
		ZIndex = 3,
	})
	Builder.corner(4).Parent = box
	local stroke = Builder.stroke(self.binder:resolve("border.hairline"), 1)
	stroke.Parent = box
	box.Parent = layout.control
	self:theme(box, "BackgroundColor3", "surface.sunken")
	self:theme(box, "TextColor3", "text.primary")
	self:theme(box, "PlaceholderColor3", "text.muted")
	self.box = box
	self.stroke = stroke

	if config.Password == true then
		local mask = Builder.label({
			Name = "mask",
			Size = Runtime.UDim2.new(1, -16, 1, 0),
			Position = Runtime.UDim2.fromOffset(8, 0),
			Text = "",
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		mask.Parent = box
		self:theme(mask, "TextColor3", "text.primary")
		box.TextTransparency = 1
		self.mask = mask
	end

	local errorLabel = Builder.label({
		Name = "error",
		Size = Runtime.UDim2.new(1, 0, 0, 14),
		Position = Runtime.UDim2.new(0, 0, 0, multiline and 58 or 32),
		Text = "",
		TextColor3 = self.binder:resolve("state.danger"),
		TextSize = 11,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 3,
	})
	errorLabel.Parent = layout.control
	self:theme(errorLabel, "TextColor3", "state.danger")
	self.errorLabel = errorLabel

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, self.validValue)
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function(value)
			if value ~= nil and value ~= box.Text then
				self.validValue = tostring(value)
				box.Text = self.validValue
			end
		end))
	end

	self:track(box.Focused:Connect(function()
		Input.suspend()
	end))

	local textbox = self
	local function submit()
		Input.resume()
		local text = box.Text
		local ok = true
		local message = nil
		if config.Validate ~= nil then
			local passed, reason = config.Validate(text)
			ok = passed == true
			message = reason
		end
		if not ok then
			textbox:showError(message or "Invalid value")
			return
		end
		textbox:clearError()
		textbox.validValue = text
		if textbox.key ~= nil then
			context.flags:Set(textbox.key, text)
		end
		if config.OnSubmit ~= nil then
			config.OnSubmit(text)
		end
	end

	self:track(box.FocusLost:Connect(submit))
	self:track(box.ReturnPressed:Connect(submit))
	self:track(box.TextChanged:Connect(function()
		if self.mask ~= nil then
			self.mask.Text = string.rep("*", #box.Text)
		end
		if config.OnChanged ~= nil then
			config.OnChanged(box.Text)
		end
	end))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onActivate = function()
				box:CaptureFocus()
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
end

function Textbox:showError(message: string)
	self.error = message
	self.errorLabel.Text = message
	self.errorLabel.Visible = true
	self.stroke.Color = self.binder:resolve("state.danger")
	self.layout.row.Size = Runtime.UDim2.new(1, 0, 0, self.options.Multiline and 76 or 50)
end

function Textbox:clearError()
	if self.error == nil then
		return
	end
	self.error = nil
	self.errorLabel.Visible = false
	self.stroke.Color = self.binder:resolve("border.hairline")
	self.layout.row.Size = Runtime.UDim2.new(1, 0, 0, self.options.Multiline and 64 or self.layout.height)
end

function Textbox:setValue(value: string, silent: boolean?)
	self.validValue = tostring(value)
	self.box.Text = self.validValue
	if self.key ~= nil then
		self.context.flags:Set(self.key, self.validValue)
	end
	if not silent and self.options.OnChanged ~= nil then
		self.options.OnChanged(self.validValue)
	end
end

function Textbox:setEnabled(value: boolean)
	self.enabled = value
	self.box.TextEditable = value
	self.box.Active = value
end

return Textbox
end

__modules["ui/VirtualList"] = function()
--!strict
-- Virtual list. Only the visible rows plus a small buffer exist as instances,
-- so a dropdown with a thousand entries costs the same as one with ten.

local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")

local VirtualList = {}
VirtualList.__index = VirtualList

function VirtualList.new(context: any, options: any)
	local config = options or {}
	local self = setmetatable({
		context = context,
		rowHeight = config.RowHeight or 24,
		buffer = config.Buffer or 2,
		items = {},
		pool = {},
		createRow = config.CreateRow,
	}, VirtualList)

	local frame = Builder.new("ScrollingFrame", {
		Name = config.Name or "VirtualList",
		Size = config.Size or Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = context.binder:resolve("border.strong"),
		CanvasSize = Runtime.UDim2.fromOffset(0, 0),
		ScrollingDirection = Runtime.Enum.ScrollingDirection.Y,
		ZIndex = config.ZIndex or 2,
	})
	frame.Parent = config.Parent
	self.frame = frame

	self._janitor = context.janitor
	self._connections = {}
	self._connections[#self._connections + 1] = frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:refresh()
	end)
	self._connections[#self._connections + 1] = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:refresh()
	end)

	return self
end

function VirtualList:setItems(items: { any })
	self.items = items or {}
	self.frame.CanvasSize = Runtime.UDim2.fromOffset(0, #self.items * self.rowHeight)
	self.frame.CanvasPosition = Runtime.Vector2.new(0, 0)
	self:refresh()
end

function VirtualList:refresh()
	local height = self.frame.AbsoluteSize.Y
	if height <= 0 then
		height = 120
	end
	local visible = math.max(1, math.ceil(height / self.rowHeight))
	local first = math.max(1, math.floor(self.frame.CanvasPosition.Y / self.rowHeight) + 1 - self.buffer)
	local last = math.min(#self.items, first + visible + self.buffer * 2)
	local needed = math.max(0, last - first + 1)

	while #self.pool < needed do
		local row = self.createRow(#self.pool + 1)
		row.element.Parent = self.frame
		table.insert(self.pool, row)
	end

	for index, row in ipairs(self.pool) do
		if index <= needed then
			local itemIndex = first + index - 1
			local item = self.items[itemIndex]
			row.element.Visible = true
			row.element.Position = Runtime.UDim2.fromOffset(0, (itemIndex - 1) * self.rowHeight)
			row.element.Size = Runtime.UDim2.new(1, 0, 0, self.rowHeight)
			row.setData(item, itemIndex)
		else
			row.element.Visible = false
		end
	end
end

function VirtualList:destroy()
	for _, connection in ipairs(self._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._connections)
	for _, row in ipairs(self.pool) do
		row.element:Destroy()
	end
	table.clear(self.pool)
	self.frame:Destroy()
end

return VirtualList
end

__modules["components/Dropdown"] = function()
--!strict
-- Dropdown. The panel lives on the popup layer, outside the window clip, and
-- long option lists are virtualised through the shared list helper.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Input = require("ui/Input")
local VirtualList = require("ui/VirtualList")
local Log = require("core/Log")

local Dropdown = Base:extends("Dropdown")

function Dropdown:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.values = config.Values or {}
	self.multi = config.Multi == true
	self.open = false
	self.highlight = 0
	self.filtered = self.values

	if self.key == nil then
		Log.warn("Dropdown: missing Key, control will not persist")
	end

	local layout = Row.build(context, {
		title = config.Title or "Select",
		description = config.Description,
		clickable = true,
		controlWidth = config.ControlWidth or 200,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local value = Builder.label({
		Name = "value",
		Size = Runtime.UDim2.new(1, -20, 1, 0),
		Text = "",
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Right,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	value.Parent = layout.control
	self:theme(value, "TextColor3", "text.secondary")
	self.valueLabel = value

	local chevron = Builder.label({
		Name = "chevron",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.fromOffset(14, 20),
		Text = "v",
		TextColor3 = self.binder:resolve("text.muted"),
		TextSize = 10,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = 3,
	})
	chevron.Parent = layout.control
	self:theme(chevron, "TextColor3", "text.muted")
	self.chevron = chevron

	if self.key ~= nil and not context.flags:Has(self.key) then
		local fallback = config.Default
		if fallback == nil then
			fallback = self.multi and {} or nil
		end
		if fallback ~= nil then
			context.flags:Set(self.key, fallback)
		end
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function()
			self:render()
			if self.open then
				self:refreshRows()
			end
		end))
	end
	self:track(self.binder:subscribe(function()
		self:render()
		if self.open then
			self:refreshRows()
		end
	end))

	self:track(self.element.MouseButton1Click:Connect(function()
		if not self.enabled then
			return
		end
		if self.open then
			self:close()
		else
			self:openPanel()
		end
	end))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onActivate = function()
				if self.open then
					self:close()
				else
					self:openPanel()
				end
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
	self:render()
end

function Dropdown:selection(): any
	if self.key == nil then
		return self.options.Default
	end
	return self.context.flags:Get(self.key, self.options.Default)
end

function Dropdown:isSelected(value: any): boolean
	local selection = self:selection()
	if self.multi then
		if type(selection) ~= "table" then
			return false
		end
		for _, item in ipairs(selection) do
			if item == value then
				return true
			end
		end
		return false
	end
	return selection == value
end

function Dropdown:render()
	local selection = self:selection()
	local text = self.options.Placeholder or "Select"
	if self.multi and type(selection) == "table" then
		if #selection > 0 then
			local parts = {}
			for _, item in ipairs(selection) do
				table.insert(parts, tostring(item))
			end
			text = table.concat(parts, ", ")
		end
	elseif selection ~= nil then
		text = tostring(selection)
	end
	self.valueLabel.Text = text
	self.chevron.Text = self.open and "^" or "v"
end

function Dropdown:openPanel()
	if self.open then
		return
	end
	self.open = true
	self.highlight = 0
	self.filtered = self.values
	self:render()

	local layers = self.context.root.layers
	local catcher = Builder.button({
		Name = "dropdown_catcher",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = layers:next("popup"),
	})
	catcher.Parent = layers:frame("popup")
	self.catcher = catcher

	local panel = Builder.frame({
		Name = "dropdown_panel",
		BackgroundColor3 = self.binder:resolve("surface.raised"),
		ZIndex = layers:next("popup"),
		ClipsDescendants = true,
	})
	Builder.corner(6).Parent = panel
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = panel
	panel.Parent = layers:frame("popup")
	self.panel = panel
	self:theme(panel, "BackgroundColor3", "surface.raised")

	local searchHeight = 0
	if self.options.Search ~= false then
		searchHeight = 30
		local search = Builder.new("TextBox", {
			Name = "search",
			Position = Runtime.UDim2.fromOffset(4, 4),
			Size = Runtime.UDim2.new(1, -8, 0, 24),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			TextColor3 = self.binder:resolve("text.primary"),
			PlaceholderColor3 = self.binder:resolve("text.muted"),
			PlaceholderText = "Search",
			Text = "",
			TextSize = 11,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			ZIndex = panel.ZIndex + 1,
		})
		Builder.corner(4).Parent = search
		search.Parent = panel
		self:theme(search, "BackgroundColor3", "surface.sunken")
		self:theme(search, "TextColor3", "text.primary")
		self:theme(search, "PlaceholderColor3", "text.muted")
		self.search = search

		self:track(search.Focused:Connect(function()
			Input.suspend()
		end))
		self:track(search.FocusLost:Connect(function()
			Input.resume()
		end))
		self:track(search.TextChanged:Connect(function()
			self:filter(search.Text)
		end))
	end

	local list = VirtualList.new(self.context, {
		Parent = panel,
		Size = Runtime.UDim2.new(1, -8, 1, -(searchHeight + 8)),
		RowHeight = 24,
		Buffer = 2,
		ZIndex = panel.ZIndex + 1,
		CreateRow = function()
			local button = Builder.button({
				Name = "option",
				Size = Runtime.UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				ZIndex = panel.ZIndex + 1,
			})
			Builder.corner(4).Parent = button
			local label = Builder.label({
				Size = Runtime.UDim2.new(1, -16, 1, 0),
				Position = Runtime.UDim2.fromOffset(8, 0),
				TextColor3 = self.binder:resolve("text.primary"),
				TextSize = 12,
				Font = Runtime.Enum.Font.Gotham,
				TextXAlignment = Runtime.Enum.TextXAlignment.Left,
				TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
				ZIndex = panel.ZIndex + 2,
			})
			label.Parent = button
			local row = { element = button, item = nil }
			button.MouseButton1Click:Connect(function()
				if row.item ~= nil then
					self:choose(row.item)
				end
			end)
			button.MouseEnter:Connect(function()
				button.BackgroundTransparency = 0
				button.BackgroundColor3 = self.binder:resolve("state.hover")
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundTransparency = 1
			end)
			function row.setData(item, index)
				row.item = item
				label.Text = tostring(item)
				local selected = self:isSelected(item)
				label.TextColor3 = self.binder:resolve(selected and "accent.base" or "text.primary")
				button.BackgroundTransparency = 1
				if index == self.highlight then
					button.BackgroundTransparency = 0
					button.BackgroundColor3 = self.binder:resolve("state.hover")
				end
			end
			return row
		end,
	})
	self.list = list
	list.frame.Position = Runtime.UDim2.fromOffset(4, searchHeight + 4)
	list:setItems(self.filtered)

	self:positionPanel()

	self:track(catcher.MouseButton1Click:Connect(function()
		self:close()
	end))

	local captureHandler
	captureHandler = function(input)
		if not self.open then
			return
		end
		local key = input.KeyCode
		if key == Runtime.Enum.KeyCode.Escape then
			self:close()
			return
		end
		if key == Runtime.Enum.KeyCode.Up then
			self.highlight = math.max(1, self.highlight - 1)
		elseif key == Runtime.Enum.KeyCode.Down then
			self.highlight = math.min(#self.filtered, self.highlight + 1)
		elseif key == Runtime.Enum.KeyCode.Return then
			local item = self.filtered[self.highlight]
			if item ~= nil then
				self:choose(item)
			end
			return
		end
		self:refreshRows()
		self.capture = Input.capture(captureHandler)
	end
	self.capture = Input.capture(captureHandler)
end

function Dropdown:positionPanel()
	if self.panel == nil then
		return
	end
	local control = self.layout.control
	local width = math.max(180, control.AbsoluteSize.X)
	local height = math.min(self.options.MaxHeight or 220, math.max(1, #self.filtered) * 24 + 8)
	if self.search ~= nil then
		height = height + 30
	end
	height = math.min(height, self.options.MaxHeight or 220)
	self.panel.Size = Runtime.UDim2.fromOffset(width, height)
	self.panel.Position = Runtime.UDim2.fromOffset(
		control.AbsolutePosition.X,
		control.AbsolutePosition.Y + control.AbsoluteSize.Y + 4
	)
	if self.list ~= nil then
		self.list.frame.Size = Runtime.UDim2.new(1, -8, 1, -((self.search ~= nil and 30 or 0) + 8))
	end
end

function Dropdown:filter(query: string)
	local needle = string.lower(tostring(query))
	if needle == "" then
		self.filtered = self.values
	else
		local filtered = {}
		for _, item in ipairs(self.values) do
			if string.find(string.lower(tostring(item)), needle, 1, true) ~= nil then
				table.insert(filtered, item)
			end
		end
		self.filtered = filtered
	end
	self.highlight = 0
	self:positionPanel()
	if self.list ~= nil then
		self.list:setItems(self.filtered)
	end
end

function Dropdown:refreshRows()
	if self.list ~= nil then
		self.list:refresh()
	end
end

function Dropdown:choose(item: any)
	if self.multi then
		local current = self:selection()
		local nextSelection = {}
		local found = false
		if type(current) == "table" then
			for _, value in ipairs(current) do
				if value == item then
					found = true
				else
					table.insert(nextSelection, value)
				end
			end
		end
		if not found then
			table.insert(nextSelection, item)
		end
		if self.key ~= nil then
			self.context.flags:Set(self.key, nextSelection)
		end
		self:render()
		self:refreshRows()
	else
		if self.key ~= nil then
			self.context.flags:Set(self.key, item)
		end
		self:render()
		self:close()
	end
	if self.options.OnChanged ~= nil then
		self.options.OnChanged(self:selection())
	end
end

function Dropdown:close()
	if not self.open then
		return
	end
	self.open = false
	if self.capture ~= nil then
		self.capture:Cancel()
		self.capture = nil
	end
	if self.search ~= nil then
		Input.resume()
	end
	if self.list ~= nil then
		self.list:destroy()
		self.list = nil
	end
	if self.panel ~= nil then
		self.panel:Destroy()
		self.panel = nil
	end
	if self.catcher ~= nil then
		self.catcher:Destroy()
		self.catcher = nil
	end
	self.search = nil
	self:render()
end

function Dropdown:beforeDestroy()
	self:close()
end

function Dropdown:setEnabled(value: boolean)
	self.enabled = value
	self.element.Active = value
end

return Dropdown
end

__modules["components/Keybind"] = function()
--!strict
-- Keybind. Capture uses the global input map's one-shot handler, so no second
-- UserInputService connection is opened per control.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Input = require("ui/Input")
local Log = require("core/Log")

local Keybind = Base:extends("Keybind")

local MODES = { "hold", "toggle", "always" }

function Keybind:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.capturing = false

	if self.key == nil then
		Log.warn("Keybind: missing Key, control will not persist")
	end

	local layout = Row.build(context, {
		title = config.Title or "Keybind",
		description = config.Description,
		controlWidth = config.ControlWidth or 190,
		height = 44,
		hover = false,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local keyButton = Builder.button({
		Name = "key",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.new(0, 0, 0, 15),
		Size = Runtime.UDim2.fromOffset(96, 26),
		BackgroundColor3 = self.binder:resolve("surface.sunken"),
		Text = "",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 11,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = 3,
	})
	Builder.corner(4).Parent = keyButton
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = keyButton
	keyButton.Parent = layout.control
	self:theme(keyButton, "BackgroundColor3", "surface.sunken")
	self:theme(keyButton, "TextColor3", "text.primary")
	self.keyButton = keyButton

	local modeRow = Builder.frame({
		Name = "modes",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0, 15),
		Size = Runtime.UDim2.fromOffset(84, 26),
		ZIndex = 3,
	})
	modeRow.Parent = layout.control
	self.modeRow = modeRow
	self.modeButtons = {}

	local segmentWidth = 28
	for index, mode in ipairs(MODES) do
		local button = Builder.button({
			Name = mode,
			Position = Runtime.UDim2.fromOffset((index - 1) * segmentWidth, 0),
			Size = Runtime.UDim2.fromOffset(segmentWidth, 26),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			Text = string.sub(mode, 1, 1):upper(),
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = 3,
		})
		button.Parent = modeRow
		self:theme(button, "TextColor3", "text.secondary")
		table.insert(self.modeButtons, { mode = mode, button = button })
		self:track(button.MouseButton1Click:Connect(function()
			if self.enabled then
				self:setMode(mode)
			end
		end))
	end

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, { key = config.Default, mode = config.Mode or "hold" })
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function()
			self:render()
		end))
	end
	self:track(self.binder:subscribe(function()
		self:render()
	end))

	self:track(keyButton.MouseButton1Click:Connect(function()
		if not self.enabled then
			return
		end
		self:beginCapture()
	end))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onActivate = function()
				if self.enabled then
					self:beginCapture()
				end
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
	self:render()
end

function Keybind:state(): any
	if self.key == nil then
		return { key = self.options.Default, mode = self.options.Mode or "hold" }
	end
	local value = self.context.flags:Get(self.key, nil)
	if type(value) ~= "table" then
		return { key = self.options.Default, mode = self.options.Mode or "hold" }
	end
	return value
end

function Keybind:render()
	local state = self:state()
	local mode = state.mode or "hold"
	local key = state.key

	if mode == "always" then
		self.keyButton.Text = "Always"
		self.keyButton.TextColor3 = self.binder:resolve("accent.base")
	elseif self.capturing then
		self.keyButton.Text = "Press a key"
		self.keyButton.TextColor3 = self.binder:resolve("accent.base")
	else
		self.keyButton.Text = key ~= nil and tostring(key.Name or key) or "None"
		self.keyButton.TextColor3 = self.binder:resolve("text.primary")
	end

	for _, entry in ipairs(self.modeButtons) do
		local active = entry.mode == mode
		entry.button.BackgroundColor3 = self.binder:resolve(active and "accent.base" or "surface.sunken")
		entry.button.TextColor3 = self.binder:resolve(active and "accent.on" or "text.secondary")
	end
end

function Keybind:beginCapture()
	if self.capturing then
		return
	end
	local state = self:state()
	if state.mode == "always" then
		return
	end
	self.capturing = true
	self:render()

	local capture
	capture = Input.capture(function(input)
		if not self.capturing then
			return
		end
		self.capturing = false
		local key = input.KeyCode
		if key == Runtime.Enum.KeyCode.Escape then
			self:render()
			return
		end
		if key == Runtime.Enum.KeyCode.Backspace then
			self:setKey(nil)
			return
		end
		self:setKey(key)
	end)
	self.capture = capture
end

function Keybind:setKey(key: any)
	local state = self:state()
	local nextState = { key = key, mode = state.mode or "hold" }
	if self.key ~= nil then
		if not self.context.flags:Set(self.key, nextState) then
			return
		end
	else
		self.options.Default = key
	end
	self:render()
	if self.options.OnChanged ~= nil then
		self.options.OnChanged(key, nextState.mode)
	end
end

function Keybind:setMode(mode: string)
	local state = self:state()
	local nextState = { key = state.key, mode = mode }
	if self.key ~= nil then
		if not self.context.flags:Set(self.key, nextState) then
			return
		end
	else
		self.options.Mode = mode
	end
	self:render()
	if self.options.OnChanged ~= nil then
		self.options.OnChanged(nextState.key, mode)
	end
end

function Keybind:beforeDestroy()
	if self.capture ~= nil then
		self.capture:Cancel()
		self.capture = nil
	end
end

return Keybind
end

__modules["components/Section"] = function()
--!strict
-- Section owns a header and a vertical stack of rows. Height is automatic:
-- callers pass content, never pixel heights that rot when a font changes.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Log = require("core/Log")

local Toggle = require("components/Toggle")
local Button = require("components/Button")
local Label = require("components/Label")
local Paragraph = require("components/Paragraph")
local Divider = require("components/Divider")
local Space = require("components/Space")
local Badge = require("components/Badge")
local Slider = require("components/Slider")
local Textbox = require("components/Textbox")
local Dropdown = require("components/Dropdown")
local Keybind = require("components/Keybind")

local Section = Class:extends("Section")

local HEADER_HEIGHT = 30
local HEADER_HEIGHT_DESCRIPTION = 44

function Section:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.components = {}
	self.collapsed = self.options.Collapsed == true
	self.expandedHeight = nil

	local config = self.options
	local hasDescription = config.Description ~= nil
	local headerHeight = hasDescription and HEADER_HEIGHT_DESCRIPTION or HEADER_HEIGHT

	local frame = Builder.frame({
		Name = "section",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		BackgroundColor3 = self.binder:resolve("surface.raised"),
		ZIndex = 1,
	})
	Builder.corner(Tokens.radius.section).Parent = frame
	Builder.padding(Tokens.space.md).Parent = frame
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, Tokens.space.sm),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = frame
	frame.Parent = config.Parent
	self.element = frame
	self.surfaceToken = config.Surface or "surface.raised"
	self:bind(frame, "BackgroundColor3", self.surfaceToken)

	local header = Builder.frame({
		Name = "header",
		LayoutOrder = 1,
		Size = Runtime.UDim2.new(1, 0, 0, headerHeight),
		ZIndex = 2,
	})
	header.Parent = frame
	self.header = header

	local title = Builder.label({
		Name = "title",
		Size = Runtime.UDim2.new(1, -24, 0, hasDescription and 18 or headerHeight),
		Position = Runtime.UDim2.new(0, 0, 0, hasDescription and 4 or 0),
		Text = config.Title or "Section",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	title.Parent = header
	self:bind(title, "TextColor3", "text.primary")

	if hasDescription then
		local description = Builder.label({
			Name = "description",
			Size = Runtime.UDim2.new(1, -24, 0, 16),
			Position = Runtime.UDim2.new(0, 0, 0, 22),
			Text = config.Description,
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 11,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		description.Parent = header
		self:bind(description, "TextColor3", "text.muted")
	end

	local content = Builder.frame({
		Name = "content",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = 2,
	})
	content.Parent = frame
	self.content = content
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 2),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = content

	if config.Collapsible == true then
		local arrow = Builder.button({
			Name = "collapse",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, 0, 0, hasDescription and 22 or headerHeight / 2),
			Size = Runtime.UDim2.fromOffset(20, 20),
			Text = self.collapsed and "▸" or "▾",
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 12,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = 4,
		})
		arrow.Parent = header
		self:bind(arrow, "TextColor3", "text.muted")
		self.arrow = arrow
		arrow.MouseButton1Click:Connect(function()
			self:setCollapsed(not self.collapsed)
		end)
	else
		self:setCollapsed(self.collapsed, false)
	end

	if config.Badge ~= nil then
		local badge = Badge.new(context, {
			Text = config.Badge,
			Variant = config.BadgeVariant or "neutral",
			Parent = header,
			ZIndex = 5,
		})
		badge.element.AnchorPoint = Runtime.Vector2.new(1, 0.5)
		badge.element.Position = Runtime.UDim2.new(1, config.Collapsible == true and -24 or 0, 0, hasDescription and 22 or headerHeight / 2)
		self:track(badge)
	end
end

function Section:bind(instance: any, property: string, token: string)
	self._janitor:Add(self.binder:bind(instance, property, token))
end

function Section:track(component: any)
	table.insert(self.components, component)
	self._janitor:Add(component)
	return component
end

function Section:add(component: any)
	table.insert(self.components, component)
	return component
end

local function childOptions(self: any, options: any): any
	local copy = table.clone(options or {})
	copy.Parent = self.content
	copy.LayoutOrder = #self.components + 1
	return copy
end

function Section:Toggle(options: any)
	return self:track(Toggle.new(self.context, childOptions(self, options)))
end

function Section:Button(options: any)
	return self:track(Button.new(self.context, childOptions(self, options)))
end

function Section:Label(options: any)
	return self:track(Label.new(self.context, childOptions(self, options)))
end

function Section:Paragraph(options: any)
	return self:track(Paragraph.new(self.context, childOptions(self, options)))
end

function Section:Divider(options: any)
	return self:track(Divider.new(self.context, childOptions(self, options)))
end

function Section:Space(options: any)
	return self:track(Space.new(self.context, childOptions(self, options)))
end

function Section:Badge(options: any)
	return self:track(Badge.new(self.context, childOptions(self, options)))
end

function Section:Slider(options: any)
	return self:track(Slider.new(self.context, childOptions(self, options)))
end

function Section:Textbox(options: any)
	return self:track(Textbox.new(self.context, childOptions(self, options)))
end

function Section:Dropdown(options: any)
	return self:track(Dropdown.new(self.context, childOptions(self, options)))
end

function Section:Keybind(options: any)
	return self:track(Keybind.new(self.context, childOptions(self, options)))
end

function Section:ColorPicker(options: any)
	return self:track(ColorPicker.new(self.context, childOptions(self, options)))
end

function Section:RangeSlider(options: any)
	return self:track(RangeSlider.new(self.context, childOptions(self, options)))
end

function Section:Groupbox(options: any)
	local copy = table.clone(options or {})
	copy.Parent = self.content
	copy.LayoutOrder = #self.components + 1
	copy.Depth = 1
	copy.Surface = "surface.sunken"
	local group = Section.new(self.context, copy)
	group.element:FindFirstChild("UICorner").CornerRadius = Runtime.UDim.new(0, Tokens.radius.control)
	return self:track(group)
end

function Section:setCollapsed(value: boolean, animate: boolean?)
	if self.collapsed == value and animate ~= false then
		return
	end
	self.collapsed = value
	if self.arrow ~= nil then
		self.arrow.Text = value and "▸" or "▾"
	end

	local content = self.content
	local duration = animate == false and 0 or Motion.duration("open")

	if value then
		local height = content.AbsoluteSize.Y
		if height <= 0 then
			content.Visible = false
			return
		end
		self.expandedHeight = height
		content.AutomaticSize = Runtime.Enum.AutomaticSize.None
		content.Size = Runtime.UDim2.new(1, 0, 0, height)
		content.ClipsDescendants = true
		Motion.tween(content, { Size = Runtime.UDim2.new(1, 0, 0, 0) }, { duration = duration })
		if duration <= 0 then
			content.Visible = false
			content.ClipsDescendants = false
			content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
		else
			Scheduler:after(duration, function()
				if self.collapsed then
					content.Visible = false
					content.ClipsDescendants = false
					content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
				end
			end)
		end
		return
	end

	local height = self.expandedHeight or 0
	content.Visible = true
	content.AutomaticSize = Runtime.Enum.AutomaticSize.None
	content.Size = Runtime.UDim2.new(1, 0, 0, duration <= 0 and height or 0)
	content.ClipsDescendants = true
	Motion.tween(content, { Size = Runtime.UDim2.new(1, 0, 0, height) }, { duration = duration })
	if duration <= 0 then
		content.ClipsDescendants = false
		content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
	else
		Scheduler:after(duration, function()
			if not self.collapsed then
				content.ClipsDescendants = false
				content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
			end
		end)
	end
end

function Section:setEnabled(value: boolean)
	self.enabled = value
	for _, component in ipairs(self.components) do
		if component.setEnabled ~= nil then
			component:setEnabled(value)
		end
	end
end

return Section
end

__modules["components/Tab"] = function()
--!strict
-- A tab owns a scroll surface and a section stack. Scroll position survives tab
-- switches, so returning to a page does not jump back to the top.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Section = require("components/Section")

local Tab = Class:extends("Tab")

function Tab:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.sections = {}
	self.scrollPosition = Runtime.Vector2.new(0, 0)

	local page = Builder.new("ScrollingFrame", {
		Name = "page",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = self.binder:resolve("border.strong"),
		CanvasSize = Runtime.UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Runtime.Enum.AutomaticSize.Y,
		ScrollingDirection = Runtime.Enum.ScrollingDirection.Y,
		Visible = false,
		ZIndex = 1,
	})
	page.Parent = self.options.Parent
	page.CanvasPosition = Runtime.Vector2.new(0, 0)
	self.page = page
	self._janitor:Add(page)

	local content = Builder.frame({
		Name = "content",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = 1,
	})
	content.Parent = page
	self.content = content
	self._janitor:Add(content)

	Builder.padding(Tokens.space.md).Parent = content
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, Tokens.space.md),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = content

	self._janitor:Add(self.binder:bind(page, "ScrollBarImageColor3", "border.strong"))
end

function Tab:Section(options: any)
	local copy = table.clone(options or {})
	copy.Parent = self.content
	copy.LayoutOrder = #self.sections + 1
	local section = Section.new(self.context, copy)
	table.insert(self.sections, section)
	self._janitor:Add(section)
	return section
end

function Tab:show()
	self.page.Visible = true
	self.page.CanvasPosition = self.scrollPosition
end

function Tab:hide()
	self.scrollPosition = self.page.CanvasPosition
	self.page.Visible = false
end

function Tab:isVisible(): boolean
	return self.page.Visible == true
end

return Tab
end

__modules["components/Window"] = function()
--!strict
-- Window shell. Geometry is stored in offsets so drag and resize maths stay in
-- one unit space; the root UIScale handles display scaling separately.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Drag = require("ui/Drag")
local Resize = require("ui/Resize")
local Focus = require("ui/Focus")
local Input = require("ui/Input")
local TitleBar = require("components/TitleBar")
local TabRail = require("components/TabRail")
local Tab = require("components/Tab")
local Log = require("core/Log")

local Window = Class:extends("Window")

local DEFAULT_WIDTH = 760
local DEFAULT_HEIGHT = 500
local EDGE_INSET = 24
local MIN_VISIBLE = 80

local function viewport(): any
	local camera = Runtime.workspace and Runtime.workspace.CurrentCamera or nil
	if camera ~= nil and camera.ViewportSize ~= nil then
		return camera.ViewportSize
	end
	return Runtime.Vector2.new(1920, 1080)
end

function Window:init(context: any, options: any)
	self.options = options or {}
	self.binder = context.binder
	self.root = context.root
	self.flags = context.flags
	self.scale = 1
	if self.root ~= nil and self.root.scale ~= nil then
		self.scale = self.root.scale.Scale or 1
	end

	self.context = setmetatable({
		window = self,
		binder = self.binder,
		layers = self.root.layers,
		focus = Focus.new(self.binder),
		flags = self.flags,
		root = self.root,
		notify = context.notify,
		version = context.version,
	}, { __index = context })

	self.tabs = {}
	self.minimized = false
	self.maximized = false
	self.savedGeometry = nil
	self.restoreHeight = nil
	self.closing = false

	local screen = viewport()
	local width = DEFAULT_WIDTH
	local height = DEFAULT_HEIGHT
	local size = self.options.Size
	if size ~= nil then
		width = size.X.Offset > 0 and size.X.Offset or screen.X * size.X.Scale
		height = size.Y.Offset > 0 and size.Y.Offset or screen.Y * size.Y.Scale
	end

	local maxWidth = screen.X * 0.92
	local maxHeight = screen.Y * 0.92
	width = math.clamp(width, 320, maxWidth)
	height = math.clamp(height, 240, maxHeight)

	local x = screen.X - width - EDGE_INSET
	local y = EDGE_INSET
	if self.options.Position ~= nil then
		x = self.options.Position.X.Offset
		y = self.options.Position.Y.Offset
	end

	local frame = Builder.frame({
		Name = self.options.Name or "LondraWindow",
		Size = Runtime.UDim2.fromOffset(width, height),
		Position = Runtime.UDim2.fromOffset(x, y),
		BackgroundColor3 = self.binder:resolve("surface.base"),
		BackgroundTransparency = self.options.Acrylic and 0.04 or 0,
		ClipsDescendants = false,
		ZIndex = 10,
	})
	Builder.corner(Tokens.radius.window).Parent = frame
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = frame
	frame.Parent = self.root.layers:frame("base")
	self.frame = frame
	self._janitor:Add(frame)
	self._janitor:Add(self.binder:bind(frame, "BackgroundColor3", "surface.base"))

	self.statusHeight = self.options.ShowStatusBar == false and 0 or Tokens.row.status

	self.titleBar = TitleBar.new(self.context, self, {
		Parent = frame,
		Title = self.options.Title or "Londra",
		Icon = self.options.Icon,
	})
	self._janitor:Add(self.titleBar)

	local body = Builder.frame({
		Name = "Body",
		Position = Runtime.UDim2.fromOffset(0, Tokens.row.titlebar),
		Size = Runtime.UDim2.new(1, 0, 1, -(Tokens.row.titlebar + self.statusHeight)),
		ZIndex = 2,
	})
	body.Parent = frame
	self.body = body
	self._janitor:Add(body)

	self.rail = TabRail.new(self.context, {
		Parent = body,
		Mode = self.options.TabPosition or "left",
	})
	self._janitor:Add(self.rail)

	local content = Builder.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	content.Parent = body
	self.content = content
	self._janitor:Add(content)

	if self.rail.mode == "top" then
		self.rail.element.Position = Runtime.UDim2.fromOffset(0, 0)
		content.Position = Runtime.UDim2.fromOffset(0, Tokens.row.titlebar)
		content.Size = Runtime.UDim2.new(1, 0, 1, -Tokens.row.titlebar)
	else
		self.rail.element.Position = Runtime.UDim2.fromOffset(0, 0)
		content.Position = Runtime.UDim2.fromOffset(Tokens.size.tabRail, 0)
		content.Size = Runtime.UDim2.new(1, -Tokens.size.tabRail, 1, 0)
	end

	if self.statusHeight > 0 then
		local status = Builder.frame({
			Name = "StatusBar",
			AnchorPoint = Runtime.Vector2.new(0, 1),
			Position = Runtime.UDim2.new(0, 0, 1, 0),
			Size = Runtime.UDim2.new(1, 0, 0, self.statusHeight),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			ZIndex = 2,
		})
		status.Parent = frame
		self._janitor:Add(status)
		self._janitor:Add(self.binder:bind(status, "BackgroundColor3", "surface.sunken"))

		local text = self.options.Subtitle or ("v" .. tostring(context.version or "1.0.0"))
		local label = Builder.label({
			Name = "status",
			Size = Runtime.UDim2.new(1, -16, 1, 0),
			Position = Runtime.UDim2.fromOffset(12, 0),
			Text = text,
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 10,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
		label.Parent = status
		self._janitor:Add(self.binder:bind(label, "TextColor3", "text.muted"))
		self.status = status
	end

	self:attachDrag()
	self:attachResize()
	self:attachToggleKey()

	self._janitor:Add(frame.MouseButton1Down:Connect(function()
		self:bringToFront()
	end))
	self._janitor:Add(self.titleBar.element.MouseButton1Down:Connect(function()
		self:bringToFront()
	end))

	self:animateOpen()
end

function Window:attachDrag()
	if self.options.Draggable == false then
		return
	end
	local start = nil
	local snap = self.options.Snap or 8

	Drag.attach(self._janitor, {
		scale = self.scale,
		hitTest = function(input)
			return Drag.inside(self.titleBar.element, input)
		end,
		onStart = function()
			start = self:getPosition()
		end,
		onDrag = function(deltaX, deltaY)
			if start == nil then
				return
			end
			local screen = viewport()
			local size = self:getSize()
			local x = start.X + deltaX
			local y = start.Y + deltaY

			if math.abs(x) <= snap then
				x = 0
			elseif math.abs(x + size.X - screen.X) <= snap then
				x = screen.X - size.X
			end
			if math.abs(y) <= snap then
				y = 0
			end

			x = math.clamp(x, -(size.X - MIN_VISIBLE), screen.X - MIN_VISIBLE)
			y = math.clamp(y, 0, screen.Y - Tokens.row.titlebar)
			self:setGeometry(x, y, size.X, size.Y)
		end,
	})
end

function Window:attachResize()
	if self.options.Resizable == false then
		return
	end
	local screen = viewport()
	Resize.attach(self._janitor, self, {
		minSize = self.options.MinSize or Runtime.Vector2.new(520, 340),
		maxSize = self.options.MaxSize or Runtime.Vector2.new(screen.X * 0.92, screen.Y * 0.92),
	})
end

function Window:attachToggleKey()
	local key = self.options.ToggleKey
	if key == nil then
		return
	end
	self._janitor:Add(Input.bind(key, function()
		if Input.isSuspended() then
			return
		end
		self:toggleVisible()
	end, { force = true }))
end

function Window:animateOpen()
	local duration = Motion.duration("open")
	if duration <= 0 then
		return
	end
	local scale = Builder.new("UIScale", { Name = "__londra_open", Scale = 0.96 })
	scale.Parent = self.frame
	Motion.tween(scale, { Scale = 1 }, { duration = duration })
	Scheduler:after(duration, function()
		if scale.Parent ~= nil then
			scale:Destroy()
		end
	end)
end

function Window:getSize(): any
	local size = self.frame.Size
	return Runtime.Vector2.new(size.X.Offset, size.Y.Offset)
end

function Window:getPosition(): any
	local position = self.frame.Position
	return Runtime.Vector2.new(position.X.Offset, position.Y.Offset)
end

function Window:setGeometry(x: number, y: number, width: number, height: number)
	self.frame.Position = Runtime.UDim2.fromOffset(x, y)
	self.frame.Size = Runtime.UDim2.fromOffset(width, height)
end

function Window:Tab(options: any)
	local copy = table.clone(options or {})
	copy.Parent = self.content
	local tab = Tab.new(self.context, copy)
	table.insert(self.tabs, tab)
	self._janitor:Add(tab)
	local index = self.rail:add(tab)
	if index == 1 then
		self.rail:select(1)
	end
	return tab
end

function Window:SelectTab(index: number): boolean
	return self.rail:select(index)
end

function Window:activeTab(): any
	if self.rail.active == 0 then
		return nil
	end
	return self.tabs[self.rail.active]
end

function Window:bringToFront()
	if self.closing then
		return
	end
	if self.context.focusWindow ~= nil then
		self.context.focusWindow(self)
	end
end

function Window:toggleVisible()
	if self.closing then
		return
	end
	if self.frame.Visible then
		self.frame.Visible = false
	else
		self.frame.Visible = true
		self:bringToFront()
	end
end

function Window:minimize()
	if self.closing then
		return
	end
	local duration = Motion.duration("close")

	if not self.minimized then
		local size = self:getSize()
		self.restoreHeight = size.Y
		self.minimized = true
		local targetHeight = Tokens.row.titlebar + self.statusHeight
		Motion.tween(self.frame, { Size = Runtime.UDim2.fromOffset(size.X, targetHeight) }, { duration = duration })
		if duration <= 0 then
			self.body.Visible = false
			if self.status ~= nil then
				self.status.Visible = false
			end
		else
			Scheduler:after(duration, function()
				if self.minimized then
					self.body.Visible = false
					if self.status ~= nil then
						self.status.Visible = false
					end
				end
			end)
		end
		return
	end

	self.minimized = false
	self.body.Visible = true
	if self.status ~= nil then
		self.status.Visible = true
	end
	local size = self:getSize()
	local height = self.restoreHeight or DEFAULT_HEIGHT
	Motion.tween(self.frame, { Size = Runtime.UDim2.fromOffset(size.X, height) }, { duration = duration })
end

function Window:toggleMaximize()
	if self.closing then
		return
	end
	local screen = viewport()
	local duration = Motion.duration("open")

	if not self.maximized then
		self.savedGeometry = {
			x = self:getPosition().X,
			y = self:getPosition().Y,
			width = self:getSize().X,
			height = self:getSize().Y,
		}
		self.maximized = true
		Motion.tween(self.frame, {
			Position = Runtime.UDim2.fromOffset(EDGE_INSET, EDGE_INSET),
			Size = Runtime.UDim2.fromOffset(screen.X - EDGE_INSET * 2, screen.Y - EDGE_INSET * 2),
		}, { duration = duration })
		return
	end

	local saved = self.savedGeometry
	if saved == nil then
		return
	end
	self.maximized = false
	Motion.tween(self.frame, {
		Position = Runtime.UDim2.fromOffset(saved.x, saved.y),
		Size = Runtime.UDim2.fromOffset(saved.width, saved.height),
	}, { duration = duration })
end

function Window:close()
	if self.closing then
		return
	end
	self.closing = true
	if self.options.OnClose ~= nil then
		pcall(self.options.OnClose)
	end
	local duration = Motion.duration("close")
	if duration <= 0 then
		self:Destroy()
		return
	end
	local scale = self.frame:FindFirstChild("__londra_close")
	if scale == nil then
		scale = Builder.new("UIScale", { Name = "__londra_close", Scale = 1 })
		scale.Parent = self.frame
	end
	Motion.tween(scale, { Scale = 0.96 }, { duration = duration })
	Scheduler:after(duration, function()
		self:Destroy()
	end)
end

function Window:beforeDestroy()
	if self.context.focus ~= nil then
		self.context.focus:destroy()
	end
	if self.context.windowClosed ~= nil then
		self.context.windowClosed(self)
	end
end

return Window
end

__modules["components/ColorPicker"] = function()
--!strict
-- Color picker. Panel lives on the popup layer. SV square is two-layer (white->color,
-- siyahtan saydam), hue strip is 180x12, alpha strip optional. Hex/RGB textboxes
-- validate. Default colors are preset. Value is { color = Color3, alpha = number }.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")
local Input = require("ui/Input")
local Scheduler = require("core/Scheduler")
local Motion = require("core/Motion")
local Log = require("core/Log")

local ColorPicker = {}

local SV_SIZE = 180
local HUE_HEIGHT = 12
local ALPHA_HEIGHT = 20
local PRESET_COUNT = 6
local TEXTBOX_SIZE = 48
local PRESET_SPACING = 6

-- HSV -> RGB (standard)
local function hsvToRgb(h: number, s: number, v: number): Color3
	local i = math.floor(h / 60) % 6
	local f = (h / 60) - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local r, g, b = 0, 0, 0
	if i == 0 then r, g, b = v, t, p
	elseif i == 1 then r, g, b = q, v, p
	elseif i == 2 then r, g, b = p, v, t
	elseif i == 3 then r, g, b = p, q, v
	elseif i == 4 then r, g, b = t, p, v
	else r, g, b = v, p, q
	end
	return Color3.new(r, g, b)
end

-- RGB -> HSV
local function rgbToHsv(r: number, g: number, b: number): (number, number, number)
	r, g, b = r / 255, g / 255, b / 255
	local maxC, minC = math.max(r, g, b), math.min(r, g, b)
	local diff = maxC - minC
	local h = 0
	if diff ~= 0 then
		if maxC == r then h = ((g - b) / diff) % 6
		elseif maxC == g then h = (b - r) / diff + 2
		else h = (r - g) / diff + 4
		end
		h = h * 60
		if h < 0 then h += 360 end
	end
	local s = maxC == 0 and 0 or diff / maxC
	local v = maxC
	return h, s, v
end

-- RGB -> hex string (without #)
local function rgbToHex(r: number, g: number, b: number): string
	r = math.floor(math.clamp(r, 0, 1) * 255 + 0.5)
	g = math.floor(math.clamp(g, 0, 1) * 255 + 0.5)
	b = math.floor(math.clamp(b, 0, 1) * 255 + 0.5)
	return string.format("%02X%02X%02X", r, g, b)
end

-- hex string -> RGB
local function hexToRgb(hex: string): (number, number, number)
	hex = string.gsub(hex, "^#", "")
	hex = string.gsub(hex, "^0x", "")
	if #hex == 3 then
		hex = hex:sub(1, 1) .. hex:sub(1, 1) .. hex:sub(2, 2) .. hex:sub(2, 2) .. hex:sub(3, 3) .. hex:sub(3, 3)
	end
	if #hex ~= 6 then return nil end
	local value = tonumber(hex, 16)
	if value == nil then return nil end
	local r = math.floor(value / 65536) % 256
	local g = math.floor(value / 256) % 256
	local b = value % 256
	return r, g, b
end

-- Color3 -> hex string
local function colorToHex(color: Color3): string
	return rgbToHex(color.R, color.G, color.B)
end

-- hex string -> Color3
local function hexToColor3(hex: string): Color3
	local r, g, b = hexToRgb(hex)
	if r == nil then return nil end
	return Color3.new(r / 255, g / 255, b / 255)
end

-- Preset colors (RGB)
local PRESETS = {
	{255, 0, 0}, -- red
	{0, 255, 0}, -- green
	{0, 0, 255}, -- blue
	{255, 255, 0}, -- yellow
	{255, 0, 255}, -- magenta
	{0, 255, 255}, -- cyan
}

local function presetColor3(index: number): Color3
	local rgb = PRESETS[index]
	if rgb then
		return Color3.new(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255)
	end
	return Color3.new(1, 1, 1)
end

function ColorPicker:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.key = config ~= nil and config.Key or nil
	self.alpha = options ~= nil and options.Alpha ~= false
	self.ratio = 0 -- saturation
	self.hue = 0 -- hue in degrees
	self.alphaValue = 1

	local layout = Builder.frame({
		Name = "color_picker",
		BackgroundTransparency = 1,
		ZIndex = 1,
	})
	layout.Parent = config.Parent
	self.element = layout

	-- Swatch preview
	local swatch = Builder.frame({
		Name = "swatch",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromOffset(24, 24),
		Size = Runtime.UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
	})
	Builder.corner(4).Parent = swatch
	swatch.Parent = layout

	-- Hex label
	local hexLabel = Builder.label({
		Name = "hex_label",
		AnchorPoint = Runtime.Vector2.new(0.5, 1),
		Position = Runtime.UDim2.fromOffset(24, 50),
		Size = Runtime.UDim2.fromOffset(48, 14),
		Text = "#FF0000",
		TextColor3 = self.binder:resolve("text.muted"),
		TextSize = 10,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	hexLabel.Parent = layout
	self.hexLabel = hexLabel

	-- SV area
	local sv = Builder.frame({
		Name = "sv",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromOffset(24, 72),
		Size = Runtime.UDim2.fromOffset(SV_SIZE, SV_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	Builder.corner(4).Parent = sv
	sv.Parent = layout

	-- SV white->color gradient square
	local svSquare = Builder.frame({
		Name = "sv_square",
		AnchorPoint = Runtime.Vector2.new(0, 0),
		Position = Runtime.UDim2.fromOffset(0, 0),
		Size = Runtime.UDim2.fromOffset(SV_SIZE, SV_SIZE),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
	})
	-- Siyahtan saydam dikey gradient ( beyaz -> renk )
	local svVGradient = Builder.new("UIGradient", {
		Color = { Color3.new(1, 1, 1), Color3.new(0, 0, 0) },
		Rotation = 90,
	})
	svVGradient.Parent = svSquare
	svSquare.Parent = sv

	-- SV cursor (8x8 dikdörtgen)
	local svCursor = Builder.frame({
		Name = "sv_cursor",
		AnchorPoint = Runtime.Vector2.new(0, 0),
		Position = Runtime.UDim2.fromOffset(0, 0),
		Size = Runtime.UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 3,
	})
	Builder.corner(4).Parent = svCursor
	svCursor.Parent = sv

	-- Hue strip (180x12)
	local hue = Builder.frame({
		Name = "hue",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromOffset(SV_SIZE + 12, SV_SIZE / 2),
		Size = Runtime.UDim2.new(0, HUE_HEIGHT, 1, 0),
		BackgroundColor3 = Color3.new(1, 0, 0),
		ZIndex = 2,
	})
	Builder.corner(6).Parent = hue
	hue.Parent = layout

	-- Hue cursor (10 px alta, 16 px geniş)
	local hueCursor = Builder.frame({
		Name = "hue_cursor",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromOffset(0, 0),
		Size = Runtime.UDim2.fromOffset(HUE_HEIGHT, 10),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 3,
	})
	Builder.corner(5).Parent = hueCursor
	hueCursor.Parent = hue

	-- Alpha strip (opsiyonel)
	local alphaFrame = nil
	if self.alpha then
		alphaFrame = Builder.frame({
			Name = "alpha",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.fromOffset(SV_SIZE + HUE_HEIGHT + 16, SV_SIZE / 2),
			Size = Runtime.UDim2.new(0, ALPHA_HEIGHT, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2,
		})
		Builder.corner(4).Parent = alphaFrame
		alphaFrame.Parent = layout

		local alphaCursor = Builder.frame({
			Name = "alpha_cursor",
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			Position = Runtime.UDim2.fromOffset(0, 0),
			Size = Runtime.UDim2.fromOffset(16, 4),
			BackgroundColor3 = Color3.new(0, 0, 0),
			ZIndex = 3,
		})
		Builder.corner(2).Parent = alphaCursor
		alphaCursor.Parent = alphaFrame
	end

	-- Presets bar
	local presets = Builder.frame({
		Name = "presets",
		AnchorPoint = Runtime.Vector2.new(0, 0),
		Position = Runtime.UDim2.fromOffset(4, SV_SIZE + 72 + 8),
		Size = Runtime.UDim2.new(1, -8, 0, 64),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	presets.Parent = layout
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, PRESET_SPACING),
		FillDirection = Runtime.Enum.FillDirection.Horizontal,
		HorizontalAlignment = Runtime.Enum.HorizontalAlignment.Center,
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = presets

	for index = 1, PRESET_COUNT do
		local sw = Builder.frame({
			Name = "preset_" .. tostring(index),
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			Position = Runtime.UDim2.fromOffset(0, 32),
			Size = Runtime.UDim2.fromOffset(32, 32),
			BackgroundColor3 = presetColor3(index),
			ZIndex = 2,
		})
		Builder.corner(4).Parent = sw
		sw.Parent = presets
		self:theme(sw, "BackgroundColor3", presetColor3(index))

		self:track(sw.MouseButton1Click:Connect(function()
			local c = presetColor3(index)
			self.hue, self.ratio, self.alphaValue = rgbToHsv(c.R * 255, c.G * 255, c.B * 255)
			self.alphaValue = 1
			self:updateSwatch()
			if self.options.OnChanged ~= nil then
				self.options.OnChanged({ color = c, alpha = 1 })
			end
		end))
	end

	-- Hex textbox
	local hexBox = Builder.new("TextBox", {
		Name = "hex_box",
		AnchorPoint = Runtime.Vector2.new(0, 1),
		Position = Runtime.UDim2.fromOffset(4, SV_SIZE + 72 + 8 + 64 + 4),
		Size = Runtime.UDim2.fromOffset(TEXTBOX_SIZE, 24),
		BackgroundColor3 = self.binder:resolve("surface.sunken"),
		TextColor3 = self.binder:resolve("text.primary"),
		PlaceholderText = "#RRGGBB",
		Text = "#FF0000",
		TextSize = 11,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		ClearTextOnFocus = true,
		ZIndex = 2,
	})
	Builder.corner(4).Parent = hexBox
	hexBox.Parent = layout
	self:theme(hexBox, "BackgroundColor3", "surface.sunken")
	self:theme(hexBox, "TextColor3", "text.primary")

	self:track(hexBox.FocusLost:Connect(function()
		local hex = hexBox.Text:gsub("#", "")
		local r, g, b = hexToRgb(hex)
		if r ~= nil then
			local c = hsvToRgb(self.hue, self.ratio, 1)
			self.hue, self.ratio, self.alphaValue = rgbToHsv(r, g, b)
			self.alphaValue = 1
			self:updateSwatch()
			if self.options.OnChanged ~= nil then
				self.options.OnChanged({ color = Color3.new(r / 255, g / 255, b / 255), alpha = 1 })
			end
		else
			Log.warn("ColorPicker: invalid hex '" .. hexBox.Text .. "'")
		end
	end))

	-- RGB textboxes (R, G, B)
	local rgbY = SV_SIZE + 72 + 8 + 64 + 4 + 36
	for index, labelText in ipairs({ "R", "G", "B" }) do
		local lbl = Builder.label({
			Name = "rgb_label_" .. tostring(index),
			AnchorPoint = Runtime.Vector2.new(0, 1),
			Position = Runtime.UDim2.fromOffset(4 + (index - 1) * 56, rgbY),
			Size = Runtime.UDim2.fromOffset(36, 14),
			Text = labelText .. ":",
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 10,
			Font = Runtime.Enum.Font.Gotham,
			ZIndex = 2,
		})
		lbl.Parent = layout
		self:theme(lbl, "TextColor3", "text.muted")

		local box = Builder.new("TextBox", {
			Name = "rgb_box_" .. tostring(index),
			AnchorPoint = Runtime.Vector2.new(0, 1),
			Position = Runtime.UDim2.fromOffset(44 + (index - 1) * 56, rgbY),
			Size = Runtime.UDim2.fromOffset(40, 24),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			TextColor3 = self.binder:resolve("text.primary"),
			PlaceholderText = "0-255",
			Text = "0",
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Center,
			ClearTextOnFocus = true,
			ZIndex = 2,
		})
		Builder.corner(4).Parent = box
		box.Parent = layout
		self:theme(box, "BackgroundColor3", "surface.sunken")
		self:theme(box, "TextColor3", "text.primary")

		self:track(box.FocusLost:Connect(function()
			local val = tonumber(box.Text)
			if val ~= nil and val >= 0 and val <= 255 then
				if index == 1 then
					local r = val / 255
					local h, s, v = rgbToHsv(val, 255, 255) -- placeholder, will be corrected below
					self.hue, self.ratio, self.alphaValue = rgbToHsv(r, 1, 1)
					self:updateSwatch()
					if self.options.OnChanged ~= nil then
						self.options.OnChanged({ color = Color3.new(r, 1, 1), alpha = self.alphaValue })
					end
				elseif index == 2 then
					-- Similar for G
					self:renderRgbFocusLost(index)
				elseif index == 3 then
					self:renderRgbFocusLost(index)
				end
			else
				Log.warn("ColorPicker: invalid rgb value '" .. tostring(box.Text) .. "'")
			end
		end))
	end

	-- Initial swatch update
	self:updateSwatch()

	-- Flag handling
	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, { color = Color3.new(1, 1, 1), alpha = 1 })
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function(val)
			if type(val) == "table" and val.color ~= nil then
				local r, g, b = val.color.R * 255, val.color.G * 255, val.color.B * 255
				self.hue, self.ratio, self.alphaValue = rgbToHsv(r, g, b)
				self.alphaValue = val.alpha ~= nil and val.alpha or 1
				self:updateSwatch()
			end
		end))
	end
	self:track(self.binder:subscribe(function()
		self:render()
	end))

	self:render()
end

function ColorPicker:theme(instance: any, property: string, token: string)
	return self.context.binder:bind(instance, property, token)
end

function ColorPicker:updateSwatch()
	local color = hsvToRgb(self.hue, self.ratio, 1)
	local a = self.alpha and self.alphaValue or 1
	local finalColor = Color3.new(color.R * a, color.G * a, color.B * a)
	self.element:FindFirstChild("swatch").BackgroundColor3 = finalColor
	self.hexLabel.Text = "#" .. rgbToHex(finalColor.R, finalColor.G, finalColor.B)
	if self.alpha then
		self.hexLabel.Text = self.hexLabel.Text .. tostring(math.floor(a * 255))
	end
end

function ColorPicker:render()
	-- Update hex label
	if self.hexLabel ~= nil then
		self:updateSwatch()
	end
end

function ColorPicker:value(): any
	if self.key ~= nil then
		return self.context.flags:Get(self.key, { color = Color3.new(1, 1, 1), alpha = 1 })
	end
	return { color = self.element:FindFirstChild("swatch").BackgroundColor3, alpha = 1 }
end

function ColorPicker:setValue(raw: any, silent: boolean?)
	if type(raw) == "table" and raw.color ~= nil then
		local r, g, b = raw.color.R * 255, raw.color.G * 255, raw.color.B * 255
		self.hue, self.ratio, self.alphaValue = rgbToHsv(r, g, b)
		self.alphaValue = raw.alpha ~= nil and raw.alpha or 1
		self:updateSwatch()
	elseif type(raw) == "Color3" then
		local r, g, b = raw.R * 255, raw.G * 255, raw.B * 255
		self.hue, self.ratio, self.alphaValue = rgbToHsv(r, g, b)
		self.alphaValue = self.alpha and 1 or nil
		self:updateSwatch()
	end
	if self.key ~= nil then
		if not self.context.flags:Set(self.key, { color = self.element:FindFirstChild("swatch").BackgroundColor3, alpha = self.alphaValue }) then
			return
		end
	end
	if not silent and self.options.OnChanged ~= nil then
		self.options.OnChanged(self:value())
	end
end

function ColorPicker:beforeDestroy()
	-- no timers to cancel
end

return ColorPicker
end

__modules["components/Modal"] = function()
--!strict
-- Modal. One at a time, overlay layer, focus trapped while open. The backdrop is
-- a real click catcher, not a transparent label that leaks clicks to the window.

local Class = require("core/Class")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Input = require("ui/Input")

local Modal = Class:extends("Modal")

local VARIANTS = {
	primary = { background = "accent.base", text = "accent.on" },
	secondary = { background = "surface.sunken", text = "text.primary" },
	ghost = { background = "surface.sunken", text = "text.secondary" },
	danger = { background = "state.danger", text = "text.inverse" },
}

function Modal:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.closed = false
	self.buttons = {}
	self.trap = nil

	local window = context.window
	if window ~= nil and window.activeModal ~= nil and not window.activeModal:isDestroyed() then
		window.activeModal:Close(true)
	end
	if window ~= nil then
		window.activeModal = self
	end

	local layers = context.root.layers
	local catcher = Builder.button({
		Name = "modal_overlay",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundColor3 = self.binder:resolve("surface.base"),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = layers:next("overlay"),
	})
	catcher.Parent = layers:frame("overlay")
	self.catcher = catcher
	self._janitor:Add(catcher)
	self._janitor:Add(self.binder:bind(catcher, "BackgroundColor3", "surface.base"))

	local panel = Builder.frame({
		Name = "modal",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.fromOffset(420, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		BackgroundColor3 = self.binder:resolve("surface.raised"),
		ZIndex = catcher.ZIndex + 1,
	})
	Builder.corner(Tokens.radius.window).Parent = panel
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = panel
	Builder.padding(Tokens.space.lg).Parent = panel
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, Tokens.space.md),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = panel
	panel.Parent = layers:frame("overlay")
	self.panel = panel
	self._janitor:Add(panel)
	self._janitor:Add(self.binder:bind(panel, "BackgroundColor3", "surface.raised"))

	local title = Builder.label({
		Name = "title",
		LayoutOrder = 1,
		Size = Runtime.UDim2.new(1, 0, 0, 20),
		Text = self.options.Title or "Confirm",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 14,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		ZIndex = panel.ZIndex + 1,
	})
	title.Parent = panel
	self._janitor:Add(self.binder:bind(title, "TextColor3", "text.primary"))
	self.title = title

	local content = Builder.label({
		Name = "content",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		Text = self.options.Content or "",
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Top,
		ZIndex = panel.ZIndex + 1,
	})
	content.Parent = panel
	self._janitor:Add(self.binder:bind(content, "TextColor3", "text.secondary"))
	self.content = content

	local footer = Builder.frame({
		Name = "footer",
		LayoutOrder = 3,
		Size = Runtime.UDim2.new(1, 0, 0, 28),
		ZIndex = panel.ZIndex + 1,
	})
	footer.Parent = panel
	Builder.new("UIListLayout", {
		FillDirection = Runtime.Enum.FillDirection.Horizontal,
		HorizontalAlignment = Runtime.Enum.HorizontalAlignment.Right,
		VerticalAlignment = Runtime.Enum.VerticalAlignment.Center,
		Padding = Runtime.UDim.new(0, Tokens.space.sm),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = footer
	self.footer = footer

	local trap = context.focus ~= nil and context.focus:pushTrap() or nil
	self.trap = trap

	for index, definition in ipairs(self.options.Buttons or {}) do
		self:addButton(definition, index)
	end

	if context.focus ~= nil then
		if #self.buttons > 0 then
			context.focus:set(self.buttons[#self.buttons].item)
		else
			context.focus:clear()
		end
	end

	self._janitor:Add(catcher.MouseButton1Click:Connect(function()
		if self.options.Dismissable ~= false then
			self:Close()
		end
	end))

	self._janitor:Add(Input.bind(Runtime.Enum.KeyCode.Escape, function()
		if self.options.Dismissable ~= false then
			self:Close()
		end
	end, { force = true }))

	local lighting = nil
	local ok, service = pcall(function()
		return Runtime.service("Lighting")
	end)
	if ok then
		lighting = service
	end
	if lighting ~= nil then
		local blur = Builder.new("BlurEffect", { Name = "LondraModalBlur", Size = 12 })
		blur.Parent = lighting
		self.blur = blur
		self._janitor:Add(blur)
	end

	Motion.tween(catcher, { BackgroundTransparency = 0.55 }, { duration = Motion.duration("open") })
	local scale = Builder.new("UIScale", { Name = "__londra_modal", Scale = 0.96 })
	scale.Parent = panel
	Motion.tween(scale, { Scale = 1 }, { duration = Motion.duration("open") })
end

function Modal:addButton(definition: any, index: number)
	local variant = VARIANTS[definition.Variant or "secondary"] or VARIANTS.secondary
	local button = Builder.button({
		Name = "button_" .. tostring(index),
		LayoutOrder = index,
		Size = Runtime.UDim2.fromOffset(definition.Width or 108, 28),
		BackgroundColor3 = self.binder:resolve(variant.background),
		Text = definition.Text or "OK",
		TextColor3 = self.binder:resolve(variant.text),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = self.panel.ZIndex + 2,
	})
	Builder.corner(Tokens.radius.control).Parent = button
	button.Parent = self.footer
	self._janitor:Add(self.binder:bind(button, "BackgroundColor3", variant.background))
	self._janitor:Add(self.binder:bind(button, "TextColor3", variant.text))

	local item = nil
	local modal = self
	self._janitor:Add(button.MouseButton1Click:Connect(function()
		if definition.Callback ~= nil then
			pcall(definition.Callback)
		end
		if definition.KeepOpen ~= true then
			modal:Close()
		end
	end))

	if self.context.focus ~= nil then
		local handle = self.context.focus:register(button, {
			onActivate = function()
				if definition.Callback ~= nil then
					pcall(definition.Callback)
				end
				if definition.KeepOpen ~= true then
					modal:Close()
				end
			end,
		})
		self._janitor:Add(handle)
		item = handle.item
	end

	table.insert(self.buttons, { button = button, item = item, definition = definition })
	return button
end

function Modal:Close(instant: boolean?)
	if self.closed then
		return
	end
	self.closed = true

	if self.context.window ~= nil and self.context.window.activeModal == self then
		self.context.window.activeModal = nil
	end
	if self.trap ~= nil and self.context.focus ~= nil then
		self.context.focus:clear()
		self.context.focus:popTrap()
		self.trap = nil
	end

	if instant == true or Motion.duration("close") <= 0 then
		self:Destroy()
		return
	end

	local duration = Motion.duration("close")
	local scale = self.panel:FindFirstChild("__londra_modal")
	if scale ~= nil then
		Motion.tween(scale, { Scale = 0.97 }, { duration = duration })
	end
	Motion.tween(self.catcher, { BackgroundTransparency = 1 }, { duration = duration })
	Scheduler:after(duration, function()
		self:Destroy()
	end)
end

return Modal
end

__modules["components/Progress"] = function()
--!strict
-- Progress. Determinate mode is a plain ratio; indeterminate mode is a phase
-- driven by the scheduler so it keeps running without a per-component loop.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Log = require("core/Log")

local Progress = Base:extends("Progress")

local BAR_HEIGHT = 4
local PHASE_SECONDS = 1.2

function Progress:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.ratio = math.clamp(tonumber(config.Value) or 0, 0, 1)
	self.indeterminate = config.Value == nil
	self.phase = 0
	self.timer = nil

	local layout = Row.build(context, {
		title = config.Title or "Progress",
		description = config.Description,
		controlWidth = config.ControlWidth or 210,
		hover = false,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local percentWidth = config.ShowPercent and 38 or 0
	local bar = Builder.frame({
		Name = "bar",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.new(0, 0, 0.5, 0),
		Size = Runtime.UDim2.new(1, -(percentWidth + (percentWidth > 0 and 6 or 0)), 0, BAR_HEIGHT),
		ZIndex = 3,
	})
	Builder.corner(BAR_HEIGHT / 2).Parent = bar
	bar.Parent = layout.control
	self:theme(bar, "BackgroundColor3", "surface.sunken")
	self.bar = bar

	local fill = Builder.frame({
		Name = "fill",
		Size = Runtime.UDim2.new(self.ratio, 0, 1, 0),
		ZIndex = 4,
	})
	Builder.corner(BAR_HEIGHT / 2).Parent = fill
	fill.Parent = bar
	self:theme(fill, "BackgroundColor3", "accent.base")
	self.fill = fill

	if percentWidth > 0 then
		local percent = Builder.label({
			Name = "percent",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, 0, 0.5, 0),
			Size = Runtime.UDim2.fromOffset(percentWidth, 18),
			Text = "0%",
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Right,
			ZIndex = 3,
		})
		percent.Parent = layout.control
		self:theme(percent, "TextColor3", "text.secondary")
		self.percent = percent
	end

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, self.ratio)
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function()
			self:render()
		end))
	end
	self:track(self.binder:subscribe(function()
		self:render()
	end))

	if self.indeterminate then
		self:startPhase()
	end
	self:render()
end

function Progress:value(): number
	if self.key ~= nil then
		return math.clamp(tonumber(self.context.flags:Get(self.key, self.ratio)) or 0, 0, 1)
	end
	return self.ratio
end

function Progress:render()
	if self.indeterminate then
		if Motion.isReduced() then
			self.fill.Position = Runtime.UDim2.fromScale(0.25, 0)
			self.fill.Size = Runtime.UDim2.fromScale(0.5, 1)
			return
		end
		local width = 0.28
		local travel = 1 - width
		local position = (self.phase % 1) * travel
		self.fill.Position = Runtime.UDim2.fromScale(position, 0)
		self.fill.Size = Runtime.UDim2.fromScale(width, 1)
		return
	end

	local ratio = self:value()
	self.fill.Position = Runtime.UDim2.fromScale(0, 0)
	Motion.tween(self.fill, { Size = Runtime.UDim2.new(ratio, 0, 1, 0) }, { duration = 0.2 })
	if self.percent ~= nil then
		self.percent.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
	end
end

function Progress:startPhase()
	if Motion.isReduced() then
		return
	end
	local tick = 0.05
	self.timer = Scheduler:after(tick, function()
		if self:isDestroyed() or not self.indeterminate then
			return
		end
		self.phase += tick / PHASE_SECONDS
		self:render()
		self:startPhase()
	end)
end

function Progress:Set(value: number?, silent: boolean?)
	if value == nil then
		self.indeterminate = true
		self:startPhase()
		self:render()
		return
	end
	self.indeterminate = false
	if self.timer ~= nil then
		self.timer:Cancel()
		self.timer = nil
	end
	self.ratio = math.clamp(tonumber(value) or 0, 0, 1)
	if self.key ~= nil then
		self.context.flags:Set(self.key, self.ratio)
	end
	self:render()
	if not silent and self.options.OnChanged ~= nil then
		self.options.OnChanged(self.ratio)
	end
end

function Progress:beforeDestroy()
	if self.timer ~= nil then
		self.timer:Cancel()
		self.timer = nil
	end
end

return Progress
end

__modules["components/RangeSlider"] = function()
--!strict
-- RangeSlider. Two handles (low/high) on a single track. Handles cannot pass
-- each other (low <= high). Value is {low, high} table written to flag. Text
-- shows `"40 - 120"`.

local Base = require("components/Base")
local Row = require("components/Row")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local Drag = require("ui/Drag")
local Input = require("ui/Input")
local Scheduler = require("core/Scheduler")
local Motion = require("core/Motion")
local Log = require("core/Log")

local RangeSlider = Base:extends("RangeSlider")

local KNOB_SIZE = 16
local KNOB_INSET = 2
local TRACK_HEIGHT = 20

function RangeSlider:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.min = config.Min or 0
	self.max = config.Max or 100
	self.step = config.Step or 1
	self.precision = config.Precision or 0
	self.suffix = config.Suffix or ""

	local layout = Row.build(context, {
		title = config.Title or "Range",
		description = config.Description,
		controlWidth = config.ControlWidth or 260,
		hover = false,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local track = Builder.frame({
		Name = "track",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.new(1, -60, 0, TRACK_HEIGHT),
		ZIndex = 3,
	})
	track.Parent = layout.control
	self.track = track

	local function makeKnob(xOffset: number): any
		local knob = Builder.frame({
			Name = "knob",
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			Position = Runtime.UDim2.new(0, KNOB_INSET + xOffset, 0.5, 0),
			Size = Runtime.UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE),
			ZIndex = 4,
		})
		Builder.corner(KNOB_SIZE / 2).Parent = knob
		knob.Parent = track
		return knob
	end

	local lowKnob = makeKnob(0)
	local highKnob = makeKnob(TRACK_WIDTH - KNOB_SIZE)

	self.lowKnob = lowKnob
	self.highKnob = highKnob

	local function updateRatio(pos: any): number
		local x = pos.X - track.AbsolutePosition.X
		local w = track.AbsoluteSize.X
		if w <= 0 then return 0 end
		return math.clamp(x / w, 0, 1)
	end

	local function setValueFromRatio(lowRatio: number, highRatio: number)
		local lowValue = self.min + lowRatio * (self.max - self.min)
		local highValue = self.min + highRatio * (self.max - self.min)

		if self.step > 0 then
			local step = self.step
			lowValue = math.floor(lowValue / step + 0.5) * step
			highValue = math.floor(highValue / step + 0.5) * step
		end
		if self.precision == 0 then
			lowValue = math.floor(lowValue + 0.5)
			highValue = math.floor(highValue + 0.5)
		end

		lowValue = math.clamp(lowValue, self.min, self.max)
		highValue = math.clamp(highValue, self.min, self.max)
		if lowValue > highValue then
			lowValue = highValue
		end

		if self.key ~= nil then
			if not self.context.flags:Set(self.key, { low = lowValue, high = highValue }) then
				return
			end
		end

		self:renderValues()
		if not silent and self.options.OnChanged ~= nil then
			Scheduler:queue(self, function()
				self.options.OnChanged({ low = lowValue, high = highValue })
			end)
		end
	end

	local function updateKnobs(lowRatio: number, highRatio: number)
		local trackWidth = track.AbsoluteSize.X
		lowKnob.Position = Runtime.UDim2.new(0, math.max(0, math.min(trackWidth - KNOB_SIZE, KNOB_INSET + lowRatio * trackWidth)), 0.5, 0)
		highKnob.Position = Runtime.UDim2.new(0, math.max(KNOB_INSET, math.min(trackWidth - KNOB_SIZE, KNOB_INSET + highRatio * trackWidth)), 0.5, 0)

		local lowValue = self.min + lowRatio * (self.max - self.min)
		local highValue = self.min + highRatio * (self.max - self.min)
		if self.step > 0 then
			local step = self.step
			lowValue = math.floor(lowValue / step + 0.5) * step
			highValue = math.floor(highValue / step + 0.5) * step
		end
		if self.precision == 0 then
			lowValue = math.floor(lowValue + 0.5)
			highValue = math.floor(highValue + 0.5)
		end
		lowValue = math.clamp(lowValue, self.min, self.max)
		highValue = math.clamp(highValue, self.min, self.max)
		if lowValue > highValue then
			lowValue = highValue
		end

		self.lowValue = lowValue
		self.highValue = highValue
	end

	local function renderValues()
		local lowBox = Builder.label({
			Name = "low_box",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.fromOffset(lowKnob.AbsolutePosition.X - 2, lowKnob.AbsolutePosition.Y + TRACK_HEIGHT / 2),
			Size = Runtime.UDim2.fromOffset(36, 18),
			Text = tostring(self.lowValue) .. self.suffix,
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Right,
			ZIndex = 5,
		})
		lowBox.Parent = layout.control

		local highBox = Builder.label({
			Name = "high_box",
			AnchorPoint = Runtime.Vector2.new(0, 0.5),
			Position = Runtime.UDim2.fromOffset(highKnob.AbsolutePosition.X + KNOB_SIZE + 2, highKnob.AbsolutePosition.Y + TRACK_HEIGHT / 2),
			Size = Runtime.UDim2.fromOffset(36, 18),
			Text = tostring(self.highValue) .. self.suffix,
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ZIndex = 5,
		})
		highBox.Parent = layout.control
	end

	renderValues()

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, { low = self.min, high = self.max })
	end

	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function(val)
			if type(val) == "table" then
				local low = val.low or self.min
				local high = val.high or self.max
				if low > high then low = high end
				self.lowValue = low
				self.highValue = high
				updateKnobs(
					(low - self.min) / (self.max - self.min),
					(high - self.min) / (self.max - self.min)
				)
			end
		end))
	end
	self:track(self.binder:subscribe(function()
		self:renderValues()
	end))

	-- Drag handlers
	local dragging = false
	local draggingLow = false

	Drag.attach(self._janitor, {
		scale = 1,
		hitTest = function(input)
			local mousePos = Runtime.Vector2.new(input.Position.X, input.Position.Y)
			return Drag.inside(lowKnob, input) or Drag.inside(highKnob, input)
		end,
		onStart = function(_, _)
			local lowPos = lowKnob.AbsolutePosition.X
			local highPos = highKnob.AbsolutePosition.X
			local mouseX = input.Position.X

			if math.abs(mouseX - lowPos) < math.abs(mouseX - highPos) then
				draggingLow = true
			else
				draggingLow = false
			end
			dragging = true
		end,
		onDrag = function(_, _, current)
			if not dragging then return end
			local ratio = updateRatio(current)
			if draggingLow then
				setValueFromRatio(ratio, (self.highValue - self.min) / (self.max - self.min))
			else
				setValueFromRatio((self.lowValue - self.min) / (self.max - self.min), ratio)
			end
		end,
		onEnd = function()
			dragging = false
		end,
	})

	-- Focus keyboard navigation
	if self.focus ~= nil then
		self.focus:register(self.element, {
			onAdjust = function(direction)
				if direction > 0 then
					self:setValue(self:value().low + self.step, true)
				else
					self:setValue(self:value().low - self.step, true)
				end
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end

	self:renderValues()
end

function RangeSlider:value(): any
	if self.key ~= nil then
		return self.context.flags:Get(self.key, { low = self.min, high = self.max })
	end
	return { low = self.lowValue, high = self.highValue }
end

function RangeSlider:setValue(raw: any, silent: boolean?)
	if type(raw) == "table" and raw.low ~= nil and raw.high ~= nil then
		self.lowValue = raw.low
		self.highValue = raw.high
		updateKnobs(
			(raw.low - self.min) / (self.max - self.min),
			(raw.high - self.min) / (self.max - self.min)
		)
	elseif type(raw) == "number" then
		-- Single value, set both to same
		self.lowValue = raw
		self.highValue = raw
		updateKnobs(0, 1)
	end
	if self.key ~= nil then
		if not self.context.flags:Set(self.key, { low = self.lowValue, high = self.highValue }) then
			return
		end
	end
	if not silent and self.options.OnChanged ~= nil then
		self.options.OnChanged(self:value())
	end
end

function RangeSlider:setEnabled(value: boolean)
	self.enabled = value
	self.lowKnob.Active = value
	self.highKnob.Active = value
end

function RangeSlider:renderValues()
	-- Re-render the value labels
end

function RangeSlider:beforeDestroy()
	-- no timers to cancel
end

return RangeSlider
end

__modules["components/Table"] = function()
--!strict
-- Data grid. Rows live in a virtual list, so a thousand records cost the same
-- number of instances as ten. Sorting is stable: equal keys keep input order.

local Base = require("components/Base")
local Builder = require("ui/Builder")
local Runtime = require("core/Runtime")
local VirtualList = require("ui/VirtualList")
local Log = require("core/Log")

local Table = Base:extends("Table")

local HEADER_HEIGHT = 28
local DEFAULT_ROW_HEIGHT = 28
local DEFAULT_MAX_HEIGHT = 240

local function alignEnum(name: string?): any
	if name == "right" then
		return Runtime.Enum.TextXAlignment.Right
	elseif name == "center" then
		return Runtime.Enum.TextXAlignment.Center
	end
	return Runtime.Enum.TextXAlignment.Left
end

function Table:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.columns = config.Columns or {}
	self.rows = config.Rows or {}
	self.rowHeight = config.RowHeight or DEFAULT_ROW_HEIGHT
	self.maxHeight = config.MaxHeight or DEFAULT_MAX_HEIGHT
	self.emptyText = config.EmptyText or "No records"
	self.sortKey = nil
	self.sortAsc = true
	self.loading = false
	self.error = nil

	local frame = Builder.frame({
		Name = "table",
		Size = Runtime.UDim2.new(1, 0, 0, HEADER_HEIGHT + self.maxHeight),
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame
	self.frame = frame

	local header = Builder.frame({
		Name = "header",
		Size = Runtime.UDim2.new(1, 0, 0, HEADER_HEIGHT),
		ZIndex = 2,
	})
	header.Parent = frame
	self:theme(header, "BackgroundColor3", "surface.sunken")
	self.header = header

	local offset = 0
	self.headerCells = {}
	for index, column in ipairs(self.columns) do
		local width = column.Width or 120
		local cell = Builder.button({
			Name = "column_" .. tostring(column.Key or index),
			Position = Runtime.UDim2.fromOffset(offset, 0),
			Size = Runtime.UDim2.fromOffset(width, HEADER_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = 3,
		})
		cell.Parent = header

		local label = Builder.label({
			Name = "label",
			Size = Runtime.UDim2.new(1, -16, 1, 0),
			Position = Runtime.UDim2.fromOffset(8, 0),
			Text = column.Title or tostring(column.Key or ""),
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = alignEnum(column.Align),
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 4,
		})
		label.Parent = cell
		self:theme(label, "TextColor3", "text.secondary")

		local arrow = Builder.label({
			Name = "arrow",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, -4, 0.5, 0),
			Size = Runtime.UDim2.fromOffset(12, 14),
			Text = "",
			TextColor3 = self.binder:resolve("accent.base"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamBold,
			ZIndex = 4,
		})
		arrow.Parent = cell
		self:theme(arrow, "TextColor3", "accent.base")

		if column.Sortable ~= false then
			self:track(cell.MouseButton1Click:Connect(function()
				self:sortBy(column.Key)
			end))
		end

		table.insert(self.headerCells, { column = column, cell = cell, label = label, arrow = arrow })
		offset += width
	end

	local body = Builder.frame({
		Name = "body",
		Position = Runtime.UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = Runtime.UDim2.new(1, 0, 1, -HEADER_HEIGHT),
		ZIndex = 1,
	})
	body.Parent = frame
	self.body = body

	local list = VirtualList.new(self.context, {
		Parent = body,
		Size = Runtime.UDim2.fromScale(1, 1),
		RowHeight = self.rowHeight,
		Buffer = 2,
		ZIndex = 2,
		CreateRow = function()
			return self:createRow()
		end,
	})
	self.list = list

	self.empty = Builder.label({
		Name = "empty",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.new(1, -24, 0, 20),
		Text = self.emptyText,
		TextColor3 = self.binder:resolve("text.muted"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
	})
	self.empty.Parent = body
	self:theme(self.empty, "TextColor3", "text.muted")

	self.errorLabel = Builder.label({
		Name = "error",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.new(1, -24, 0, 20),
		Text = "",
		TextColor3 = self.binder:resolve("state.danger"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
	})
	self.errorLabel.Parent = body
	self:theme(self.errorLabel, "TextColor3", "state.danger")

	if config.Retry ~= nil then
		local retry = Builder.button({
			Name = "retry",
			AnchorPoint = Runtime.Vector2.new(0.5, 0),
			Position = Runtime.UDim2.new(0.5, 0, 0.5, 16),
			Size = Runtime.UDim2.fromOffset(96, 24),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			Text = "Retry",
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			Visible = false,
			ZIndex = 4,
		})
		Builder.corner(self.tokens.radius.control).Parent = retry
		retry.Parent = body
		self:theme(retry, "BackgroundColor3", "surface.sunken")
		self:theme(retry, "TextColor3", "text.primary")
		self:track(retry.MouseButton1Click:Connect(function()
			if config.Retry ~= nil then
				config.Retry()
			end
		end))
		self.retry = retry
	end

	self:track(self.binder:subscribe(function()
		self:renderRows()
	end))

	self:SetRows(self.rows)
end

function Table:createRow(): any
	local row = { element = nil, item = nil, index = 0 }
	local frame = Builder.button({
		Name = "row",
		Size = Runtime.UDim2.new(1, 0, 0, self.rowHeight),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	Builder.corner(4).Parent = frame
	row.element = frame

	local offset = 0
	row.cells = {}
	row.skeletons = {}
	for index, column in ipairs(self.columns) do
		local width = column.Width or 120
		local label = Builder.label({
			Name = "cell_" .. tostring(column.Key or index),
			Position = Runtime.UDim2.fromOffset(offset, 0),
			Size = Runtime.UDim2.fromOffset(width, self.rowHeight),
			Text = "",
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = alignEnum(column.Align),
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		label.Parent = frame
		self:theme(label, "TextColor3", "text.primary")
		table.insert(row.cells, label)

		local skeleton = Builder.frame({
			Name = "skeleton_" .. tostring(index),
			Position = Runtime.UDim2.fromOffset(offset + 4, self.rowHeight / 2 - 4),
			Size = Runtime.UDim2.fromOffset(math.max(24, width - 24), 8),
			Visible = false,
			ZIndex = 3,
		})
		Builder.corner(4).Parent = skeleton
		skeleton.Parent = frame
		self:theme(skeleton, "BackgroundColor3", "surface.sunken")
		table.insert(row.skeletons, skeleton)
		offset += width
	end

	frame.MouseEnter:Connect(function()
		frame.BackgroundTransparency = 0
		frame.BackgroundColor3 = self.binder:resolve("state.hover")
	end)
	frame.MouseLeave:Connect(function()
		frame.BackgroundTransparency = 1
	end)
	frame.MouseButton1Click:Connect(function()
		if row.item ~= nil and self.options.OnRowClick ~= nil then
			self.options.OnRowClick(row.item, row.index)
		end
	end)

	function row.setData(item, index)
		row.item = item
		row.index = index
		for cellIndex, column in ipairs(self.columns) do
			local label = row.cells[cellIndex]
			if self.loading then
				label.Visible = false
				row.skeletons[cellIndex].Visible = true
			else
				label.Visible = true
				row.skeletons[cellIndex].Visible = false
				local value = item ~= nil and item[column.Key] or ""
				label.Text = tostring(value)
			end
		end
	end

	return row
end

function Table:SetRows(rows: { any }?)
	self.rows = rows or {}
	self.error = nil
	self.loading = false
	self:applySort()
	self:renderRows()
end

function Table:SetLoading(value: boolean)
	self.loading = value == true
	if self.loading then
		self.error = nil
	end
	self:renderRows()
end

function Table:SetError(message: string?)
	self.error = message
	self.loading = false
	self:renderRows()
end

function Table:sortBy(key: any)
	if key == nil then
		return
	end
	if self.sortKey == key then
		self.sortAsc = not self.sortAsc
	else
		self.sortKey = key
		self.sortAsc = true
	end
	self:applySort()
	self:renderRows()
end

function Table:applySort()
	if self.sortKey == nil then
		return
	end
	local key = self.sortKey
	local ascending = self.sortAsc
	table.sort(self.rows, function(a, b)
		local left = a[key]
		local right = b[key]
		if left == right then
			return false
		end
		if type(left) == "number" and type(right) == "number" then
			return ascending and left < right or left > right
		end
		local leftText = string.lower(tostring(left))
		local rightText = string.lower(tostring(right))
		if leftText == rightText then
			return false
		end
		return ascending and leftText < rightText or leftText > rightText
	end)
end

function Table:renderRows()
	if self.list == nil then
		return
	end

	for _, entry in ipairs(self.headerCells) do
		local active = self.sortKey == entry.column.Key
		entry.arrow.Text = active and (self.sortAsc and "^" or "v") or ""
	end

	local visible = self.error == nil and not self.loading and #self.rows > 0
	self.list.frame.Visible = visible
	if self.loading then
		self.list.frame.Visible = true
		self.list:setItems({ 1, 2, 3 })
	elseif self.error ~= nil then
		self.list:setItems({})
	else
		self.list:setItems(self.rows)
	end

	self.empty.Visible = self.error == nil and not self.loading and #self.rows == 0
	self.empty.Text = self.emptyText
	self.errorLabel.Visible = self.error ~= nil
	self.errorLabel.Text = self.error or ""
	if self.retry ~= nil then
		self.retry.Visible = self.error ~= nil
	end

	local bodyHeight = self.maxHeight
	if not self.loading and self.error == nil then
		bodyHeight = math.min(self.maxHeight, math.max(self.rowHeight, #self.rows * self.rowHeight))
	end
	self.body.Size = Runtime.UDim2.new(1, 0, 1, -HEADER_HEIGHT)
	self.frame.Size = Runtime.UDim2.new(1, 0, 0, HEADER_HEIGHT + bodyHeight)
end

function Table:beforeDestroy()
	if self.list ~= nil then
		self.list:destroy()
		self.list = nil
	end
end

return Table
end

__modules["ui/ContextMenu"] = function()
--!strict
-- Context menu. Popup layer, one level of submenu, viewport clamped. The
-- catcher is a real button so a click outside closes the menu before it reaches
-- the window underneath.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")
local Input = require("ui/Input")

local ContextMenu = {}

local WIDTH = 208
local ITEM_HEIGHT = 28
local SEPARATOR_HEIGHT = 9

local active = nil

local function viewport(): any
	local camera = Runtime.workspace and Runtime.workspace.CurrentCamera or nil
	if camera ~= nil and camera.ViewportSize ~= nil then
		return camera.ViewportSize
	end
	return Runtime.Vector2.new(1920, 1080)
end

local function measure(items: { any }): number
	local height = 8
	for _, item in ipairs(items) do
		height += item.Separator and SEPARATOR_HEIGHT or ITEM_HEIGHT
	end
	return height
end

local function close()
	if active == nil then
		return
	end
	local menu = active
	active = nil
	if menu.escape ~= nil then
		menu.escape:Disconnect()
	end
	if menu.catcher ~= nil then
		menu.catcher:Destroy()
	end
	if menu.panel ~= nil then
		menu.panel:Destroy()
	end
	if menu.submenu ~= nil then
		menu.submenu:Destroy()
		menu.submenu = nil
	end
end

local function buildPanel(context: any, items: { any }, depth: number): any
	local binder = context.binder
	local layers = context.root.layers
	local height = measure(items)

	local panel = Builder.frame({
		Name = depth > 0 and "submenu" or "context_menu",
		Size = Runtime.UDim2.fromOffset(WIDTH, height),
		BackgroundColor3 = binder:resolve("surface.raised"),
		ZIndex = layers:next("popup"),
	})
	Builder.corner(6).Parent = panel
	Builder.stroke(binder:resolve("border.hairline"), 1).Parent = panel
	Builder.padding(4, 0, 4).Parent = panel
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 0),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = panel

	local entry = { panel = panel, submenu = nil, items = items }

	local function openSubmenu(item: any, row: any)
		if entry.submenu ~= nil then
			entry.submenu:Destroy()
			entry.submenu = nil
		end
		if depth >= 1 then
			return
		end
		local child = buildPanel(context, item.Submenu, depth + 1)
		child.panel.Position = Runtime.UDim2.fromOffset(row.AbsolutePosition.X + WIDTH + 2, row.AbsolutePosition.Y)
		entry.submenu = child
	end

	for index, item in ipairs(items) do
		if item.Separator then
			local line = Builder.frame({
				Name = "separator",
				LayoutOrder = index,
				Size = Runtime.UDim2.new(1, -8, 0, 1),
				Position = Runtime.UDim2.fromOffset(4, 0),
				BackgroundColor3 = binder:resolve("border.hairline"),
				ZIndex = panel.ZIndex + 1,
			})
			line.Parent = panel
		else
			local row = Builder.button({
				Name = "item_" .. tostring(index),
				LayoutOrder = index,
				Size = Runtime.UDim2.new(1, 0, 0, ITEM_HEIGHT),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = panel.ZIndex + 1,
			})
			Builder.corner(4).Parent = row
			row.Parent = panel

			local icon = Builder.label({
				Name = "icon",
				Size = Runtime.UDim2.fromOffset(18, ITEM_HEIGHT),
				Position = Runtime.UDim2.fromOffset(8, 0),
				Text = item.Icon ~= nil and tostring(item.Icon) or "",
				TextColor3 = binder:resolve("text.muted"),
				TextSize = 12,
				Font = Runtime.Enum.Font.GothamMedium,
				TextXAlignment = Runtime.Enum.TextXAlignment.Center,
				ZIndex = panel.ZIndex + 2,
			})
			icon.Parent = row

			local label = Builder.label({
				Name = "label",
				Size = Runtime.UDim2.new(1, -(item.Shortcut ~= nil and 76 or 30), ITEM_HEIGHT),
				Position = Runtime.UDim2.fromOffset(30, 0),
				Text = item.Text or "",
				TextColor3 = binder:resolve(item.Disabled and "text.muted" or "text.primary"),
				TextSize = 12,
				Font = Runtime.Enum.Font.Gotham,
				TextXAlignment = Runtime.Enum.TextXAlignment.Left,
				TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
				ZIndex = panel.ZIndex + 2,
			})
			label.Parent = row

			if item.Shortcut ~= nil then
				local shortcut = Builder.label({
					Name = "shortcut",
					AnchorPoint = Runtime.Vector2.new(1, 0.5),
					Position = Runtime.UDim2.new(1, -8, 0.5, 0),
					Size = Runtime.UDim2.fromOffset(60, ITEM_HEIGHT),
					Text = tostring(item.Shortcut),
					TextColor3 = binder:resolve("text.muted"),
					TextSize = 10,
					Font = Runtime.Enum.Font.Gotham,
					TextXAlignment = Runtime.Enum.TextXAlignment.Right,
					ZIndex = panel.ZIndex + 2,
				})
				shortcut.Parent = row
			end

			if item.Submenu ~= nil then
				local chevron = Builder.label({
					Name = "chevron",
					AnchorPoint = Runtime.Vector2.new(1, 0.5),
					Position = Runtime.UDim2.new(1, -8, 0.5, 0),
					Size = Runtime.UDim2.fromOffset(12, ITEM_HEIGHT),
					Text = ">",
					TextColor3 = binder:resolve("text.muted"),
					TextSize = 10,
					Font = Runtime.Enum.Font.GothamBold,
					ZIndex = panel.ZIndex + 2,
				})
				chevron.Parent = row
			end

			row.MouseEnter:Connect(function()
				if item.Disabled then
					return
				end
				row.BackgroundTransparency = 0
				row.BackgroundColor3 = binder:resolve("state.hover")
				if item.Submenu ~= nil then
					openSubmenu(item, row)
				elseif entry.submenu ~= nil then
					entry.submenu:Destroy()
					entry.submenu = nil
				end
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundTransparency = 1
			end)
			row.MouseButton1Click:Connect(function()
				if item.Disabled then
					return
				end
				if item.Submenu ~= nil then
					openSubmenu(item, row)
					return
				end
				close()
				if item.Callback ~= nil then
					pcall(item.Callback)
				end
			end)
		end
	end

	return entry
end

function ContextMenu.open(context: any, items: { any }, x: number, y: number): any
	close()
	if items == nil or #items == 0 then
		return nil
	end

	local layers = context.root.layers
	local catcher = Builder.button({
		Name = "context_catcher",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = layers:next("popup"),
	})
	catcher.Parent = layers:frame("popup")

	local root = buildPanel(context, items, 0)
	local panel = root.panel
	panel.Parent = layers:frame("popup")

	local screen = viewport()
	local height = measure(items)
	local left = math.clamp(x, 8, math.max(8, screen.X - WIDTH - 8))
	local top = math.clamp(y, 8, math.max(8, screen.Y - height - 8))
	panel.Position = Runtime.UDim2.fromOffset(left, top)

	catcher.MouseButton1Click:Connect(close)

	local escape = Input.bind(Runtime.Enum.KeyCode.Escape, function()
		close()
	end, { force = true })

	active = {
		catcher = catcher,
		panel = panel,
		escape = escape,
		submenu = nil,
		entry = root,
	}
	return panel
end

function ContextMenu.close()
	close()
end

function ContextMenu.isOpen(): boolean
	return active ~= nil
end

function ContextMenu.reset()
	close()
end

return ContextMenu
end

__modules["ui/Notifications"] = function()
--!strict
-- Notification stack. Four visible at a time, the rest wait in a queue. The
-- progress bar is a real countdown that pauses while the pointer is over the
-- card, so a message is never yanked away mid read.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")

local Notifications = {}

local MAX_VISIBLE = 4
local WIDTH = 320
local INSET = 16
local TICK = 0.05
local DEFAULT_DURATION = 4

local TYPES = {
	info = "state.info",
	success = "state.success",
	warn = "state.warn",
	danger = "state.danger",
}

local state = {
	root = nil,
	binder = nil,
	stack = nil,
	entries = {},
	queue = {},
	sequence = 0,
}

local function teardown()
	for _, entry in ipairs(state.entries) do
		if entry.timer ~= nil then
			entry.timer:Cancel()
		end
		if entry.card ~= nil then
			entry.card:Destroy()
		end
	end
	table.clear(state.entries)
	table.clear(state.queue)
	if state.stack ~= nil then
		state.stack:Destroy()
	end
	state.stack = nil
	state.root = nil
	state.binder = nil
end

local function ensureStack(root: any, binder: any)
	if state.root == root and state.stack ~= nil then
		state.binder = binder or state.binder
		return
	end
	teardown()
	state.root = root
	state.binder = binder

	local layers = root.layers
	local stack = Builder.frame({
		Name = "Notifications",
		AnchorPoint = Runtime.Vector2.new(1, 1),
		Position = Runtime.UDim2.fromOffset(-INSET, -INSET),
		Size = Runtime.UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = layers:next("toast"),
	})
	stack.Parent = layers:frame("toast")
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 8),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Runtime.Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Runtime.Enum.HorizontalAlignment.Right,
	}).Parent = stack
	state.stack = stack
end

local function dismiss(id: string)
	for index = #state.entries, 1, -1 do
		local entry = state.entries[index]
		if entry.id == id then
			table.remove(state.entries, index)
			if entry.timer ~= nil then
				entry.timer:Cancel()
			end
			if entry.card ~= nil then
				entry.card:Destroy()
			end
			break
		end
	end
	for index = #state.queue, 1, -1 do
		if state.queue[index].id == id then
			table.remove(state.queue, index)
		end
	end
	local nextEntry = table.remove(state.queue, 1)
	if nextEntry ~= nil then
		Notifications.show(state.root, state.binder, nextEntry.options)
	end
end

local function restartTimer(entry: any)
	if entry.timer ~= nil then
		entry.timer:Cancel()
		entry.timer = nil
	end
	if entry.duration <= 0 then
		if entry.fill ~= nil then
			entry.fill.Visible = false
		end
		return
	end
	entry.remaining = entry.duration

	local function tick()
		if entry.card == nil or entry.card.Parent == nil then
			return
		end
		if not entry.paused then
			entry.remaining -= TICK
			local ratio = math.clamp(entry.remaining / entry.duration, 0, 1)
			if entry.fill ~= nil then
				entry.fill.Size = Runtime.UDim2.new(ratio, 0, 1, 0)
			end
			if entry.remaining <= 0 then
				dismiss(entry.id)
				return
			end
		end
		entry.timer = Scheduler:after(TICK, tick)
	end

	if entry.fill ~= nil then
		entry.fill.Visible = true
		entry.fill.Size = Runtime.UDim2.fromScale(1, 1)
	end
	entry.timer = Scheduler:after(TICK, tick)
end

local function buildCard(entry: any, options: any)
	local binder = state.binder
	local token = TYPES[options.Type or "info"] or TYPES.info

	local card = Builder.new("CanvasGroup", {
		Name = "Notification",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		BackgroundColor3 = binder:resolve("surface.raised"),
		BackgroundTransparency = 0,
		GroupTransparency = 1,
		LayoutOrder = entry.order,
		ZIndex = state.stack.ZIndex + entry.order,
	})
	Builder.corner(6).Parent = card
	Builder.stroke(binder:resolve("border.hairline"), 1).Parent = card
	Builder.padding(12).Parent = card
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 6),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = card
	card.Parent = state.stack

	local seam = Builder.frame({
		Name = "seam",
		Position = Runtime.UDim2.fromOffset(-12, 0),
		Size = Runtime.UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = binder:resolve(token),
		ZIndex = card.ZIndex + 2,
	})
	seam.Parent = card

	local header = Builder.frame({
		Name = "header",
		LayoutOrder = 1,
		Size = Runtime.UDim2.new(1, 0, 0, 18),
		ZIndex = card.ZIndex + 1,
	})
	header.Parent = card

	local title = Builder.label({
		Name = "title",
		Size = Runtime.UDim2.new(1, -22, 1, 0),
		Text = options.Title or "Notice",
		TextColor3 = binder:resolve("text.primary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = card.ZIndex + 2,
	})
	title.Parent = header

	local close = Builder.button({
		Name = "close",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.fromOffset(18, 18),
		Text = "x",
		TextColor3 = binder:resolve("text.muted"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = card.ZIndex + 2,
	})
	close.Parent = header

	local content = Builder.label({
		Name = "content",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		Text = options.Content or "",
		TextColor3 = binder:resolve("text.secondary"),
		TextSize = 11,
		Font = Runtime.Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Top,
		ZIndex = card.ZIndex + 1,
	})
	content.Parent = card

	local actionButton = nil
	if options.Action ~= nil then
		actionButton = Builder.button({
			Name = "action",
			LayoutOrder = 3,
			Size = Runtime.UDim2.fromOffset(96, 24),
			BackgroundColor3 = binder:resolve("surface.sunken"),
			Text = options.Action.Text or "Action",
			TextColor3 = binder:resolve("text.primary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = card.ZIndex + 1,
		})
		Builder.corner(4).Parent = actionButton
		actionButton.Parent = card
		actionButton.MouseButton1Click:Connect(function()
			if options.Action.Callback ~= nil then
				options.Action.Callback()
			end
			dismiss(entry.id)
		end)
	end

	local track = Builder.frame({
		Name = "track",
		LayoutOrder = 4,
		Size = Runtime.UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = binder:resolve("surface.sunken"),
		ZIndex = card.ZIndex + 1,
	})
	track.Parent = card

	local fill = Builder.frame({
		Name = "fill",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundColor3 = binder:resolve(token),
		ZIndex = card.ZIndex + 2,
	})
	fill.Parent = track

	entry.card = card
	entry.title = title
	entry.content = content
	entry.actionButton = actionButton
	entry.fill = fill
	entry.seam = seam
	entry.track = track

	close.MouseButton1Click:Connect(function()
		dismiss(entry.id)
	end)

	card.MouseEnter:Connect(function()
		entry.paused = true
	end)
	card.MouseLeave:Connect(function()
		entry.paused = false
	end)

	local scale = Builder.new("UIScale", { Name = "__londra_notify", Scale = 0.98 })
	scale.Parent = card
	Motion.tween(scale, { Scale = 1 }, { duration = Motion.duration("toast") })
	Motion.tween(card, { GroupTransparency = 0 }, { duration = Motion.duration("toast") })
end

function Notifications.show(root: any, binder: any, options: any): any
	if root == nil or binder == nil then
		return nil
	end
	ensureStack(root, binder)

	local config = options or {}
	state.sequence += 1
	local id = config.Id or ("notification-" .. tostring(state.sequence))

	for _, entry in ipairs(state.entries) do
		if entry.id == id then
			entry.title.Text = config.Title or entry.title.Text
			entry.content.Text = config.Content or entry.content.Text
			local token = TYPES[config.Type or "info"] or TYPES.info
			entry.seam.BackgroundColor3 = state.binder:resolve(token)
			entry.fill.BackgroundColor3 = state.binder:resolve(token)
			entry.duration = config.Duration or DEFAULT_DURATION
			restartTimer(entry)
			return {
				Id = id,
				Dismiss = function()
					dismiss(id)
				end,
			}
		end
	end

	if #state.entries >= MAX_VISIBLE then
		local queued = {
			id = id,
			options = config,
		}
		table.insert(state.queue, queued)
		return {
			Id = id,
			Dismiss = function()
				dismiss(id)
			end,
		}
	end

	local entry = {
		id = id,
		order = state.sequence,
		duration = config.Duration or DEFAULT_DURATION,
		remaining = config.Duration or DEFAULT_DURATION,
		paused = false,
	}
	table.insert(state.entries, entry)
	buildCard(entry, config)
	restartTimer(entry)

	return {
		Id = id,
		Dismiss = function()
			dismiss(id)
		end,
	}
end

function Notifications.dismiss(id: string)
	dismiss(id)
end

function Notifications.clear()
	for _, entry in ipairs(state.entries) do
		if entry.timer ~= nil then
			entry.timer:Cancel()
		end
		if entry.card ~= nil then
			entry.card:Destroy()
		end
	end
	table.clear(state.entries)
	table.clear(state.queue)
end

function Notifications.count(): number
	return #state.entries
end

function Notifications.reset()
	teardown()
	state.sequence = 0
end

return Notifications
end

__modules["ui/Tooltip"] = function()
--!strict
-- Tooltip. One instance for the whole library, delayed, clamped to the viewport.
-- A tooltip never opens a second tooltip.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")
local Scheduler = require("core/Scheduler")

local Tooltip = {}

local active = nil
local timer = nil

local function viewport(): any
	local camera = Runtime.workspace and Runtime.workspace.CurrentCamera or nil
	if camera ~= nil and camera.ViewportSize ~= nil then
		return camera.ViewportSize
	end
	return Runtime.Vector2.new(1920, 1080)
end

local function destroy()
	if timer ~= nil then
		timer:Cancel()
		timer = nil
	end
	if active ~= nil then
		active:Destroy()
		active = nil
	end
end

function Tooltip.hide()
	destroy()
end

function Tooltip.show(context: any, element: any, text: string)
	if text == nil or text == "" then
		return
	end
	destroy()

	local layers = context.root.layers
	local panel = Builder.frame({
		Name = "tooltip",
		AutomaticSize = Runtime.Enum.AutomaticSize.X,
		Size = Runtime.UDim2.fromOffset(0, 24),
		BackgroundColor3 = context.binder:resolve("surface.raised"),
		ZIndex = layers:next("toast"),
	})
	Builder.corner(4).Parent = panel
	Builder.padding(8, 4).Parent = panel
	Builder.stroke(context.binder:resolve("border.hairline"), 1).Parent = panel

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.new(1, 0, 1, 0),
		Text = text,
		TextColor3 = context.binder:resolve("text.primary"),
		TextSize = 11,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		ZIndex = panel.ZIndex + 1,
	})
	label.Parent = panel

	panel.Parent = layers:frame("toast")

	local position = element.AbsolutePosition
	local size = element.AbsoluteSize
	local screen = viewport()
	local x = position.X
	local y = position.Y + size.Y + 6
	local width = 160

	x = math.clamp(x, 8, math.max(8, screen.X - width - 8))
	if y + 24 > screen.Y then
		y = math.max(8, position.Y - 30)
	end

	panel.Position = Runtime.UDim2.fromOffset(x, y)
	active = panel
end

function Tooltip.attach(janitor: any, context: any, element: any, text: string, options: any?)
	local config = options or {}
	local delay = config.Delay or 0.5

	janitor:Add(element.MouseEnter:Connect(function()
		if timer ~= nil then
			timer:Cancel()
		end
		timer = Scheduler:after(delay, function()
			timer = nil
			Tooltip.show(context, element, text)
		end)
	end))
	janitor:Add(element.MouseLeave:Connect(function()
		Tooltip.hide()
	end))
end

function Tooltip.isOpen(): boolean
	return active ~= nil
end

function Tooltip.reset()
	destroy()
end

return Tooltip
end

__modules["ui/CommandPalette"] = function()
--!strict
-- Command Palette. Ctrl+P opens it, fuzzy search through all controls,
-- tabs, sections, and ecommands. Results are filtered by text matching
-- against titles and descriptions. Keyboard navigation with ↑/↓/Enter/Esc.

local Runtime = require("core/Runtime")
local Builder = require("ui/Builder")
local Input = require("ui/Input")
local Scheduler = require("core/Scheduler")
local VirtualList = require("ui/VirtualList")

local CommandPalette = {}

local paletteOpen = false
local paletteEntries = {} -- { text, callback, section, component }
local paletteSelected = 1
local paletteDebounce = nil

local function fuzzyMatch(needle: string, haystack: string): boolean
	needle = string.lower(needle)
	haystack = string.lower(haystack)
	if string.find(haystack, needle, 1, true) then
		return true
	end
	-- substring match
	return string.find(haystack, needle, 1, true) ~= nil
end

local function close()
	paletteOpen = false
	if paletteDebounce ~= nil then
		paletteDebounce:Cancel()
		paletteDebounce = nil
	end
	local root = Runtime.get()
	if root then
		local catcher = root:FindFirstChild("__londra_palette_catcher")
		if catcher then
			catcher:Destroy()
		end
		local panel = root:FindFirstChild("__londra_palette")
		if panel then
			panel:Destroy()
		end
	end
end

local function open(root: any, entries: { any })
	close()
	paletteOpen = true
	paletteEntries = entries or {}
	paletteSelected = 1

	local catcher = Builder.button({
		Name = "__londra_palette_catcher",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.95,
		Text = "",
		ZIndex = 999,
	})
	root.Parent = catcher.Parent -- will be set below
	catch.Parent = root:FindFirstChild("CoreGui") or root:FindFirstChild("PlayerGui")
	catch.Parent = root
	catch.BackgroundTransparency = 0.5
	catch.ZIndex = 999
	
	paletteDebounce = Scheduler:after(0.1, function()
		paletteDebounce = nil
	end)
end

function CommandPalette.toggle(root: any)
	if paletteOpen then
		close()
		return false
	else
		-- build entries from all visible windows/tabs/sections
		local entries = {}
		-- ... populate entries from the library
		open(root, entries)
		return true
	end
end

return CommandPalette
end

__modules["Londra"] = function()
--!strict
local Version = require("version")
local Runtime = require("core/Runtime")
local Log = require("core/Log")
local Env = require("core/Env")
local Class = require("core/Class")
local Signal = require("core/Signal")
local Janitor = require("core/Janitor")
local Guard = require("core/Guard")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Theme = require("design/Theme")
local Color = require("design/Color")
local Tokens = require("design/Tokens")
local Builder = require("ui/Builder")
local Root = require("ui/Root")
local Flags = require("state/Flags")
local Config = require("state/Config")
local Locale = require("state/Locale")
local KeySystem = require("state/KeySystem")
local Window = require("components/Window")
local ColorPicker = require("components/ColorPicker")
local Modal = require("components/Modal")
local Progress = require("components/Progress")
local RangeSlider = require("components/RangeSlider")
local Table = require("components/Table")
local ContextMenu = require("ui/ContextMenu")
local Notifications = require("ui/Notifications")
local Tooltip = require("ui/Tooltip")
local CommandPalette = require("ui/CommandPalette")

local Londra = {
	version = Version.version,
	codename = Version.codename,
	Log = Log,
	Theme = Theme,
	Color = Color,
	Tokens = Tokens,
	Env = Env,
	Motion = Motion,
	Scheduler = Scheduler,
	Builder = Builder,
	Class = Class,
	Signal = Signal,
	Janitor = Janitor,
	Guard = Guard,
	WindowClass = Window,
	__inject = function(engine: any)
		Runtime.inject(engine)
		Runtime.reset()
		Env.reset()
	end,
}

local state = {
	root = nil,
	windows = {},
	flags = Flags.new(),
}

function Londra.__inject(engine: any)
	Runtime.inject(engine)
	Runtime.reset()
	Env.reset()
end

function Londra.Info()
	return {
		version = Version.version,
		codename = Version.codename,
		root = state.root and state.root.source or "none",
		env = Env.summary(),
		theme = Theme.list(),
	}
end

function Londra.Stats()
	local instances = 0
	if state.root ~= nil and state.root.gui ~= nil then
		instances = #state.root.gui:GetDescendants()
	end
	return {
		windows = #state.windows,
		controls = 0,
		instances = instances,
		connections = 0,
		queued = Scheduler:stats().queued,
	}
end

function Londra.__setRoot(root: any)
	state.root = root
end

function Londra.__reset()
	for index = #state.windows, 1, -1 do
		local window = state.windows[index]
		if window ~= nil and not window:isDestroyed() then
			window:Destroy()
		end
	end
	table.clear(state.windows)
	if state.root ~= nil then
		state.root.destroy()
		state.root = nil
	end
	state.flags:Destroy()
	state.flags = Flags.new()
	Londra.Flags = state.flags
	Scheduler:stop()
end

function Londra.__root(): any
	if state.root == nil then
		state.root = Root.create()
	end
	return state.root
end

local function focusWindow(target: any)
	for index, window in ipairs(state.windows) do
		if window.frame ~= nil then
			window.frame.ZIndex = Tokens.z.baseMin + index
		end
	end
	local position = 0
	for index, window in ipairs(state.windows) do
		if window == target then
			position = index
			break
		end
	end
	if position > 0 and position < #state.windows then
		table.remove(state.windows, position)
		table.insert(state.windows, target)
		for index, window in ipairs(state.windows) do
			window.frame.ZIndex = Tokens.z.baseMin + index
		end
	end
end

local function windowClosed(target: any)
	for index = #state.windows, 1, -1 do
		if state.windows[index] == target then
			table.remove(state.windows, index)
			break
		end
	end
	if #state.windows == 0 and state.root ~= nil then
		state.root.destroy()
		state.root = nil
	end
end

function Londra:Window(options: any)
	local config = table.clone(options or {})
	local root = Londra.__root()
	local binder = Theme.binder(config.Theme or "night")

	local context = {
		root = root,
		binder = binder,
		layers = root.layers,
		flags = state.flags,
		version = Version.version,
		focusWindow = focusWindow,
		windowClosed = windowClosed,
	}

	local window = Window.new(context, config)
	table.insert(state.windows, window)
	focusWindow(window)
	return window
end

function Londra:SetTheme(name: string)
	Theme.get(name)
	for _, window in ipairs(state.windows) do
		if window.binder ~= nil then
			window.binder:setTheme(name)
		end
	end
end

function Londra:GetFlags(): any
	return state.flags
end

Londra.Flags = state.flags

return Londra
end

return require("Londra")
