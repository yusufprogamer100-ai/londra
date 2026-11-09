--!strict
-- Progress. Determinate mode is a plain ratio; indeterminate mode is a phase
-- driven by the scheduler so it keeps running without a per-component loop.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Scheduler = require("../core/Scheduler")
local Log = require("../core/Log")

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
