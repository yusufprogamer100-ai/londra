--!strict
-- Section owns a header and a vertical stack of rows. Height is automatic:
-- callers pass content, never pixel heights that rot when a font changes.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Scheduler = require("../core/Scheduler")
local Log = require("../core/Log")

local Toggle = require("./Toggle")
local Button = require("./Button")
local Label = require("./Label")
local Paragraph = require("./Paragraph")
local Divider = require("./Divider")
local Space = require("./Space")
local Badge = require("./Badge")
local Slider = require("./Slider")
local Textbox = require("./Textbox")
local Dropdown = require("./Dropdown")
local Keybind = require("./Keybind")

local Section = Class:extends("Section")

local HEADER_HEIGHT = 30
local HEADER_HEIGHT_DESCRIPTION = 44

function Section:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.components = {}
	self.collapsed = self.options.Collapsed == true
	self.expandedHeight = nil

	local config = self.options
	local hasDescription = config.Description ~= nil
	local headerHeight = hasDescription and HEADER_HEIGHT_DESCRIPTION or HEADER_HEIGHT

	local frame = Builder.frame({
		Name = "section",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		BackgroundColor3 = self.binder:resolve("surface.raised"),
		ZIndex = 1,
	})
	Builder.corner(Tokens.radius.section).Parent = frame
	Builder.padding(Tokens.space.md).Parent = frame
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, Tokens.space.sm),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = frame
	frame.Parent = config.Parent
	self.element = frame
	self.surfaceToken = config.Surface or "surface.raised"
	self:bind(frame, "BackgroundColor3", self.surfaceToken)

	local header = Builder.frame({
		Name = "header",
		LayoutOrder = 1,
		Size = Runtime.UDim2.new(1, 0, 0, headerHeight),
		ZIndex = 2,
	})
	header.Parent = frame
	self.header = header

	local title = Builder.label({
		Name = "title",
		Size = Runtime.UDim2.new(1, -24, 0, hasDescription and 18 or headerHeight),
		Position = Runtime.UDim2.new(0, 0, 0, hasDescription and 4 or 0),
		Text = config.Title or "Section",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	title.Parent = header
	self:bind(title, "TextColor3", "text.primary")

	if hasDescription then
		local description = Builder.label({
			Name = "description",
			Size = Runtime.UDim2.new(1, -24, 0, 16),
			Position = Runtime.UDim2.new(0, 0, 0, 22),
			Text = config.Description,
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 11,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		description.Parent = header
		self:bind(description, "TextColor3", "text.muted")
	end

	local content = Builder.frame({
		Name = "content",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = 2,
	})
	content.Parent = frame
	self.content = content
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 2),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = content

	if config.Collapsible == true then
		local arrow = Builder.button({
			Name = "collapse",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, 0, 0, hasDescription and 22 or headerHeight / 2),
			Size = Runtime.UDim2.fromOffset(20, 20),
			Text = self.collapsed and "▸" or "▾",
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 12,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = 4,
		})
		arrow.Parent = header
		self:bind(arrow, "TextColor3", "text.muted")
		self.arrow = arrow
		arrow.MouseButton1Click:Connect(function()
			self:setCollapsed(not self.collapsed)
		end)
	else
		self:setCollapsed(self.collapsed, false)
	end

	if config.Badge ~= nil then
		local badge = Badge.new(context, {
			Text = config.Badge,
			Variant = config.BadgeVariant or "neutral",
			Parent = header,
			ZIndex = 5,
		})
		badge.element.AnchorPoint = Runtime.Vector2.new(1, 0.5)
		badge.element.Position = Runtime.UDim2.new(1, config.Collapsible == true and -24 or 0, 0, hasDescription and 22 or headerHeight / 2)
		self:track(badge)
	end
end

function Section:bind(instance: any, property: string, token: string)
	self._janitor:Add(self.binder:bind(instance, property, token))
end

function Section:track(component: any)
	table.insert(self.components, component)
	self._janitor:Add(component)
	return component
end

function Section:add(component: any)
	table.insert(self.components, component)
	return component
end

local function childOptions(self: any, options: any): any
	local copy = table.clone(options or {})
	copy.Parent = self.content
	copy.LayoutOrder = #self.components + 1
	return copy
end

function Section:Toggle(options: any)
	return self:track(Toggle.new(self.context, childOptions(self, options)))
end

function Section:Button(options: any)
	return self:track(Button.new(self.context, childOptions(self, options)))
end

function Section:Label(options: any)
	return self:track(Label.new(self.context, childOptions(self, options)))
end

function Section:Paragraph(options: any)
	return self:track(Paragraph.new(self.context, childOptions(self, options)))
end

function Section:Divider(options: any)
	return self:track(Divider.new(self.context, childOptions(self, options)))
end

function Section:Space(options: any)
	return self:track(Space.new(self.context, childOptions(self, options)))
end

function Section:Badge(options: any)
	return self:track(Badge.new(self.context, childOptions(self, options)))
end

function Section:Slider(options: any)
	return self:track(Slider.new(self.context, childOptions(self, options)))
end

function Section:Textbox(options: any)
	return self:track(Textbox.new(self.context, childOptions(self, options)))
end

function Section:Dropdown(options: any)
	return self:track(Dropdown.new(self.context, childOptions(self, options)))
end

function Section:Keybind(options: any)
	return self:track(Keybind.new(self.context, childOptions(self, options)))
end

function Section:ColorPicker(options: any)
	return self:track(ColorPicker.new(self.context, childOptions(self, options)))
end

function Section:RangeSlider(options: any)
	return self:track(RangeSlider.new(self.context, childOptions(self, options)))
end

function Section:Groupbox(options: any)
	local copy = table.clone(options or {})
	copy.Parent = self.content
	copy.LayoutOrder = #self.components + 1
	copy.Depth = 1
	copy.Surface = "surface.sunken"
	local group = Section.new(self.context, copy)
	group.element:FindFirstChild("UICorner").CornerRadius = Runtime.UDim.new(0, Tokens.radius.control)
	return self:track(group)
end

function Section:setCollapsed(value: boolean, animate: boolean?)
	if self.collapsed == value and animate ~= false then
		return
	end
	self.collapsed = value
	if self.arrow ~= nil then
		self.arrow.Text = value and "▸" or "▾"
	end

	local content = self.content
	local duration = animate == false and 0 or Motion.duration("open")

	if value then
		local height = content.AbsoluteSize.Y
		if height <= 0 then
			content.Visible = false
			return
		end
		self.expandedHeight = height
		content.AutomaticSize = Runtime.Enum.AutomaticSize.None
		content.Size = Runtime.UDim2.new(1, 0, 0, height)
		content.ClipsDescendants = true
		Motion.tween(content, { Size = Runtime.UDim2.new(1, 0, 0, 0) }, { duration = duration })
		if duration <= 0 then
			content.Visible = false
			content.ClipsDescendants = false
			content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
		else
			Scheduler:after(duration, function()
				if self.collapsed then
					content.Visible = false
					content.ClipsDescendants = false
					content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
				end
			end)
		end
		return
	end

	local height = self.expandedHeight or 0
	content.Visible = true
	content.AutomaticSize = Runtime.Enum.AutomaticSize.None
	content.Size = Runtime.UDim2.new(1, 0, 0, duration <= 0 and height or 0)
	content.ClipsDescendants = true
	Motion.tween(content, { Size = Runtime.UDim2.new(1, 0, 0, height) }, { duration = duration })
	if duration <= 0 then
		content.ClipsDescendants = false
		content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
	else
		Scheduler:after(duration, function()
			if not self.collapsed then
				content.ClipsDescendants = false
				content.AutomaticSize = Runtime.Enum.AutomaticSize.Y
			end
		end)
	end
end

function Section:setEnabled(value: boolean)
	self.enabled = value
	for _, component in ipairs(self.components) do
		if component.setEnabled ~= nil then
			component:setEnabled(value)
		end
	end
end

return Section
