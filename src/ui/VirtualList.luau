--!strict
-- Virtual list. Only the visible rows plus a small buffer exist as instances,
-- so a dropdown with a thousand entries costs the same as one with ten.

local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")

local VirtualList = {}
VirtualList.__index = VirtualList

function VirtualList.new(context: any, options: any)
	local config = options or {}
	local self = setmetatable({
		context = context,
		rowHeight = config.RowHeight or 24,
		buffer = config.Buffer or 2,
		items = {},
		pool = {},
		createRow = config.CreateRow,
	}, VirtualList)

	local frame = Builder.new("ScrollingFrame", {
		Name = config.Name or "VirtualList",
		Size = config.Size or Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = context.binder:resolve("border.strong"),
		CanvasSize = Runtime.UDim2.fromOffset(0, 0),
		ScrollingDirection = Runtime.Enum.ScrollingDirection.Y,
		ZIndex = config.ZIndex or 2,
	})
	frame.Parent = config.Parent
	self.frame = frame

	self._janitor = context.janitor
	self._connections = {}
	self._connections[#self._connections + 1] = frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:refresh()
	end)
	self._connections[#self._connections + 1] = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:refresh()
	end)

	return self
end

function VirtualList:setItems(items: { any })
	self.items = items or {}
	self.frame.CanvasSize = Runtime.UDim2.fromOffset(0, #self.items * self.rowHeight)
	self.frame.CanvasPosition = Runtime.Vector2.new(0, 0)
	self:refresh()
end

function VirtualList:refresh()
	local height = self.frame.AbsoluteSize.Y
	if height <= 0 then
		height = 120
	end
	local visible = math.max(1, math.ceil(height / self.rowHeight))
	local first = math.max(1, math.floor(self.frame.CanvasPosition.Y / self.rowHeight) + 1 - self.buffer)
	local last = math.min(#self.items, first + visible + self.buffer * 2)
	local needed = math.max(0, last - first + 1)

	while #self.pool < needed do
		local row = self.createRow(#self.pool + 1)
		row.element.Parent = self.frame
		table.insert(self.pool, row)
	end

	for index, row in ipairs(self.pool) do
		if index <= needed then
			local itemIndex = first + index - 1
			local item = self.items[itemIndex]
			row.element.Visible = true
			row.element.Position = Runtime.UDim2.fromOffset(0, (itemIndex - 1) * self.rowHeight)
			row.element.Size = Runtime.UDim2.new(1, 0, 0, self.rowHeight)
			row.setData(item, itemIndex)
		else
			row.element.Visible = false
		end
	end
end

function VirtualList:destroy()
	for _, connection in ipairs(self._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._connections)
	for _, row in ipairs(self.pool) do
		row.element:Destroy()
	end
	table.clear(self.pool)
	self.frame:Destroy()
end

return VirtualList
