--!strict
-- A tab owns a scroll surface and a section stack. Scroll position survives tab
-- switches, so returning to a page does not jump back to the top.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Section = require("./Section")

local Tab = Class:extends("Tab")

function Tab:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.sections = {}
	self.scrollPosition = Runtime.Vector2.new(0, 0)

	local page = Builder.new("ScrollingFrame", {
		Name = "page",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = self.binder:resolve("border.strong"),
		CanvasSize = Runtime.UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Runtime.Enum.AutomaticSize.Y,
		ScrollingDirection = Runtime.Enum.ScrollingDirection.Y,
		Visible = false,
		ZIndex = 1,
	})
	page.Parent = self.options.Parent
	page.CanvasPosition = Runtime.Vector2.new(0, 0)
	self.page = page
	self._janitor:Add(page)

	local content = Builder.frame({
		Name = "content",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = 1,
	})
	content.Parent = page
	self.content = content
	self._janitor:Add(content)

	Builder.padding(Tokens.space.md).Parent = content
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, Tokens.space.md),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = content

	self._janitor:Add(self.binder:bind(page, "ScrollBarImageColor3", "border.strong"))
end

function Tab:Section(options: any)
	local copy = table.clone(options or {})
	copy.Parent = self.content
	copy.LayoutOrder = #self.sections + 1
	local section = Section.new(self.context, copy)
	table.insert(self.sections, section)
	self._janitor:Add(section)
	return section
end

function Tab:show()
	self.page.Visible = true
	self.page.CanvasPosition = self.scrollPosition
end

function Tab:hide()
	self.scrollPosition = self.page.CanvasPosition
	self.page.Visible = false
end

function Tab:isVisible(): boolean
	return self.page.Visible == true
end

return Tab
