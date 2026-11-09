--!strict
-- Wrapped prose. AutomaticSize keeps the section layout honest without asking
-- the caller to guess a pixel height.

local Base = require("./Base")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")

local Paragraph = Base:extends("Paragraph")

function Paragraph:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local frame = Builder.frame({
		Name = "paragraph",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame

	local layout = Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 4),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	})
	layout.Parent = frame
	Builder.padding(0, 0, 6).Parent = frame

	if config.Title ~= nil and config.Title ~= "" then
		local title = Builder.label({
			Name = "title",
			LayoutOrder = 1,
			Size = Runtime.UDim2.new(1, 0, 0, 16),
			Text = config.Title,
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		})
		title.Parent = frame
		self:theme(title, "TextColor3", "text.primary")
	end

	local text = Builder.label({
		Name = "text",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		Text = config.Text or "",
		TextWrapped = true,
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = config.TextSize or 12,
		LineHeight = 1.25,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Top,
	})
	text.Parent = frame
	self:theme(text, "TextColor3", "text.secondary")
	self.text = text
end

return Paragraph
