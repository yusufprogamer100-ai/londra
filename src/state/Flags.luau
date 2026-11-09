--!strict
-- Single owner of every control value. Controls write here and listen here;
-- they never keep a second copy that can drift out of sync.

local Runtime = require("../core/Runtime")
local Log = require("../core/Log")
local Signal = require("../core/Signal")

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
