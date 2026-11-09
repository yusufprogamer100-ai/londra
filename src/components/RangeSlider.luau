--!strict
-- RangeSlider. Two handles (low/high) on a single track. Handles cannot pass
-- each other (low <= high). Value is {low, high} table written to flag. Text
-- shows `"40 - 120"`.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Drag = require("../ui/Drag")
local Input = require("../ui/Input")
local Scheduler = require("../core/Scheduler")
local Motion = require("../core/Motion")
local Log = require("../core/Log")

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