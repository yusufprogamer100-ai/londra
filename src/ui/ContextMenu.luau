--!strict
-- Context menu. Popup layer, one level of submenu, viewport clamped. The
-- catcher is a real button so a click outside closes the menu before it reaches
-- the window underneath.

local Runtime = require("../core/Runtime")
local Builder = require("./Builder")
local Input = require("./Input")

local ContextMenu = {}

local WIDTH = 208
local ITEM_HEIGHT = 28
local SEPARATOR_HEIGHT = 9

local active = nil

local function viewport(): any
	local camera = Runtime.workspace and Runtime.workspace.CurrentCamera or nil
	if camera ~= nil and camera.ViewportSize ~= nil then
		return camera.ViewportSize
	end
	return Runtime.Vector2.new(1920, 1080)
end

local function measure(items: { any }): number
	local height = 8
	for _, item in ipairs(items) do
		height += item.Separator and SEPARATOR_HEIGHT or ITEM_HEIGHT
	end
	return height
end

local function close()
	if active == nil then
		return
	end
	local menu = active
	active = nil
	if menu.escape ~= nil then
		menu.escape:Disconnect()
	end
	if menu.catcher ~= nil then
		menu.catcher:Destroy()
	end
	if menu.panel ~= nil then
		menu.panel:Destroy()
	end
	if menu.submenu ~= nil then
		menu.submenu:Destroy()
		menu.submenu = nil
	end
end

local function buildPanel(context: any, items: { any }, depth: number): any
	local binder = context.binder
	local layers = context.root.layers
	local height = measure(items)

	local panel = Builder.frame({
		Name = depth > 0 and "submenu" or "context_menu",
		Size = Runtime.UDim2.fromOffset(WIDTH, height),
		BackgroundColor3 = binder:resolve("surface.raised"),
		ZIndex = layers:next("popup"),
	})
	Builder.corner(6).Parent = panel
	Builder.stroke(binder:resolve("border.hairline"), 1).Parent = panel
	Builder.padding(4, 0, 4).Parent = panel
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 0),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = panel

	local entry = { panel = panel, submenu = nil, items = items }

	local function openSubmenu(item: any, row: any)
		if entry.submenu ~= nil then
			entry.submenu:Destroy()
			entry.submenu = nil
		end
		if depth >= 1 then
			return
		end
		local child = buildPanel(context, item.Submenu, depth + 1)
		child.panel.Position = Runtime.UDim2.fromOffset(row.AbsolutePosition.X + WIDTH + 2, row.AbsolutePosition.Y)
		entry.submenu = child
	end

	for index, item in ipairs(items) do
		if item.Separator then
			local line = Builder.frame({
				Name = "separator",
				LayoutOrder = index,
				Size = Runtime.UDim2.new(1, -8, 0, 1),
				Position = Runtime.UDim2.fromOffset(4, 0),
				BackgroundColor3 = binder:resolve("border.hairline"),
				ZIndex = panel.ZIndex + 1,
			})
			line.Parent = panel
		else
			local row = Builder.button({
				Name = "item_" .. tostring(index),
				LayoutOrder = index,
				Size = Runtime.UDim2.new(1, 0, 0, ITEM_HEIGHT),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = panel.ZIndex + 1,
			})
			Builder.corner(4).Parent = row
			row.Parent = panel

			local icon = Builder.label({
				Name = "icon",
				Size = Runtime.UDim2.fromOffset(18, ITEM_HEIGHT),
				Position = Runtime.UDim2.fromOffset(8, 0),
				Text = item.Icon ~= nil and tostring(item.Icon) or "",
				TextColor3 = binder:resolve("text.muted"),
				TextSize = 12,
				Font = Runtime.Enum.Font.GothamMedium,
				TextXAlignment = Runtime.Enum.TextXAlignment.Center,
				ZIndex = panel.ZIndex + 2,
			})
			icon.Parent = row

			local label = Builder.label({
				Name = "label",
				Size = Runtime.UDim2.new(1, -(item.Shortcut ~= nil and 76 or 30), ITEM_HEIGHT),
				Position = Runtime.UDim2.fromOffset(30, 0),
				Text = item.Text or "",
				TextColor3 = binder:resolve(item.Disabled and "text.muted" or "text.primary"),
				TextSize = 12,
				Font = Runtime.Enum.Font.Gotham,
				TextXAlignment = Runtime.Enum.TextXAlignment.Left,
				TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
				ZIndex = panel.ZIndex + 2,
			})
			label.Parent = row

			if item.Shortcut ~= nil then
				local shortcut = Builder.label({
					Name = "shortcut",
					AnchorPoint = Runtime.Vector2.new(1, 0.5),
					Position = Runtime.UDim2.new(1, -8, 0.5, 0),
					Size = Runtime.UDim2.fromOffset(60, ITEM_HEIGHT),
					Text = tostring(item.Shortcut),
					TextColor3 = binder:resolve("text.muted"),
					TextSize = 10,
					Font = Runtime.Enum.Font.Gotham,
					TextXAlignment = Runtime.Enum.TextXAlignment.Right,
					ZIndex = panel.ZIndex + 2,
				})
				shortcut.Parent = row
			end

			if item.Submenu ~= nil then
				local chevron = Builder.label({
					Name = "chevron",
					AnchorPoint = Runtime.Vector2.new(1, 0.5),
					Position = Runtime.UDim2.new(1, -8, 0.5, 0),
					Size = Runtime.UDim2.fromOffset(12, ITEM_HEIGHT),
					Text = ">",
					TextColor3 = binder:resolve("text.muted"),
					TextSize = 10,
					Font = Runtime.Enum.Font.GothamBold,
					ZIndex = panel.ZIndex + 2,
				})
				chevron.Parent = row
			end

			row.MouseEnter:Connect(function()
				if item.Disabled then
					return
				end
				row.BackgroundTransparency = 0
				row.BackgroundColor3 = binder:resolve("state.hover")
				if item.Submenu ~= nil then
					openSubmenu(item, row)
				elseif entry.submenu ~= nil then
					entry.submenu:Destroy()
					entry.submenu = nil
				end
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundTransparency = 1
			end)
			row.MouseButton1Click:Connect(function()
				if item.Disabled then
					return
				end
				if item.Submenu ~= nil then
					openSubmenu(item, row)
					return
				end
				close()
				if item.Callback ~= nil then
					pcall(item.Callback)
				end
			end)
		end
	end

	return entry
end

function ContextMenu.open(context: any, items: { any }, x: number, y: number): any
	close()
	if items == nil or #items == 0 then
		return nil
	end

	local layers = context.root.layers
	local catcher = Builder.button({
		Name = "context_catcher",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = layers:next("popup"),
	})
	catcher.Parent = layers:frame("popup")

	local root = buildPanel(context, items, 0)
	local panel = root.panel
	panel.Parent = layers:frame("popup")

	local screen = viewport()
	local height = measure(items)
	local left = math.clamp(x, 8, math.max(8, screen.X - WIDTH - 8))
	local top = math.clamp(y, 8, math.max(8, screen.Y - height - 8))
	panel.Position = Runtime.UDim2.fromOffset(left, top)

	catcher.MouseButton1Click:Connect(close)

	local escape = Input.bind(Runtime.Enum.KeyCode.Escape, function()
		close()
	end, { force = true })

	active = {
		catcher = catcher,
		panel = panel,
		escape = escape,
		submenu = nil,
		entry = root,
	}
	return panel
end

function ContextMenu.close()
	close()
end

function ContextMenu.isOpen(): boolean
	return active ~= nil
end

function ContextMenu.reset()
	close()
end

return ContextMenu
