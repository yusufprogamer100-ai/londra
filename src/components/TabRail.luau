--!strict
-- Tab rail. Active tab is marked by surface plus a brass seam on the leading
-- edge, not by colour alone, so the state survives a monochrome display.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Log = require("../core/Log")

local TabRail = Class:extends("TabRail")

local function entryWidth(title: string): number
	return math.max(96, math.min(180, #tostring(title) * 7 + 32))
end

function TabRail:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.entries = {}
	self.active = 0
	self.mode = self.options.Mode or "left"

	local rail = Builder.new("ScrollingFrame", {
		Name = "TabRail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self.binder:resolve("border.hairline"),
		CanvasSize = Runtime.UDim2.fromOffset(0, 0),
		ZIndex = 2,
	})
	rail.Parent = self.options.Parent
	self.element = rail

	if self.mode == "top" then
		rail.AutomaticCanvasSize = Runtime.Enum.AutomaticSize.X
		rail.ScrollingDirection = Runtime.Enum.ScrollingDirection.X
		rail.Size = Runtime.UDim2.new(1, 0, 0, Tokens.row.titlebar)
		rail.ScrollBarThickness = 0
		Builder.new("UIListLayout", {
			FillDirection = Runtime.Enum.FillDirection.Horizontal,
			Padding = Runtime.UDim.new(0, 2),
			SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
		}).Parent = rail
	else
		rail.AutomaticCanvasSize = Runtime.Enum.AutomaticSize.Y
		rail.ScrollingDirection = Runtime.Enum.ScrollingDirection.Y
		rail.Size = Runtime.UDim2.new(0, Tokens.size.tabRail, 1, 0)
		Builder.padding(Tokens.space.sm).Parent = rail
		Builder.new("UIListLayout", {
			Padding = Runtime.UDim.new(0, 2),
			SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
		}).Parent = rail
	end

	self._janitor:Add(self.binder:bind(rail, "ScrollBarImageColor3", "border.hairline"))
	self._janitor:Add(self.binder:subscribe(function()
		self:render()
	end))
end

function TabRail:add(tab: any): number
	local index = #self.entries + 1
	local title = tab.options.Title or ("Tab " .. tostring(index))
	local top = self.mode == "top"

	local button = Builder.button({
		Name = "tab_" .. tostring(index),
		Size = top and Runtime.UDim2.fromOffset(entryWidth(title), Tokens.row.titlebar)
			or Runtime.UDim2.new(1, 0, 0, Tokens.row.tab),
		LayoutOrder = index,
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	Builder.corner(Tokens.radius.control).Parent = button
	button.Parent = self.element

	local bar = Builder.frame({
		Name = "seam",
		Size = top and Runtime.UDim2.new(1, -16, 0, 2) or Runtime.UDim2.new(0, 2, 1, -12),
		Position = top and Runtime.UDim2.new(0, 8, 1, -2) or Runtime.UDim2.new(0, 0, 0, 6),
		BackgroundColor3 = self.binder:resolve("accent.base"),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	bar.Parent = button

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.new(1, top and -16 or -36, 1, 0),
		Position = Runtime.UDim2.new(0, top and 8 or 14, 0, 0),
		Text = (tab.options.Icon ~= nil and tostring(tab.options.Icon) .. "  " or "") .. title,
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	label.Parent = button

	local badge = nil
	if tab.options.Badge ~= nil then
		badge = Builder.label({
			Name = "badge",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, -10, 0.5, 0),
			Size = Runtime.UDim2.fromOffset(0, 14),
			AutomaticSize = Runtime.Enum.AutomaticSize.X,
			Text = tostring(tab.options.Badge),
			TextColor3 = self.binder:resolve("accent.base"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamBold,
			ZIndex = 5,
		})
		badge.Parent = button
	end

	local entry = {
		tab = tab,
		button = button,
		label = label,
		badge = badge,
		bar = bar,
		alive = true,
	}
	table.insert(self.entries, entry)
	self._janitor:Add(button)

	local rail = self
	button.MouseEnter:Connect(function()
		if rail.active == index then
			return
		end
		Motion.tween(button, { BackgroundTransparency = 0 }, { duration = Motion.duration("state") })
		button.BackgroundColor3 = rail.binder:resolve("state.hover")
	end)
	button.MouseLeave:Connect(function()
		if rail.active == index then
			return
		end
		Motion.tween(button, { BackgroundTransparency = 1 }, { duration = Motion.duration("state") })
	end)
	button.MouseButton1Down:Connect(function()
		if rail.active ~= index then
			button.BackgroundColor3 = rail.binder:resolve("state.pressed")
			button.BackgroundTransparency = 0
		end
	end)
	button.MouseButton1Click:Connect(function()
		rail:select(index)
	end)

	self:render()
	return index
end

function TabRail:render()
	for index, entry in ipairs(self.entries) do
		local active = index == self.active
		entry.label.TextColor3 = self.binder:resolve(active and "text.primary" or "text.secondary")
		entry.bar.BackgroundColor3 = self.binder:resolve("accent.base")
		entry.bar.BackgroundTransparency = active and 0 or 1
		if active then
			entry.button.BackgroundColor3 = self.binder:resolve("surface.raised")
			entry.button.BackgroundTransparency = 0
		else
			entry.button.BackgroundTransparency = 1
		end
	end
end

function TabRail:select(index: number): boolean
	if index < 1 or index > #self.entries then
		Log.warn("TabRail:select out of range: %s", tostring(index))
		return false
	end
	if self.active == index then
		return true
	end
	if self.active > 0 then
		local previous = self.entries[self.active]
		if previous ~= nil then
			previous.tab:hide()
		end
	end
	self.active = index
	local entry = self.entries[index]
	entry.tab:show()
	self:render()
	if self.options.OnSelect ~= nil then
		self.options.OnSelect(index, entry.tab)
	end
	return true
end

function TabRail:count(): number
	return #self.entries
end

return TabRail
