--!strict
-- Dropdown. The panel lives on the popup layer, outside the window clip, and
-- long option lists are virtualised through the shared list helper.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Input = require("../ui/Input")
local VirtualList = require("../ui/VirtualList")
local Log = require("../core/Log")

local Dropdown = Base:extends("Dropdown")

function Dropdown:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.key = config.Key
	self.values = config.Values or {}
	self.multi = config.Multi == true
	self.open = false
	self.highlight = 0
	self.filtered = self.values

	if self.key == nil then
		Log.warn("Dropdown: missing Key, control will not persist")
	end

	local layout = Row.build(context, {
		title = config.Title or "Select",
		description = config.Description,
		clickable = true,
		controlWidth = config.ControlWidth or 200,
	})
	self.element = layout.row
	self.element.Parent = config.Parent
	self.layout = layout

	local value = Builder.label({
		Name = "value",
		Size = Runtime.UDim2.new(1, -20, 1, 0),
		Text = "",
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Right,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	value.Parent = layout.control
	self:theme(value, "TextColor3", "text.secondary")
	self.valueLabel = value

	local chevron = Builder.label({
		Name = "chevron",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.fromOffset(14, 20),
		Text = "v",
		TextColor3 = self.binder:resolve("text.muted"),
		TextSize = 10,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = 3,
	})
	chevron.Parent = layout.control
	self:theme(chevron, "TextColor3", "text.muted")
	self.chevron = chevron

	if self.key ~= nil and not context.flags:Has(self.key) then
		local fallback = config.Default
		if fallback == nil then
			fallback = self.multi and {} or nil
		end
		if fallback ~= nil then
			context.flags:Set(self.key, fallback)
		end
	end
	if self.key ~= nil then
		self:track(context.flags:OnChanged(self.key, function()
			self:render()
			if self.open then
				self:refreshRows()
			end
		end))
	end
	self:track(self.binder:subscribe(function()
		self:render()
		if self.open then
			self:refreshRows()
		end
	end))

	self:track(self.element.MouseButton1Click:Connect(function()
		if not self.enabled then
			return
		end
		if self.open then
			self:close()
		else
			self:openPanel()
		end
	end))

	if self.focus ~= nil then
		self.focus:register(self.element, {
			onActivate = function()
				if self.open then
					self:close()
				else
					self:openPanel()
				end
			end,
		})
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
	self:render()
end

function Dropdown:selection(): any
	if self.key == nil then
		return self.options.Default
	end
	return self.context.flags:Get(self.key, self.options.Default)
end

function Dropdown:isSelected(value: any): boolean
	local selection = self:selection()
	if self.multi then
		if type(selection) ~= "table" then
			return false
		end
		for _, item in ipairs(selection) do
			if item == value then
				return true
			end
		end
		return false
	end
	return selection == value
end

function Dropdown:render()
	local selection = self:selection()
	local text = self.options.Placeholder or "Select"
	if self.multi and type(selection) == "table" then
		if #selection > 0 then
			local parts = {}
			for _, item in ipairs(selection) do
				table.insert(parts, tostring(item))
			end
			text = table.concat(parts, ", ")
		end
	elseif selection ~= nil then
		text = tostring(selection)
	end
	self.valueLabel.Text = text
	self.chevron.Text = self.open and "^" or "v"
end

function Dropdown:openPanel()
	if self.open then
		return
	end
	self.open = true
	self.highlight = 0
	self.filtered = self.values
	self:render()

	local layers = self.context.root.layers
	local catcher = Builder.button({
		Name = "dropdown_catcher",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = layers:next("popup"),
	})
	catcher.Parent = layers:frame("popup")
	self.catcher = catcher

	local panel = Builder.frame({
		Name = "dropdown_panel",
		BackgroundColor3 = self.binder:resolve("surface.raised"),
		ZIndex = layers:next("popup"),
		ClipsDescendants = true,
	})
	Builder.corner(6).Parent = panel
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = panel
	panel.Parent = layers:frame("popup")
	self.panel = panel
	self:theme(panel, "BackgroundColor3", "surface.raised")

	local searchHeight = 0
	if self.options.Search ~= false then
		searchHeight = 30
		local search = Builder.new("TextBox", {
			Name = "search",
			Position = Runtime.UDim2.fromOffset(4, 4),
			Size = Runtime.UDim2.new(1, -8, 0, 24),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			TextColor3 = self.binder:resolve("text.primary"),
			PlaceholderColor3 = self.binder:resolve("text.muted"),
			PlaceholderText = "Search",
			Text = "",
			TextSize = 11,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			ZIndex = panel.ZIndex + 1,
		})
		Builder.corner(4).Parent = search
		search.Parent = panel
		self:theme(search, "BackgroundColor3", "surface.sunken")
		self:theme(search, "TextColor3", "text.primary")
		self:theme(search, "PlaceholderColor3", "text.muted")
		self.search = search

		self:track(search.Focused:Connect(function()
			Input.suspend()
		end))
		self:track(search.FocusLost:Connect(function()
			Input.resume()
		end))
		self:track(search.TextChanged:Connect(function()
			self:filter(search.Text)
		end))
	end

	local list = VirtualList.new(self.context, {
		Parent = panel,
		Size = Runtime.UDim2.new(1, -8, 1, -(searchHeight + 8)),
		RowHeight = 24,
		Buffer = 2,
		ZIndex = panel.ZIndex + 1,
		CreateRow = function()
			local button = Builder.button({
				Name = "option",
				Size = Runtime.UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				ZIndex = panel.ZIndex + 1,
			})
			Builder.corner(4).Parent = button
			local label = Builder.label({
				Size = Runtime.UDim2.new(1, -16, 1, 0),
				Position = Runtime.UDim2.fromOffset(8, 0),
				TextColor3 = self.binder:resolve("text.primary"),
				TextSize = 12,
				Font = Runtime.Enum.Font.Gotham,
				TextXAlignment = Runtime.Enum.TextXAlignment.Left,
				TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
				ZIndex = panel.ZIndex + 2,
			})
			label.Parent = button
			local row = { element = button, item = nil }
			button.MouseButton1Click:Connect(function()
				if row.item ~= nil then
					self:choose(row.item)
				end
			end)
			button.MouseEnter:Connect(function()
				button.BackgroundTransparency = 0
				button.BackgroundColor3 = self.binder:resolve("state.hover")
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundTransparency = 1
			end)
			function row.setData(item, index)
				row.item = item
				label.Text = tostring(item)
				local selected = self:isSelected(item)
				label.TextColor3 = self.binder:resolve(selected and "accent.base" or "text.primary")
				button.BackgroundTransparency = 1
				if index == self.highlight then
					button.BackgroundTransparency = 0
					button.BackgroundColor3 = self.binder:resolve("state.hover")
				end
			end
			return row
		end,
	})
	self.list = list
	list.frame.Position = Runtime.UDim2.fromOffset(4, searchHeight + 4)
	list:setItems(self.filtered)

	self:positionPanel()

	self:track(catcher.MouseButton1Click:Connect(function()
		self:close()
	end))

	local captureHandler
	captureHandler = function(input)
		if not self.open then
			return
		end
		local key = input.KeyCode
		if key == Runtime.Enum.KeyCode.Escape then
			self:close()
			return
		end
		if key == Runtime.Enum.KeyCode.Up then
			self.highlight = math.max(1, self.highlight - 1)
		elseif key == Runtime.Enum.KeyCode.Down then
			self.highlight = math.min(#self.filtered, self.highlight + 1)
		elseif key == Runtime.Enum.KeyCode.Return then
			local item = self.filtered[self.highlight]
			if item ~= nil then
				self:choose(item)
			end
			return
		end
		self:refreshRows()
		self.capture = Input.capture(captureHandler)
	end
	self.capture = Input.capture(captureHandler)
end

function Dropdown:positionPanel()
	if self.panel == nil then
		return
	end
	local control = self.layout.control
	local width = math.max(180, control.AbsoluteSize.X)
	local height = math.min(self.options.MaxHeight or 220, math.max(1, #self.filtered) * 24 + 8)
	if self.search ~= nil then
		height = height + 30
	end
	height = math.min(height, self.options.MaxHeight or 220)
	self.panel.Size = Runtime.UDim2.fromOffset(width, height)
	self.panel.Position = Runtime.UDim2.fromOffset(
		control.AbsolutePosition.X,
		control.AbsolutePosition.Y + control.AbsoluteSize.Y + 4
	)
	if self.list ~= nil then
		self.list.frame.Size = Runtime.UDim2.new(1, -8, 1, -((self.search ~= nil and 30 or 0) + 8))
	end
end

function Dropdown:filter(query: string)
	local needle = string.lower(tostring(query))
	if needle == "" then
		self.filtered = self.values
	else
		local filtered = {}
		for _, item in ipairs(self.values) do
			if string.find(string.lower(tostring(item)), needle, 1, true) ~= nil then
				table.insert(filtered, item)
			end
		end
		self.filtered = filtered
	end
	self.highlight = 0
	self:positionPanel()
	if self.list ~= nil then
		self.list:setItems(self.filtered)
	end
end

function Dropdown:refreshRows()
	if self.list ~= nil then
		self.list:refresh()
	end
end

function Dropdown:choose(item: any)
	if self.multi then
		local current = self:selection()
		local nextSelection = {}
		local found = false
		if type(current) == "table" then
			for _, value in ipairs(current) do
				if value == item then
					found = true
				else
					table.insert(nextSelection, value)
				end
			end
		end
		if not found then
			table.insert(nextSelection, item)
		end
		if self.key ~= nil then
			self.context.flags:Set(self.key, nextSelection)
		end
		self:render()
		self:refreshRows()
	else
		if self.key ~= nil then
			self.context.flags:Set(self.key, item)
		end
		self:render()
		self:close()
	end
	if self.options.OnChanged ~= nil then
		self.options.OnChanged(self:selection())
	end
end

function Dropdown:close()
	if not self.open then
		return
	end
	self.open = false
	if self.capture ~= nil then
		self.capture:Cancel()
		self.capture = nil
	end
	if self.search ~= nil then
		Input.resume()
	end
	if self.list ~= nil then
		self.list:destroy()
		self.list = nil
	end
	if self.panel ~= nil then
		self.panel:Destroy()
		self.panel = nil
	end
	if self.catcher ~= nil then
		self.catcher:Destroy()
		self.catcher = nil
	end
	self.search = nil
	self:render()
end

function Dropdown:beforeDestroy()
	self:close()
end

function Dropdown:setEnabled(value: boolean)
	self.enabled = value
	self.element.Active = value
end

return Dropdown
