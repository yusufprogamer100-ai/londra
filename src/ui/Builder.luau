--!strict
-- Instance construction helpers. Property writes are checked: a typo in a
-- property name is reported instead of being swallowed by the engine.

local Runtime = require("../core/Runtime")
local Log = require("../core/Log")

local Builder = {}

function Builder.set(instance: any, property: string, value: any)
	local ok, err = pcall(function()
		instance[property] = value
	end)
	if not ok then
		Log.error("Builder: cannot set %s.%s (%s)", tostring(instance.ClassName), property, tostring(err))
	end
	return instance
end

function Builder.apply(instance: any, props: any?): any
	if props == nil then
		return instance
	end
	for property, value in pairs(props) do
		Builder.set(instance, property, value)
	end
	return instance
end

function Builder.new(className: string, props: any?, children: { any }?): any
	local instance = Runtime.Instance.new(className)
	Builder.apply(instance, props)
	if children ~= nil then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	return instance
end

function Builder.corner(radius: number): any
	return Builder.new("UICorner", { CornerRadius = Runtime.UDim.new(0, radius) })
end

function Builder.stroke(color: any, thickness: number?, transparency: number?): any
	return Builder.new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Runtime.Enum.ApplyStrokeMode.Border,
	})
end

function Builder.padding(all: number, horizontal: number?, vertical: number?): any
	local x = horizontal or all
	local y = vertical or all
	return Builder.new("UIPadding", {
		PaddingLeft = Runtime.UDim.new(0, x),
		PaddingRight = Runtime.UDim.new(0, x),
		PaddingTop = Runtime.UDim.new(0, y),
		PaddingBottom = Runtime.UDim.new(0, y),
	})
end

function Builder.list(padding: number?): any
	return Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, padding or 0),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	})
end

function Builder.text(props: any): any
	return Builder.new("TextLabel", props)
end

function Builder.button(props: any): any
	local propsCopy = table.clone(props or {})
	propsCopy.AutoButtonColor = false
	propsCopy.BackgroundTransparency = propsCopy.BackgroundTransparency or 1
	propsCopy.BorderSizePixel = 0
	return Builder.new("TextButton", propsCopy)
end

function Builder.frame(props: any): any
	local propsCopy = table.clone(props or {})
	propsCopy.BorderSizePixel = 0
	if propsCopy.BackgroundTransparency == nil then
		propsCopy.BackgroundTransparency = 1
	end
	return Builder.new("Frame", propsCopy)
end

function Builder.label(props: any): any
	local propsCopy = table.clone(props or {})
	propsCopy.BackgroundTransparency = 1
	propsCopy.BorderSizePixel = 0
	propsCopy.RichText = false
	return Builder.new("TextLabel", propsCopy)
end

return Builder
