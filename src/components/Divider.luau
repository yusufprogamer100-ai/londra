--!strict
-- Hairline separator, the library's seam motif. An optional label sits on the
-- line and masks it with the surrounding surface colour.

local Base = require("./Base")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")

local Divider = Base:extends("Divider")

function Divider:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local height = config.Text ~= nil and 18 or 9

	local frame = Builder.frame({
		Name = "divider",
		Size = Runtime.UDim2.new(1, 0, 0, height),
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame

	local line = Builder.frame({
		Name = "line",
		AnchorPoint = Runtime.Vector2.new(0, 0.5),
		Position = Runtime.UDim2.new(0, 0, 0.5, 0),
		Size = Runtime.UDim2.new(1, 0, 0, 1),
		ZIndex = 1,
	})
	line.Parent = frame
	self:theme(line, "BackgroundColor3", "border.hairline")

	if config.Text ~= nil and config.Text ~= "" then
		local label = Builder.label({
			Name = "label",
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			Position = Runtime.UDim2.fromScale(0.5, 0.5),
			Size = Runtime.UDim2.new(0, 0, 0, 14),
			AutomaticSize = Runtime.Enum.AutomaticSize.X,
			Text = "  " .. tostring(config.Text) .. "  ",
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 10,
			Font = Runtime.Enum.Font.Gotham,
			ZIndex = 2,
		})
		label.Parent = frame
		self:theme(label, "BackgroundColor3", "surface.raised")
		self:theme(label, "TextColor3", "text.muted")
		label.BackgroundTransparency = 0
		self.label = label
	end
end

return Divider
