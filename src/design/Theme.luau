--!strict
-- Token themes plus per-window binders. A theme switch walks the binding list,
-- never the instance tree: O(bindings), not O(descendants).

local Color = require("./Color")
local Runtime = require("../core/Runtime")
local Log = require("../core/Log")
local ThemeNight = require("./ThemeNight")
local ThemeDay = require("./ThemeDay")
local ThemeContrast = require("./ThemeContrast")

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
