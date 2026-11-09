--!strict
-- Eight resize handles. Size is clamped in pre-scale units so the limits match
-- what the user sees at any UI scale.

local Runtime = require("../core/Runtime")
local Builder = require("./Builder")
local Drag = require("./Drag")

local Resize = {}

local DIRECTIONS = {
	{ name = "left", x = -1, y = 0 },
	{ name = "right", x = 1, y = 0 },
	{ name = "top", x = 0, y = -1 },
	{ name = "bottom", x = 0, y = 1 },
	{ name = "topLeft", x = -1, y = -1 },
	{ name = "topRight", x = 1, y = -1 },
	{ name = "bottomLeft", x = -1, y = 1 },
	{ name = "bottomRight", x = 1, y = 1 },
}

local function handleSize(direction: any): any
	if direction.x ~= 0 and direction.y ~= 0 then
		return Runtime.UDim2.fromOffset(12, 12)
	end
	if direction.x ~= 0 then
		return Runtime.UDim2.new(0, 6, 1, 0)
	end
	return Runtime.UDim2.new(1, 0, 0, 6)
end

local function handlePosition(direction: any): any
	local x = 0.5
	local y = 0.5
	if direction.x == -1 then
		x = 0
	elseif direction.x == 1 then
		x = 1
	end
	if direction.y == -1 then
		y = 0
	elseif direction.y == 1 then
		y = 1
	end
	return Runtime.UDim2.fromScale(x, y)
end

function Resize.attach(janitor: any, window: any, options: any)
	local config = options or {}
	local minSize = config.minSize or Runtime.Vector2.new(520, 340)
	local maxSize = config.maxSize

	for _, direction in ipairs(DIRECTIONS) do
		local handle = Builder.frame({
			Name = "resize_" .. direction.name,
			Size = handleSize(direction),
			Position = handlePosition(direction),
			AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
			ZIndex = 10,
		})
		handle.Parent = window.frame

		local state = {
			startSize = nil,
			startPosition = nil,
		}

		Drag.attach(janitor, {
			scale = window.scale,
			hitTest = function(input)
				return Drag.inside(handle, input)
			end,
			onStart = function()
				state.startSize = window:getSize()
				state.startPosition = window:getPosition()
			end,
			onDrag = function(deltaX, deltaY)
				if state.startSize == nil then
					return
				end
				local width = state.startSize.X
				local height = state.startSize.Y
				local x = state.startPosition.X
				local y = state.startPosition.Y

				if direction.x ~= 0 then
					local change = deltaX * direction.x
					local newWidth = math.clamp(width + change, minSize.X, maxSize and maxSize.X or math.huge)
					if direction.x == -1 then
						x = state.startPosition.X + (width - newWidth)
					end
					width = newWidth
				end

				if direction.y ~= 0 then
					local change = deltaY * direction.y
					local newHeight = math.clamp(height + change, minSize.Y, maxSize and maxSize.Y or math.huge)
					if direction.y == -1 then
						y = state.startPosition.Y + (height - newHeight)
					end
					height = newHeight
				end

				window:setGeometry(x, y, width, height)
			end,
		})
	end
end

return Resize
