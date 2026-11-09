--!strict
-- ZIndex budget. Every layer owns a range, so a dropdown can never end up under
-- a modal by accident.

local Tokens = require("../design/Tokens")
local Log = require("../core/Log")

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
