--!strict
-- The shared control row: label on the left, control area on the right, and an
-- optional description that raises the row height instead of overlapping.

local Tokens = require("../design/Tokens")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")
local Motion = require("../core/Motion")

local Row = {}

function Row.build(context: any, options: any): any
	local config = options or {}
	local hasDescription = config.description ~= nil
	local height = config.height or (hasDescription and 52 or Tokens.row.height)
	local labelWidth = config.labelWidth or 0.52
	local controlWidth = config.controlWidth or 150

	local rowProps = {
		Name = "row",
		Size = Runtime.UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}
	local row = Builder.frame(rowProps)
	if config.clickable then
		row = Builder.button(rowProps)
		row.AutoButtonColor = false
	end
	row.BackgroundColor3 = context.binder:resolve("state.hover")

	local label = Builder.label({
		Name = "label",
		Size = Runtime.UDim2.new(labelWidth, -12, 0, hasDescription and 18 or height),
		Position = Runtime.UDim2.new(0, 0, 0, hasDescription and 6 or 0),
		Text = config.title or "",
		TextColor3 = context.binder:resolve("text.primary"),
		TextSize = 13,
		Font = Runtime.Enum.Font.Gotham,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Center,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
	})
	label.Parent = row
	context.binder:bind(label, "TextColor3", "text.primary")

	local description = nil
	if hasDescription then
		description = Builder.label({
			Name = "description",
			Size = Runtime.UDim2.new(labelWidth, -12, 0, 16),
			Position = Runtime.UDim2.new(0, 0, 0, 24),
			Text = config.description,
			TextColor3 = context.binder:resolve("text.secondary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.Gotham,
			TextXAlignment = Runtime.Enum.TextXAlignment.Left,
			TextYAlignment = Runtime.Enum.TextYAlignment.Top,
			TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		})
		description.Parent = row
		context.binder:bind(description, "TextColor3", "text.secondary")
	end

	local control = Builder.frame({
		Name = "control",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.new(0, controlWidth, 0, height),
		ZIndex = 2,
	})
	control.Parent = row

	local hover = true
	if config.hover == false then
		hover = false
	end

	if hover then
		row.MouseEnter:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 0 }, { duration = Motion.duration("state") })
		end)
		row.MouseLeave:Connect(function()
			Motion.tween(row, { BackgroundTransparency = 1 }, { duration = Motion.duration("state") })
		end)
	end

	return {
		row = row,
		label = label,
		description = description,
		control = control,
		height = height,
	}
end

return Row
