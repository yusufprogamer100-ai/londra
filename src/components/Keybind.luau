--!strict
-- Keybind. Capture uses the global input map's one-shot handler, so no second
-- UserInputService connection is opened per control.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Input = require("../ui/Input")
local Log = require("../core/Log")

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
