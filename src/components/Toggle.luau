--!strict
-- Toggle reads and writes a flag, never a private copy. The visual state is a
-- pure function of that flag, so config load and external writes stay in sync.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Log = require("../core/Log")

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
