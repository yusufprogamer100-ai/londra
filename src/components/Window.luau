--!strict
-- Window shell. Geometry is stored in offsets so drag and resize maths stay in
-- one unit space; the root UIScale handles display scaling separately.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Scheduler = require("../core/Scheduler")
local Drag = require("../ui/Drag")
local Resize = require("../ui/Resize")
local Focus = require("../ui/Focus")
local Input = require("../ui/Input")
local TitleBar = require("./TitleBar")
local TabRail = require("./TabRail")
local Tab = require("./Tab")
local Log = require("../core/Log")

local Window = Class:extends("Window")

local DEFAULT_WIDTH = 760
local DEFAULT_HEIGHT = 500
local EDGE_INSET = 24
local MIN_VISIBLE = 80

local function viewport(): any
	local camera = Runtime.workspace and Runtime.workspace.CurrentCamera or nil
	if camera ~= nil and camera.ViewportSize ~= nil then
		return camera.ViewportSize
	end
	return Runtime.Vector2.new(1920, 1080)
end

function Window:init(context: any, options: any)
	self.options = options or {}
	self.binder = context.binder
	self.root = context.root
	self.flags = context.flags
	self.scale = 1
	if self.root ~= nil and self.root.scale ~= nil then
		self.scale = self.root.scale.Scale or 1
	end

	self.context = setmetatable({
		window = self,
		binder = self.binder,
		layers = self.root.layers,
		focus = Focus.new(self.binder),
		flags = self.flags,
		root = self.root,
		notify = context.notify,
		version = context.version,
	}, { __index = context })

	self.tabs = {}
	self.minimized = false
	self.maximized = false
	self.savedGeometry = nil
	self.restoreHeight = nil
	self.closing = false

	local screen = viewport()
	local width = DEFAULT_WIDTH
	local height = DEFAULT_HEIGHT
	local size = self.options.Size
	if size ~= nil then
		width = size.X.Offset > 0 and size.X.Offset or screen.X * size.X.Scale
		height = size.Y.Offset > 0 and size.Y.Offset or screen.Y * size.Y.Scale
	end

	local maxWidth = screen.X * 0.92
	local maxHeight = screen.Y * 0.92
	width = math.clamp(width, 320, maxWidth)
	height = math.clamp(height, 240, maxHeight)

	local x = screen.X - width - EDGE_INSET
	local y = EDGE_INSET
	if self.options.Position ~= nil then
		x = self.options.Position.X.Offset
		y = self.options.Position.Y.Offset
	end

	local frame = Builder.frame({
		Name = self.options.Name or "LondraWindow",
		Size = Runtime.UDim2.fromOffset(width, height),
		Position = Runtime.UDim2.fromOffset(x, y),
		BackgroundColor3 = self.binder:resolve("surface.base"),
		BackgroundTransparency = self.options.Acrylic and 0.04 or 0,
		ClipsDescendants = false,
		ZIndex = 10,
	})
	Builder.corner(Tokens.radius.window).Parent = frame
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = frame
	frame.Parent = self.root.layers:frame("base")
	self.frame = frame
	self._janitor:Add(frame)
	self._janitor:Add(self.binder:bind(frame, "BackgroundColor3", "surface.base"))

	self.statusHeight = self.options.ShowStatusBar == false and 0 or Tokens.row.status

	self.titleBar = TitleBar.new(self.context, self, {
		Parent = frame,
		Title = self.options.Title or "Londra",
		Icon = self.options.Icon,
	})
	self._janitor:Add(self.titleBar)

	local body = Builder.frame({
		Name = "Body",
		Position = Runtime.UDim2.fromOffset(0, Tokens.row.titlebar),
		Size = Runtime.UDim2.new(1, 0, 1, -(Tokens.row.titlebar + self.statusHeight)),
		ZIndex = 2,
	})
	body.Parent = frame
	self.body = body
	self._janitor:Add(body)

	self.rail = TabRail.new(self.context, {
		Parent = body,
		Mode = self.options.TabPosition or "left",
	})
	self._janitor:Add(self.rail)

	local content = Builder.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	content.Parent = body
	self.content = content
	self._janitor:Add(content)

	if self.rail.mode == "top" then
		self.rail.element.Position = Runtime.UDim2.fromOffset(0, 0)
		content.Position = Runtime.UDim2.fromOffset(0, Tokens.row.titlebar)
		content.Size = Runtime.UDim2.new(1, 0, 1, -Tokens.row.titlebar)
	else
		self.rail.element.Position = Runtime.UDim2.fromOffset(0, 0)
		content.Position = Runtime.UDim2.fromOffset(Tokens.size.tabRail, 0)
		content.Size = Runtime.UDim2.new(1, -Tokens.size.tabRail, 1, 0)
	end

	if self.statusHeight > 0 then
		local status = Builder.frame({
			Name = "StatusBar",
			AnchorPoint = Runtime.Vector2.new(0, 1),
			Position = Runtime.UDim2.new(0, 0, 1, 0),
			Size = Runtime.UDim2.new(1, 0, 0, self.statusHeight),
			BackgroundColor3 = self.binder:resolve("surface.sunken"),
			ZIndex = 2,
		})
		status.Parent = frame
		self._janitor:Add(status)
		self._janitor:Add(self.binder:bind(status, "BackgroundColor3", "surface.sunken"))

		local text = self.options.Subtitle or ("v" .. tostring(context.version or "1.0.0"))
		local label = Builder.label({
			Name = "status",
			Size = Runtime.UDim2.new(1, -16, 1, 0),
			Position = Runtime.UDim2.fromOffset(12, 0),
			Text = text,
			TextColor3 = self.binder:resolve("text.muted"),
			TextSize = 10,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
		label.Parent = status
		self._janitor:Add(self.binder:bind(label, "TextColor3", "text.muted"))
		self.status = status
	end

	self:attachDrag()
	self:attachResize()
	self:attachToggleKey()

	self._janitor:Add(frame.MouseButton1Down:Connect(function()
		self:bringToFront()
	end))
	self._janitor:Add(self.titleBar.element.MouseButton1Down:Connect(function()
		self:bringToFront()
	end))

	self:animateOpen()
end

function Window:attachDrag()
	if self.options.Draggable == false then
		return
	end
	local start = nil
	local snap = self.options.Snap or 8

	Drag.attach(self._janitor, {
		scale = self.scale,
		hitTest = function(input)
			return Drag.inside(self.titleBar.element, input)
		end,
		onStart = function()
			start = self:getPosition()
		end,
		onDrag = function(deltaX, deltaY)
			if start == nil then
				return
			end
			local screen = viewport()
			local size = self:getSize()
			local x = start.X + deltaX
			local y = start.Y + deltaY

			if math.abs(x) <= snap then
				x = 0
			elseif math.abs(x + size.X - screen.X) <= snap then
				x = screen.X - size.X
			end
			if math.abs(y) <= snap then
				y = 0
			end

			x = math.clamp(x, -(size.X - MIN_VISIBLE), screen.X - MIN_VISIBLE)
			y = math.clamp(y, 0, screen.Y - Tokens.row.titlebar)
			self:setGeometry(x, y, size.X, size.Y)
		end,
	})
end

function Window:attachResize()
	if self.options.Resizable == false then
		return
	end
	local screen = viewport()
	Resize.attach(self._janitor, self, {
		minSize = self.options.MinSize or Runtime.Vector2.new(520, 340),
		maxSize = self.options.MaxSize or Runtime.Vector2.new(screen.X * 0.92, screen.Y * 0.92),
	})
end

function Window:attachToggleKey()
	local key = self.options.ToggleKey
	if key == nil then
		return
	end
	self._janitor:Add(Input.bind(key, function()
		if Input.isSuspended() then
			return
		end
		self:toggleVisible()
	end, { force = true }))
end

function Window:animateOpen()
	local duration = Motion.duration("open")
	if duration <= 0 then
		return
	end
	local scale = Builder.new("UIScale", { Name = "__londra_open", Scale = 0.96 })
	scale.Parent = self.frame
	Motion.tween(scale, { Scale = 1 }, { duration = duration })
	Scheduler:after(duration, function()
		if scale.Parent ~= nil then
			scale:Destroy()
		end
	end)
end

function Window:getSize(): any
	local size = self.frame.Size
	return Runtime.Vector2.new(size.X.Offset, size.Y.Offset)
end

function Window:getPosition(): any
	local position = self.frame.Position
	return Runtime.Vector2.new(position.X.Offset, position.Y.Offset)
end

function Window:setGeometry(x: number, y: number, width: number, height: number)
	self.frame.Position = Runtime.UDim2.fromOffset(x, y)
	self.frame.Size = Runtime.UDim2.fromOffset(width, height)
end

function Window:Tab(options: any)
	local copy = table.clone(options or {})
	copy.Parent = self.content
	local tab = Tab.new(self.context, copy)
	table.insert(self.tabs, tab)
	self._janitor:Add(tab)
	local index = self.rail:add(tab)
	if index == 1 then
		self.rail:select(1)
	end
	return tab
end

function Window:SelectTab(index: number): boolean
	return self.rail:select(index)
end

function Window:activeTab(): any
	if self.rail.active == 0 then
		return nil
	end
	return self.tabs[self.rail.active]
end

function Window:bringToFront()
	if self.closing then
		return
	end
	if self.context.focusWindow ~= nil then
		self.context.focusWindow(self)
	end
end

function Window:toggleVisible()
	if self.closing then
		return
	end
	if self.frame.Visible then
		self.frame.Visible = false
	else
		self.frame.Visible = true
		self:bringToFront()
	end
end

function Window:minimize()
	if self.closing then
		return
	end
	local duration = Motion.duration("close")

	if not self.minimized then
		local size = self:getSize()
		self.restoreHeight = size.Y
		self.minimized = true
		local targetHeight = Tokens.row.titlebar + self.statusHeight
		Motion.tween(self.frame, { Size = Runtime.UDim2.fromOffset(size.X, targetHeight) }, { duration = duration })
		if duration <= 0 then
			self.body.Visible = false
			if self.status ~= nil then
				self.status.Visible = false
			end
		else
			Scheduler:after(duration, function()
				if self.minimized then
					self.body.Visible = false
					if self.status ~= nil then
						self.status.Visible = false
					end
				end
			end)
		end
		return
	end

	self.minimized = false
	self.body.Visible = true
	if self.status ~= nil then
		self.status.Visible = true
	end
	local size = self:getSize()
	local height = self.restoreHeight or DEFAULT_HEIGHT
	Motion.tween(self.frame, { Size = Runtime.UDim2.fromOffset(size.X, height) }, { duration = duration })
end

function Window:toggleMaximize()
	if self.closing then
		return
	end
	local screen = viewport()
	local duration = Motion.duration("open")

	if not self.maximized then
		self.savedGeometry = {
			x = self:getPosition().X,
			y = self:getPosition().Y,
			width = self:getSize().X,
			height = self:getSize().Y,
		}
		self.maximized = true
		Motion.tween(self.frame, {
			Position = Runtime.UDim2.fromOffset(EDGE_INSET, EDGE_INSET),
			Size = Runtime.UDim2.fromOffset(screen.X - EDGE_INSET * 2, screen.Y - EDGE_INSET * 2),
		}, { duration = duration })
		return
	end

	local saved = self.savedGeometry
	if saved == nil then
		return
	end
	self.maximized = false
	Motion.tween(self.frame, {
		Position = Runtime.UDim2.fromOffset(saved.x, saved.y),
		Size = Runtime.UDim2.fromOffset(saved.width, saved.height),
	}, { duration = duration })
end

function Window:close()
	if self.closing then
		return
	end
	self.closing = true
	if self.options.OnClose ~= nil then
		pcall(self.options.OnClose)
	end
	local duration = Motion.duration("close")
	if duration <= 0 then
		self:Destroy()
		return
	end
	local scale = self.frame:FindFirstChild("__londra_close")
	if scale == nil then
		scale = Builder.new("UIScale", { Name = "__londra_close", Scale = 1 })
		scale.Parent = self.frame
	end
	Motion.tween(scale, { Scale = 0.96 }, { duration = duration })
	Scheduler:after(duration, function()
		self:Destroy()
	end)
end

function Window:beforeDestroy()
	if self.context.focus ~= nil then
		self.context.focus:destroy()
	end
	if self.context.windowClosed ~= nil then
		self.context.windowClosed(self)
	end
end

return Window
