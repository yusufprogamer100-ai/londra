--!strict
-- Data grid. Rows live in a virtual list, so a thousand records cost the same
-- number of instances as ten. Sorting is stable: equal keys keep input order.

local Base = require("./Base")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local VirtualList = require("../ui/VirtualList")
local Log = require("../core/Log")

local Table = Base:extends("Table")

local HEADER_HEIGHT = 28
local DEFAULT_ROW_HEIGHT = 28
local DEFAULT_MAX_HEIGHT = 240

local function alignEnum(name: string?): any
	if name == "right" then
		return Runtime.Enum.TextXAlignment.Right
	elseif name == "center" then
		return Runtime.Enum.TextXAlignment.Center
	end
	return Runtime.Enum.TextXAlignment.Left
end

function Table:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	self.columns = config.Columns or {}
	self.rows = config.Rows or {}
	self.rowHeight = config.RowHeight or DEFAULT_ROW_HEIGHT
	self.maxHeight = config.MaxHeight or DEFAULT_MAX_HEIGHT
	self.emptyText = config.EmptyText or "No records"
	self.sortKey = nil
	self.sortAsc = true
	self.loading = false
	self.error = nil

	local frame = Builder.frame({
		Name = "table",
		Size = Runtime.UDim2.new(1, 0, 0, HEADER_HEIGHT + self.maxHeight),
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame
	self.frame = frame

	local header = Builder.frame({
		Name = "header",
		Size = Runtime.UDim2.new(1, 0, 0, HEADER_HEIGHT),
		ZIndex = 2,
	})
	header.Parent = frame
	self:theme(header, "BackgroundColor3", "surface.sunken")
	self.header = header

	local offset = 0
	self.headerCells = {}
	for index, column in ipairs(self.columns) do
		local width = column.Width or 120
		local cell = Builder.button({
			Name = "column_" .. tostring(column.Key or index),
			Position = Runtime.UDim2.fromOffset(offset, 0),
			Size = Runtime.UDim2.fromOffset(width, HEADER_HEIGHT),
			BackgroundTransparency = 1,
			ZIndex = 3,
		})
		cell.Parent = header

		local label = Builder.label({
			Name = "label",
			Size = Runtime.UDim2.new(1, -16, 1, 0),
			Position = Runtime.UDim2.fromOffset(8, 0),
			Text = column.Title or tostring(column.Key or ""),
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			TextXAlignment = alignEnum(column.Align),
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 4,
		})
		label.Parent = cell
		self:theme(label, "TextColor3", "text.secondary")

		local arrow = Builder.label({
			Name = "arrow",
			AnchorPoint = Runtime.Vector2.new(1, 0.5),
			Position = Runtime.UDim2.new(1, -4, 0.5, 0),
			Size = Runtime.UDim2.fromOffset(12, 14),
			Text = "",
			TextColor3 = self.binder:resolve("accent.base"),
			TextSize = 10,
			Font = Runtime.Enum.Font.GothamBold,
			ZIndex = 4,
		})
		arrow.Parent = cell
		self:theme(arrow, "TextColor3", "accent.base")

		if column.Sortable ~= false then
			self:track(cell.MouseButton1Click:Connect(function()
				self:sortBy(column.Key)
			end))
		end

		table.insert(self.headerCells, { column = column, cell = cell, label = label, arrow = arrow })
		offset += width
	end

	local body = Builder.frame({
		Name = "body",
		Position = Runtime.UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = Runtime.UDim2.new(1, 0, 1, -HEADER_HEIGHT),
		ZIndex = 1,
	})
	body.Parent = frame
	self.body = body

	local list = VirtualList.new(self.context, {
		Parent = body,
		Size = Runtime.UDim2.fromScale(1, 1),
		RowHeight = self.rowHeight,
		Buffer = 2,
		ZIndex = 2,
		CreateRow = function()
			return self:createRow()
		end,
	})
	self.list = list

	self.empty = Builder.label({
		Name = "empty",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.new(1, -24, 0, 20),
		Text = self.emptyText,
		TextColor3 = self.binder:resolve("text.muted"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
	})
	self.empty.Parent = body
	self:theme(self.empty, "TextColor3", "text.muted")

	self.errorLabel = Builder.label({
		Name = "error",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.new(1, -24, 0, 20),
		Text = "",
		TextColor3 = self.binder:resolve("state.danger"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
	})
	self.errorLabel.Parent = body
	self:theme(self.errorLabel, "TextColor3", "state.danger")

	if config.Retry ~= nil then
		local retry = Builder.button({
			Name = "retry",
			AnchorPoint = Runtime.Vector2.new(0.5, 0),
			Position = Runtime.UDim2.new(0.5, 0, 0.5, 16),
			Size = Runtime.UDim2.fromOffset(96, 24),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			Text = "Retry",
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			Visible = false,
			ZIndex = 4,
		})
		Builder.corner(self.tokens.radius.control).Parent = retry
		retry.Parent = body
		self:theme(retry, "BackgroundColor3", "surface.sunken")
		self:theme(retry, "TextColor3", "text.primary")
		self:track(retry.MouseButton1Click:Connect(function()
			if config.Retry ~= nil then
				config.Retry()
			end
		end))
		self.retry = retry
	end

	self:track(self.binder:subscribe(function()
		self:renderRows()
	end))

	self:SetRows(self.rows)
end

function Table:createRow(): any
	local row = { element = nil, item = nil, index = 0 }
	local frame = Builder.button({
		Name = "row",
		Size = Runtime.UDim2.new(1, 0, 0, self.rowHeight),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	Builder.corner(4).Parent = frame
	row.element = frame

	local offset = 0
	row.cells = {}
	row.skeletons = {}
	for index, column in ipairs(self.columns) do
		local width = column.Width or 120
		local label = Builder.label({
			Name = "cell_" .. tostring(column.Key or index),
			Position = Runtime.UDim2.fromOffset(offset, 0),
			Size = Runtime.UDim2.fromOffset(width, self.rowHeight),
			Text = "",
			TextColor3 = self.binder:resolve("text.primary"),
			TextSize = 12,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = alignEnum(column.Align),
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		label.Parent = frame
		self:theme(label, "TextColor3", "text.primary")
		table.insert(row.cells, label)

		local skeleton = Builder.frame({
			Name = "skeleton_" .. tostring(index),
			Position = Runtime.UDim2.fromOffset(offset + 4, self.rowHeight / 2 - 4),
			Size = Runtime.UDim2.fromOffset(math.max(24, width - 24), 8),
			Visible = false,
			ZIndex = 3,
		})
		Builder.corner(4).Parent = skeleton
		skeleton.Parent = frame
		self:theme(skeleton, "BackgroundColor3", "surface.sunken")
		table.insert(row.skeletons, skeleton)
		offset += width
	end

	frame.MouseEnter:Connect(function()
		frame.BackgroundTransparency = 0
		frame.BackgroundColor3 = self.binder:resolve("state.hover")
	end)
	frame.MouseLeave:Connect(function()
		frame.BackgroundTransparency = 1
	end)
	frame.MouseButton1Click:Connect(function()
		if row.item ~= nil and self.options.OnRowClick ~= nil then
			self.options.OnRowClick(row.item, row.index)
		end
	end)

	function row.setData(item, index)
		row.item = item
		row.index = index
		for cellIndex, column in ipairs(self.columns) do
			local label = row.cells[cellIndex]
			if self.loading then
				label.Visible = false
				row.skeletons[cellIndex].Visible = true
			else
				label.Visible = true
				row.skeletons[cellIndex].Visible = false
				local value = item ~= nil and item[column.Key] or ""
				label.Text = tostring(value)
			end
		end
	end

	return row
end

function Table:SetRows(rows: { any }?)
	self.rows = rows or {}
	self.error = nil
	self.loading = false
	self:applySort()
	self:renderRows()
end

function Table:SetLoading(value: boolean)
	self.loading = value == true
	if self.loading then
		self.error = nil
	end
	self:renderRows()
end

function Table:SetError(message: string?)
	self.error = message
	self.loading = false
	self:renderRows()
end

function Table:sortBy(key: any)
	if key == nil then
		return
	end
	if self.sortKey == key then
		self.sortAsc = not self.sortAsc
	else
		self.sortKey = key
		self.sortAsc = true
	end
	self:applySort()
	self:renderRows()
end

function Table:applySort()
	if self.sortKey == nil then
		return
	end
	local key = self.sortKey
	local ascending = self.sortAsc
	table.sort(self.rows, function(a, b)
		local left = a[key]
		local right = b[key]
		if left == right then
			return false
		end
		if type(left) == "number" and type(right) == "number" then
			return ascending and left < right or left > right
		end
		local leftText = string.lower(tostring(left))
		local rightText = string.lower(tostring(right))
		if leftText == rightText then
			return false
		end
		return ascending and leftText < rightText or leftText > rightText
	end)
end

function Table:renderRows()
	if self.list == nil then
		return
	end

	for _, entry in ipairs(self.headerCells) do
		local active = self.sortKey == entry.column.Key
		entry.arrow.Text = active and (self.sortAsc and "^" or "v") or ""
	end

	local visible = self.error == nil and not self.loading and #self.rows > 0
	self.list.frame.Visible = visible
	if self.loading then
		self.list.frame.Visible = true
		self.list:setItems({ 1, 2, 3 })
	elseif self.error ~= nil then
		self.list:setItems({})
	else
		self.list:setItems(self.rows)
	end

	self.empty.Visible = self.error == nil and not self.loading and #self.rows == 0
	self.empty.Text = self.emptyText
	self.errorLabel.Visible = self.error ~= nil
	self.errorLabel.Text = self.error or ""
	if self.retry ~= nil then
		self.retry.Visible = self.error ~= nil
	end

	local bodyHeight = self.maxHeight
	if not self.loading and self.error == nil then
		bodyHeight = math.min(self.maxHeight, math.max(self.rowHeight, #self.rows * self.rowHeight))
	end
	self.body.Size = Runtime.UDim2.new(1, 0, 1, -HEADER_HEIGHT)
	self.frame.Size = Runtime.UDim2.new(1, 0, 0, HEADER_HEIGHT + bodyHeight)
end

function Table:beforeDestroy()
	if self.list ~= nil then
		self.list:destroy()
		self.list = nil
	end
end

return Table
