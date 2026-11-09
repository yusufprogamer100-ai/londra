--!strict
-- Color picker. Panel lives on the popup layer. SV square is two-layer (white->color,
-- siyahtan saydam), hue strip is 180x12, alpha strip optional. Hex/RGB textboxes
-- validate. Default colors are preset. Value is { color = Color3, alpha = number }.

local Runtime = require("../core/Runtime")
local Builder = require("../ui/Builder")
local Input = require("../ui/Input")
local Scheduler = require("../core/Scheduler")
local Motion = require("../core/Motion")
local Log = require("../core/Log")

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