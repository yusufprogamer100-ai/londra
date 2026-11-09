--!strict
-- Status chip. Variants map to the theme state tokens, so a badge never invents
-- a colour that the contrast checker has not seen.

local Base = require("./Base")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")

local Badge = Base:extends("Badge")

local VARIANTS = {
	neutral = { background = "surface.sunken", text = "text.secondary" },
	info = { background = "state.info", text = "text.inverse" },
	success = { background = "state.success", text = "text.inverse" },
	warn = { background = "state.warn", text = "text.inverse" },
	danger = { background = "state.danger", text = "text.inverse" },
	accent = { background = "accent.base", text = "accent.on" },
}

function Badge:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local variant = VARIANTS[config.Variant or "neutral"] or VARIANTS.neutral

	local frame = Builder.frame({
		Name = "badge",
		Size = Runtime.UDim2.fromOffset(0, 20),
		AutomaticSize = Runtime.Enum.AutomaticSize.X,
		ZIndex = config.ZIndex or 3,
	})
	Builder.corner(4).Parent = frame
	Builder.padding(0, 8).Parent = frame
	frame.Parent = config.Parent
	self.element = frame

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.fromOffset(0, 20),
		AutomaticSize = Runtime.Enum.AutomaticSize.X,
		Text = config.Text or "",
		TextColor3 = self.binder:resolve(variant.text),
		TextSize = 10,
		Font = Runtime.Enum.Font.GothamMedium,
		TextXAlignment = Runtime.Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	label.Parent = frame

	self:theme(frame, "BackgroundColor3", variant.background)
	self:theme(label, "TextColor3", variant.text)
	self.label = label
end

function Badge:setText(text: string)
	self.label.Text = tostring(text)
end

return Badge
