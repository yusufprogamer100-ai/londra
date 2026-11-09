--!strict
-- Text input with real validation. Invalid input keeps the last valid flag and
-- explains itself below the field instead of silently accepting garbage.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Input = require("../ui/Input")
local Log = require("../core/Log")

local Textbox = Base:extends("Textbox")

function Textbox:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.validValue = config.Default or ""
	self.error = nil

	if self.key == nil then
		Log.warn("Textbox: missing Key, control will not persist")
	end

	local multiline = config.Multiline == true
	local layout = Row.build(context, {
		title = config.Title or "Text",
		description = config.Description,
		controlWidth = config.ControlWidth or 220,
		height = multiline and 64 or nil,
		hover = false,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local box = Builder.new("TextBox", {
		Name = "input",
		Size = Runtime.UDim2.new(1, 0, 0, multiline and 52 or 26),
		Position = Runtime.UDim2.fromOffset(0, multiline and 4 or 4),
		BackgroundColor3 = self.binder:resolve("surface.sunken"),
		TextColor3 = self.binder:resolve("text.primary"),
		PlaceholderColor3 = self.binder:resolve("text.muted"),
		PlaceholderText = config.Placeholder or "",
		Text = self.validValue,
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextWrapped = multiline,
		MultiLine = multiline,
		ClearTextOnFocus = config.ClearOnFocus == true,
		TextEditable = true,
		ClipsDescendants = true,
		ZIndex = 3,
	})
	Builder.corner(4).Parent = box
	local stroke = Builder.stroke(self.binder:resolve("border.hairline"), 1)
	stroke.Parent = box
	box.Parent = layout.control
	self:theme(box, "BackgroundColor3", "surface.sunken")
	self:theme(box, "TextColor3", "text.primary")
	self:theme(box, "PlaceholderColor3", "text.muted")
	self.box = box
	self.stroke = stroke

	if config.Password == true then
		local mask = Builder.label({
			Name = "mask",
			Size = Runtime.UDim2.new(1, -16, 1, 0),
			Position = Runtime.UDim2.fromOffset(8, 0),
			Text = "",
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		mask.Parent = box
		self:theme(mask, "TextColor3", "text.primary")
		box.TextTransparency = 1
		self.mask = mask
	end

	local errorLabel = Builder.label({
		Name = "error",
		Size = Runtime.UDim2.new(1, 0, 0, 14),
		Position = Runtime.UDim2.new(0, 0, 0, multiline and 58 or 32),
		Text = "",
		TextColor3 = self.binder:resolve("state.danger"),
		TextSize = 11,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 3,
	})
	errorLabel.Parent = layout.control
	self:theme(errorLabel, "TextColor3", "state.danger")
	self.errorLabel = errorLabel

	if self.key ~= nil and not context.flags:Has(self.key) then
		context.flags:Set(self.key, self.validValue)
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function(value)
			if value ~= nil and value ~= box.Text then
				self.validValue = tostring(value)
				box.Text = self.validValue
			end
		end))
	end

	self:track(box.Focused:Connect(function()
		Input.suspend()
	end))

	local textbox = self
	local function submit()
		Input.resume()
		local text = box.Text
		local ok = true
		local message = nil
		if config.Validate ~= nil then
			local passed, reason = config.Validate(text)
			ok = passed == true
			message = reason
		end
		if not ok then
			textbox:showError(message or "Invalid value")
			return
		end
		textbox:clearError()
		textbox.validValue = text
		if textbox.key ~= nil then
			context.flags:Set(textbox.key, text)
		end
		if config.OnSubmit ~= nil then
			config.OnSubmit(text)
		end
	end

	self:track(box.FocusLost:Connect(submit))
	self:track(box.ReturnPressed:Connect(submit))
	self:track(box.TextChanged:Connect(function()
		if self.mask ~= nil then
			self.mask.Text = string.rep("*", #box.Text)
		end
		if config.OnChanged ~= nil then
			config.OnChanged(box.Text)
		end
	end))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onActivate = function()
				box:CaptureFocus()
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
end

function Textbox:showError(message: string)
	self.error = message
	self.errorLabel.Text = message
	self.errorLabel.Visible = true
	self.stroke.Color = self.binder:resolve("state.danger")
	self.layout.row.Size = Runtime.UDim2.new(1, 0, 0, self.options.Multiline and 76 or 50)
end

function Textbox:clearError()
	if self.error == nil then
		return
	end
	self.error = nil
	self.errorLabel.Visible = false
	self.stroke.Color = self.binder:resolve("border.hairline")
	self.layout.row.Size = Runtime.UDim2.new(1, 0, 0, self.options.Multiline and 64 or self.layout.height)
end

function Textbox:setValue(value: string, silent: boolean?)
	self.validValue = tostring(value)
	self.box.Text = self.validValue
	if self.key ~= nil then
		self.context.flags:Set(self.key, self.validValue)
	end
	if not silent and self.options.OnChanged ~= nil then
		self.options.OnChanged(self.validValue)
	end
end

function Textbox:setEnabled(value: boolean)
	self.enabled = value
	self.box.TextEditable = value
	self.box.Active = value
end

return Textbox
