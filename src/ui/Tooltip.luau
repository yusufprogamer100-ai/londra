--!strict
-- Tooltip. One instance for the whole library, delayed, clamped to the viewport.
-- A tooltip never opens a second tooltip.

local Runtime = require("../core/Runtime")
local Builder = require("./Builder")
local Scheduler = require("../core/Scheduler")

local Tooltip = {}

local active = nil
local timer = nil

local function viewport(): any
	local camera = Runtime.workspace and Runtime.workspace.CurrentCamera or nil
	if camera ~= nil and camera.ViewportSize ~= nil then
		return camera.ViewportSize
	end
	return Runtime.Vector2.new(1920, 1080)
end

local function destroy()
	if timer ~= nil then
		timer:Cancel()
		timer = nil
	end
	if active ~= nil then
		active:Destroy()
		active = nil
	end
end

function Tooltip.hide()
	destroy()
end

function Tooltip.show(context: any, element: any, text: string)
	if text == nil or text == "" then
		return
	end
	destroy()

	local layers = context.root.layers
	local panel = Builder.frame({
		Name = "tooltip",
		AutomaticSize = Runtime.Enum.AutomaticSize.X,
		Size = Runtime.UDim2.fromOffset(0, 24),
		BackgroundColor3 = context.binder:resolve("surface.raised"),
		ZIndex = layers:next("toast"),
	})
	Builder.corner(4).Parent = panel
	Builder.padding(8, 4).Parent = panel
	Builder.stroke(context.binder:resolve("border.hairline"), 1).Parent = panel

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.new(1, 0, 1, 0),
		Text = text,
		TextColor3 = context.binder:resolve("text.primary"),
		TextSize = 11,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		ZIndex = panel.ZIndex + 1,
	})
	label.Parent = panel

	panel.Parent = layers:frame("toast")

	local position = element.AbsolutePosition
	local size = element.AbsoluteSize
	local screen = viewport()
	local x = position.X
	local y = position.Y + size.Y + 6
	local width = 160

	x = math.clamp(x, 8, math.max(8, screen.X - width - 8))
	if y + 24 > screen.Y then
		y = math.max(8, position.Y - 30)
	end

	panel.Position = Runtime.UDim2.fromOffset(x, y)
	active = panel
end

function Tooltip.attach(janitor: any, context: any, element: any, text: string, options: any?)
	local config = options or {}
	local delay = config.Delay or 0.5

	janitor:Add(element.MouseEnter:Connect(function()
		if timer ~= nil then
			timer:Cancel()
		end
		timer = Scheduler:after(delay, function()
			timer = nil
			Tooltip.show(context, element, text)
		end)
	end))
	janitor:Add(element.MouseLeave:Connect(function()
		Tooltip.hide()
	end))
end

function Tooltip.isOpen(): boolean
	return active ~= nil
end

function Tooltip.reset()
	destroy()
end

return Tooltip
