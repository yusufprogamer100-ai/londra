--!strict
-- Slider. Pointer position is converted to a value through one formula, and the
-- same formula feeds drag, click and keyboard, so the three cannot disagree.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Drag = require("../ui/Drag")
local Input = require("../ui/Input")
local Scheduler = require("../core/Scheduler")
local Log = require("../core/Log")

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
