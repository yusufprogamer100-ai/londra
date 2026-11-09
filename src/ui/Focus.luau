--!strict
-- Focus chain per window. Tab order follows registration order, which follows
-- creation order, which follows visual order because sections are built top to
-- bottom.

local Runtime = require("../core/Runtime")
local Builder = require("./Builder")

local Focus = {}
Focus.__index = Focus

function Focus.new(binder: any)
	return setmetatable({
		binder = binder,
		items = {},
		current = nil,
	}, Focus)
end

function Focus:register(element: any, options: any?): any
	local item = {
		element = element,
		options = options or {},
		alive = true,
	}
	table.insert(self.items, item)

	local focus = self
	local handle = { Connected = true }
	function handle:Disconnect()
		if not item.alive then
			return
		end
		item.alive = false
		handle.Connected = false
		for index = #focus.items, 1, -1 do
			if focus.items[index] == item then
				table.remove(focus.items, index)
				break
			end
		end
		if focus.current == item then
			focus:clear()
		end
	end
	handle.item = item
	return handle
end

function Focus:clear()
	if self.current == nil then
		return
	end
	local item = self.current
	self.current = nil
	local ring = item.element:FindFirstChild("__londra_focus")
	if ring ~= nil then
		ring:Destroy()
	end
	if item.options.onBlur ~= nil then
		item.options.onBlur()
	end
end

function Focus:set(item: any)
	if item == nil or not item.alive then
		return
	end
	self:clear()
	self.current = item

	local ring = Builder.stroke(self.binder:resolve("focus.ring"), 2)
	ring.Name = "__londra_focus"
	ring.Parent = item.element

	if item.options.onFocus ~= nil then
		item.options.onFocus()
	end
end

function Focus:index(): number
	if self.current == nil then
		return 0
	end
	for index, item in ipairs(self.items) do
		if item == self.current then
			return index
		end
	end
	return 0
end

function Focus:move(step: number)
	local startIndex = self.trapStart or 1
	local count = #self.items - startIndex + 1
	if count <= 0 then
		return
	end
	local current = self:index()
	if current < startIndex then
		current = step > 0 and (startIndex - 1) or startIndex
	end
	local offset = current - startIndex + 1
	local nextOffset = ((offset - 1 + step) % count) + 1
	self:set(self.items[startIndex + nextOffset - 1])
end

function Focus:pushTrap(): any
	self.trapStart = #self.items + 1
	return { start = self.trapStart }
end

function Focus:popTrap()
	self.trapStart = nil
end

function Focus:next()
	self:move(1)
end

function Focus:previous()
	self:move(-1)
end

function Focus:activate()
	local item = self.current
	if item ~= nil and item.options.onActivate ~= nil then
		item.options.onActivate()
	end
end

function Focus:adjust(direction: number)
	local item = self.current
	if item ~= nil and item.options.onAdjust ~= nil then
		item.options.onAdjust(direction)
	end
end

function Focus:destroy()
	self:clear()
	table.clear(self.items)
end

return Focus
