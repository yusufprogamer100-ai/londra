--!strict
-- Read-only row: label on the left, value on the right. Values truncate before
-- they ever touch the label.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")

local Label = Base:extends("Label")

function Label:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local layout = Row.build(context, {
		title = config.Title or "",
		description = config.Description,
		hover = false,
		controlWidth = config.ValueWidth or 180,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	if config.Value ~= nil then
		local value = Builder.label({
			Name = "value",
			Size = Runtime.UDim2.fromScale(1, 1),
			Text = tostring(config.Value),
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Right,
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 2,
		})
		value.Parent = layout.control
		self:theme(value, "TextColor3", "text.secondary")
		self.valueLabel = value
	end

	if config.Icon ~= nil then
		layout.label.Text = tostring(config.Icon) .. "  " .. layout.label.Text
	end
end

function Label:setValue(value: any)
	if self.valueLabel == nil then
		return
	end
	self.valueLabel.Text = tostring(value)
end

return Label
