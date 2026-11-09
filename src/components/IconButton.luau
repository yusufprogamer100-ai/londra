--!strict
-- Square icon button used by the title bar and by compact controls. Without an
-- icon asset it falls back to a text glyph, never to a borrowed icon set.

local Base = require("./Base")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")

local IconButton = Base:extends("IconButton")

function IconButton:init(context: any, options: any)
	Base.init(self, context, options)

	local size = self.options.Size or 28
	local glyph = self.options.Glyph or ""

	self.element = Builder.button({
		Name = self.options.Name or "IconButton",
		Size = Runtime.UDim2.fromOffset(size, size),
		BackgroundColor3 = self.binder:resolve("state.hover"),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = true,
		ZIndex = self.options.ZIndex or 5,
	})
	self.element.Parent = self.options.Parent

	if glyph ~= "" then
		local label = Builder.label({
			Size = Runtime.UDim2.fromScale(1, 1),
			Text = glyph,
			TextColor3 = self.binder:resolve("text.secondary"),
			TextSize = 15,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = self.options.ZIndex or 5,
		})
		label.Parent = self.element
		self:theme(label, "TextColor3", "text.secondary")
		self.label = label
	end

	self:hoverable(self.element)

	self:track(self.element.MouseButton1Click:Connect(function()
		if not self.enabled then
			return
		end
		if self.options.Callback ~= nil then
			self.options.Callback()
		end
	end))

	self:track(self.element.MouseButton1Down:Connect(function()
		Motion.press(self.element)
	end))
	self:track(self.element.MouseButton1Up:Connect(function()
		Motion.release(self.element)
	end))

	if self.focus ~= nil and self.options.Focusable ~= false then
		self.focus:register(self.element, {
			onActivate = function()
				if self.options.Callback ~= nil then
					self.options.Callback()
				end
			end,
		})
	end
end

function IconButton:setGlyph(glyph: string)
	if self.label ~= nil then
		self.label.Text = glyph
	end
end

return IconButton
