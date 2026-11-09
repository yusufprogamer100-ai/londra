--!strict
-- Title bar: drag surface, title, and the two window controls. Double click is
-- measured here because Roblox input events do not expose a click count.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")
local IconButton = require("./IconButton")

local TitleBar = Class:extends("TitleBar")

local DOUBLE_CLICK_WINDOW = 0.35

function TitleBar:init(context: any, window: any, options: any)
	self.context = context
	self.binder = context.binder
	self.window = window
	self.options = options or {}

	local bar = Builder.frame({
		Name = "TitleBar",
		Size = Runtime.UDim2.new(1, 0, 0, Tokens.row.titlebar),
		BackgroundTransparency = 1,
		ZIndex = 10,
	})
	bar.Parent = options.Parent
	self.element = bar
	self._janitor:Add(bar)

	local title = Builder.label({
		Name = "title",
		Size = Runtime.UDim2.new(1, -116, 0, 20),
		Position = Runtime.UDim2.new(0, self.options.Icon ~= nil and 34 or 14, 0, 10),
		Text = self.options.Title or "Londra",
		TextColor3 = self.binder:resolve("text.primary"),
		TextSize = 14,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = 11,
	})
	title.Parent = bar
	self.title = title
	self._janitor:Add(self.binder:bind(title, "TextColor3", "text.primary"))

	if self.options.Icon ~= nil then
		local icon = Builder.label({
			Name = "icon",
			Size = Runtime.UDim2.fromOffset(16, 16),
			Position = Runtime.UDim2.new(0, 12, 0, 12),
			Text = tostring(self.options.Icon),
			TextColor3 = self.binder:resolve("accent.base"),
			TextSize = 14,
			Font = Runtime.Enum.Font.GothamBold,
			ZIndex = 11,
		})
		icon.Parent = bar
		self._janitor:Add(self.binder:bind(icon, "TextColor3", "accent.base"))
	end

	local minimize = IconButton.new(context, {
		Name = "minimize",
		Glyph = "-",
		Size = 28,
		Parent = bar,
		ZIndex = 12,
		Focusable = false,
		Callback = function()
			self.window:minimize()
		end,
	})
	minimize.element.AnchorPoint = Runtime.Vector2.new(1, 0.5)
	minimize.element.Position = Runtime.UDim2.new(1, -38, 0.5, 0)
	self._janitor:Add(minimize)

	local close = IconButton.new(context, {
		Name = "close",
		Glyph = "x",
		Size = 28,
		Parent = bar,
		ZIndex = 12,
		Focusable = false,
		Callback = function()
			self.window:close()
		end,
	})
	close.element.AnchorPoint = Runtime.Vector2.new(1, 0.5)
	close.element.Position = Runtime.UDim2.new(1, -8, 0.5, 0)
	self._janitor:Add(close)

	self.lastClick = -1
	self._janitor:Add(bar.MouseButton1Click:Connect(function()
		local now = os.clock()
		if self.lastClick >= 0 and now - self.lastClick <= DOUBLE_CLICK_WINDOW then
			self.lastClick = -1
			self.window:toggleMaximize()
			return
		end
		self.lastClick = now
	end))
end

function TitleBar:setTitle(text: string)
	self.title.Text = tostring(text)
end

return TitleBar
