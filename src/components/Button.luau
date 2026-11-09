--!strict
-- Primary action row. Ripple is a real element that is destroyed after the
-- animation, and a destructive action can require a second confirmation.

local Base = require("./Base")
local Row = require("./Row")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local Scheduler = require("../core/Scheduler")

local Button = Base:extends("Button")

local VARIANTS = {
	primary = { background = "accent.base", text = "accent.on", hover = "accent.hover", pressed = "accent.pressed" },
	secondary = { background = "surface.sunken", text = "text.primary", hover = "state.hover", pressed = "state.pressed" },
	ghost = { background = "surface.raised", text = "text.secondary", hover = "state.hover", pressed = "state.pressed" },
	danger = { background = "state.danger", text = "text.inverse", hover = "state.danger", pressed = "state.danger" },
}

function Button:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local variant = VARIANTS[config.Variant or "secondary"] or VARIANTS.secondary
	local confirmed = false

	local layout = Row.build(context, {
		title = config.Title or "Button",
		description = config.Description,
		controlWidth = config.Width or 120,
		hover = false,
	})

	self.element = layout.row
	self.element.Parent = config.Parent

	local button = Builder.button({
		Name = "action",
		Size = Runtime.UDim2.fromOffset(config.Width or 120, 26),
		Position = Runtime.UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Runtime.Vector2.new(0.5, 0.5),
		BackgroundColor3 = self.binder:resolve(variant.background),
		Text = config.Title or "Button",
		TextColor3 = self.binder:resolve(variant.text),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		AutoButtonColor = false,
		ClipsDescendants = true,
		ZIndex = 3,
	})
	button.Parent = layout.control
	Builder.corner(self.tokens.radius.control).Parent = button
	self:theme(button, "BackgroundColor3", variant.background)
	self:theme(button, "TextColor3", variant.text)

	self.button = button
	self.variant = variant

	local function reset()
		confirmed = false
		button.Text = config.Title or "Button"
		self:theme(button, "BackgroundColor3", variant.background)
	end

	local function activate()
		if not self.enabled then
			return
		end
		if config.Confirm == true and not confirmed then
			confirmed = true
			button.Text = config.ConfirmText or "Confirm?"
			self:theme(button, "BackgroundColor3", "state.danger")
			Scheduler:after(3, function()
				if confirmed then
					reset()
				end
			end)
			return
		end
		reset()
		if config.Callback ~= nil then
			config.Callback()
		end
	end

	self:track(button.MouseEnter:Connect(function()
		if not self.enabled then
			return
		end
		button.BackgroundColor3 = self.binder:resolve(variant.hover)
	end))
	self:track(button.MouseLeave:Connect(function()
		button.BackgroundColor3 = self.binder:resolve(variant.background)
	end))
	self:track(button.MouseButton1Down:Connect(function()
		if not self.enabled then
			return
		end
		Motion.press(button)
		button.BackgroundColor3 = self.binder:resolve(variant.pressed)
	end))
	self:track(button.MouseButton1Up:Connect(function()
		Motion.release(button)
		button.BackgroundColor3 = self.binder:resolve(variant.background)
	end))
	self:track(button.MouseButton1Click:Connect(activate))

	if self.focus ~= nil then
		self.focus:register(button, { onActivate = activate })
	end

	if config.Disabled == true then
		self:setEnabled(false)
	end
end

return Button
