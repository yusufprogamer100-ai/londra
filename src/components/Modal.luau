--!strict
-- Modal. One at a time, overlay layer, focus trapped while open. The backdrop is
-- a real click catcher, not a transparent label that leaks clicks to the window.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Scheduler = require("../core/Scheduler")
local Input = require("../ui/Input")

local Modal = Class:extends("Modal")

local VARIANTS = {
	primary = { background = "accent.base", text = "accent.on" },
	secondary = { background = "surface.sunken", text = "text.primary" },
	ghost = { background = "surface.sunken", text = "text.secondary" },
	danger = { background = "state.danger", text = "text.inverse" },
}

function Modal:init(context: any, options: any)
	self.context = context
	self.binder = context.binder
	self.options = options or {}
	self.closed = false
	self.buttons = {}
	self.trap = nil

	local window = context.window
	if window ~= nil and window.activeModal ~= nil and not window.activeModal:isDestroyed() then
		window.activeModal:Close(true)
	end
	if window ~= nil then
		window.activeModal = self
	end

	local layers = context.root.layers
	local catcher = Builder.button({
		Name = "modal_overlay",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundColor3 = self.binder:resolve("surface.base"),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = layers:next("overlay"),
	})
	catcher.Parent = layers:frame("overlay")
	self.catcher = catcher
	self._janitor:Add(catcher)
	self._janitor:Add(self.binder:bind(catcher, "BackgroundColor3", "surface.base"))

	local panel = Builder.frame({
		Name = "modal",
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		Size = Runtime.UDim2.fromOffset(420, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		BackgroundColor3 = self.binder:resolve("surface.raised"),
		ZIndex = catcher.ZIndex + 1,
	})
	Builder.corner(Tokens.radius.window).Parent = panel
	Builder.stroke(self.binder:resolve("border.hairline"), 1).Parent = panel
	Builder.padding(Tokens.space.lg).Parent = panel
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, Tokens.space.md),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = panel
	panel.Parent = layers:frame("overlay")
	self.panel = panel
	self._janitor:Add(panel)
	self._janitor:Add(self.binder:bind(panel, "BackgroundColor3", "surface.raised"))

	local title = Builder.label({
		Name = "title",
		LayoutOrder = 1,
		Size = Runtime.UDim2.new(1, 0, 0, 20),
		Text = self.options.Title or "Confirm",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 14,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		ZIndex = panel.ZIndex + 1,
	})
	title.Parent = panel
	self._janitor:Add(self.binder:bind(title, "TextColor3", "text.primary"))
	self.title = title

	local content = Builder.label({
		Name = "content",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		Text = self.options.Content or "",
		TextColor3 = self.binder:resolve("text.secondary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Top,
		ZIndex = panel.ZIndex + 1,
	})
	content.Parent = panel
	self._janitor:Add(self.binder:bind(content, "TextColor3", "text.secondary"))
	self.content = content

	local footer = Builder.frame({
		Name = "footer",
		LayoutOrder = 3,
		Size = Runtime.UDim2.new(1, 0, 0, 28),
		ZIndex = panel.ZIndex + 1,
	})
	footer.Parent = panel
	Builder.new("UIListLayout", {
		FillDirection = Runtime.Enum.FillDirection.Horizontal,
		HorizontalAlignment = Runtime.Enum.HorizontalAlignment.Right,
		VerticalAlignment = Runtime.Enum.VerticalAlignment.Center,
		Padding = Runtime.UDim.new(0, Tokens.space.sm),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = footer
	self.footer = footer

	local trap = context.focus ~= nil and context.focus:pushTrap() or nil
	self.trap = trap

	for index, definition in ipairs(self.options.Buttons or {}) do
		self:addButton(definition, index)
	end

	if context.focus ~= nil then
		if #self.buttons > 0 then
			context.focus:set(self.buttons[#self.buttons].item)
		else
			context.focus:clear()
		end
	end

	self._janitor:Add(catcher.MouseButton1Click:Connect(function()
		if self.options.Dismissable ~= false then
			self:Close()
		end
	end))

	self._janitor:Add(Input.bind(Runtime.Enum.KeyCode.Escape, function()
		if self.options.Dismissable ~= false then
			self:Close()
		end
	end, { force = true }))

	local lighting = nil
	local ok, service = pcall(function()
		return Runtime.service("Lighting")
	end)
	if ok then
		lighting = service
	end
	if lighting ~= nil then
		local blur = Builder.new("BlurEffect", { Name = "LondraModalBlur", Size = 12 })
		blur.Parent = lighting
		self.blur = blur
		self._janitor:Add(blur)
	end

	Motion.tween(catcher, { BackgroundTransparency = 0.55 }, { duration = Motion.duration("open") })
	local scale = Builder.new("UIScale", { Name = "__londra_modal", Scale = 0.96 })
	scale.Parent = panel
	Motion.tween(scale, { Scale = 1 }, { duration = Motion.duration("open") })
end

function Modal:addButton(definition: any, index: number)
	local variant = VARIANTS[definition.Variant or "secondary"] or VARIANTS.secondary
	local button = Builder.button({
		Name = "button_" .. tostring(index),
		LayoutOrder = index,
		Size = Runtime.UDim2.fromOffset(definition.Width or 108, 28),
		BackgroundColor3 = self.binder:resolve(variant.background),
		Text = definition.Text or "OK",
		TextColor3 = self.binder:resolve(variant.text),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = self.panel.ZIndex + 2,
	})
	Builder.corner(Tokens.radius.control).Parent = button
	button.Parent = self.footer
	self._janitor:Add(self.binder:bind(button, "BackgroundColor3", variant.background))
	self._janitor:Add(self.binder:bind(button, "TextColor3", variant.text))

	local item = nil
	local modal = self
	self._janitor:Add(button.MouseButton1Click:Connect(function()
		if definition.Callback ~= nil then
			pcall(definition.Callback)
		end
		if definition.KeepOpen ~= true then
			modal:Close()
		end
	end))

	if self.context.focus ~= nil then
		local handle = self.context.focus:register(button, {
			onActivate = function()
				if definition.Callback ~= nil then
					pcall(definition.Callback)
				end
				if definition.KeepOpen ~= true then
					modal:Close()
				end
			end,
		})
		self._janitor:Add(handle)
		item = handle.item
	end

	table.insert(self.buttons, { button = button, item = item, definition = definition })
	return button
end

function Modal:Close(instant: boolean?)
	if self.closed then
		return
	end
	self.closed = true

	if self.context.window ~= nil and self.context.window.activeModal == self then
		self.context.window.activeModal = nil
	end
	if self.trap ~= nil and self.context.focus ~= nil then
		self.context.focus:clear()
		self.context.focus:popTrap()
		self.trap = nil
	end

	if instant == true or Motion.duration("close") <= 0 then
		self:Destroy()
		return
	end

	local duration = Motion.duration("close")
	local scale = self.panel:FindFirstChild("__londra_modal")
	if scale ~= nil then
		Motion.tween(scale, { Scale = 0.97 }, { duration = duration })
	end
	Motion.tween(self.catcher, { BackgroundTransparency = 1 }, { duration = duration })
	Scheduler:after(duration, function()
		self:Destroy()
	end)
end

return Modal
