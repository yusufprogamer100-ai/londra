--!strict
-- Pointer drag with capture. Delta is divided by the UI scale, because pointer
-- coordinates are screen pixels while Position offsets are pre-scale units.

local Runtime = require("../core/Runtime")

local Drag = {}

local function point(input: any): any
	return Runtime.Vector2.new(input.Position.X, input.Position.Y)
end

function Drag.attach(janitor: any, options: any): any
	local userInput = Runtime.service("UserInputService")
	local state = {
		dragging = false,
		startPointer = nil,
		started = false,
	}

	local scale = options.scale or 1

	local function start(input: any)
		if options.hitTest ~= nil and not options.hitTest(input) then
			return false
		end
		state.dragging = true
		state.startPointer = point(input)
		if options.onStart ~= nil then
			options.onStart(point(input))
		end
		return true
	end

	janitor:Add(userInput.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local inputType = input.UserInputType
		if inputType ~= Runtime.Enum.UserInputType.MouseButton1 and inputType ~= Runtime.Enum.UserInputType.Touch then
			return
		end
		start(input)
	end))

	janitor:Add(userInput.InputChanged:Connect(function(input, processed)
		if not state.dragging then
			return
		end
		if processed and options.force ~= true then
			return
		end
		local current = point(input)
		local deltaX = (current.X - state.startPointer.X) / scale
		local deltaY = (current.Y - state.startPointer.Y) / scale
		if options.onDrag ~= nil then
			options.onDrag(deltaX, deltaY, current)
		end
	end))

	janitor:Add(userInput.InputEnded:Connect(function(input)
		if not state.dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType ~= Runtime.Enum.UserInputType.MouseButton1 and inputType ~= Runtime.Enum.UserInputType.Touch then
			return
		end
		state.dragging = false
		if options.onEnd ~= nil then
			options.onEnd(point(input))
		end
	end))

	return {
		isDragging = function()
			return state.dragging
		end,
		cancel = function()
			state.dragging = false
		end,
	}
end

function Drag.inside(element: any, input: any): boolean
	local position = input.Position
	local absolute = element.AbsolutePosition
	local size = element.AbsoluteSize
	return position.X >= absolute.X
		and position.X <= absolute.X + size.X
		and position.Y >= absolute.Y
		and position.Y <= absolute.Y + size.Y
end

return Drag
