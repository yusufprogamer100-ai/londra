--!strict
-- Resource ownership. Every connection, tween handle, instance and cleanup
-- function a component creates is added here. Cleanup runs LIFO so children are
-- never destroyed after their parent.

local Runtime = require("./Runtime")

local Janitor = {}
Janitor.__index = Janitor

local TASK_INSTANCE = "instance"
local TASK_CONNECTION = "connection"
local TASK_FUNCTION = "function"
local TASK_OBJECT = "object"

function Janitor.new()
	return setmetatable({
		_tasks = {},
		_owned = {},
		_cleaned = false,
	}, Janitor)
end

local function kindOf(item: any): string?
	if item == nil then
		return nil
	end
	if type(item) == "function" then
		return TASK_FUNCTION
	end
	if type(item) == "table" then
		if item.Destroy ~= nil or item.Clean ~= nil or item.Disconnect ~= nil or item.Cancel ~= nil then
			return TASK_OBJECT
		end
		return nil
	end
	local ok, itemType = pcall(function()
		return Runtime.typeof(item)
	end)
	if ok and itemType == "Instance" then
		return TASK_INSTANCE
	end
	if ok and itemType == "RBXScriptConnection" then
		return TASK_CONNECTION
	end
	return nil
end

function Janitor:Add(item: any, cleanup: (() -> ())?): any
	if item == nil then
		return nil
	end

	if cleanup ~= nil then
		table.insert(self._tasks, { kind = TASK_FUNCTION, value = cleanup })
		return item
	end

	local kind = kindOf(item)
	if kind == nil then
		return nil
	end

	if self._owned[item] then
		return item
	end
	self._owned[item] = true
	table.insert(self._tasks, { kind = kind, value = item })
	return item
end

function Janitor:Remove(item: any)
	for index = #self._tasks, 1, -1 do
		if self._tasks[index].value == item then
			table.remove(self._tasks, index)
			self._owned[item] = nil
			return
		end
	end
end

function Janitor:Link(other: any)
	if other == nil then
		return
	end
	table.insert(self._tasks, {
		kind = TASK_FUNCTION,
		value = function()
			other:Destroy()
		end,
	})
end

function Janitor:Clean()
	if self._cleaned then
		return
	end
	self._cleaned = true

	for index = #self._tasks, 1, -1 do
		local task = self._tasks[index]
		self._tasks[index] = nil
		local value = task.value
		if task.kind == TASK_INSTANCE then
			pcall(function()
				value:Destroy()
			end)
		elseif task.kind == TASK_CONNECTION then
			pcall(function()
				value:Disconnect()
			end)
		elseif task.kind == TASK_FUNCTION then
			pcall(value)
		elseif task.kind == TASK_OBJECT then
			pcall(function()
				if value.Destroy ~= nil then
					value:Destroy()
				elseif value.Clean ~= nil then
					value:Clean()
				elseif value.Disconnect ~= nil then
					value:Disconnect()
				elseif value.Cancel ~= nil then
					value:Cancel()
				end
			end)
		end
	end

	table.clear(self._tasks)
	table.clear(self._owned)
end

function Janitor:Destroy()
	self:Clean()
end

function Janitor:Count(): number
	return #self._tasks
end

return Janitor
