--!strict
-- Colour maths. Every conversion is explicit so it can be unit tested against
-- the WCAG formula and against a reference HSV implementation.

local Runtime = require("../core/Runtime")

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
