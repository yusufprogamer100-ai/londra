--!strict
-- Notification stack. Four visible at a time, the rest wait in a queue. The
-- progress bar is a real countdown that pauses while the pointer is over the
-- card, so a message is never yanked away mid read.

local Runtime = require("../core/Runtime")
local Builder = require("./Builder")
local Motion = require("../core/Motion")
local Scheduler = require("../core/Scheduler")

local Notifications = {}

local MAX_VISIBLE = 4
local WIDTH = 320
local INSET = 16
local TICK = 0.05
local DEFAULT_DURATION = 4

local TYPES = {
	info = "state.info",
	success = "state.success",
	warn = "state.warn",
	danger = "state.danger",
}

local state = {
	root = nil,
	binder = nil,
	stack = nil,
	entries = {},
	queue = {},
	sequence = 0,
}

local function teardown()
	for _, entry in ipairs(state.entries) do
		if entry.timer ~= nil then
			entry.timer:Cancel()
		end
		if entry.card ~= nil then
			entry.card:Destroy()
		end
	end
	table.clear(state.entries)
	table.clear(state.queue)
	if state.stack ~= nil then
		state.stack:Destroy()
	end
	state.stack = nil
	state.root = nil
	state.binder = nil
end

local function ensureStack(root: any, binder: any)
	if state.root == root and state.stack ~= nil then
		state.binder = binder or state.binder
		return
	end
	teardown()
	state.root = root
	state.binder = binder

	local layers = root.layers
	local stack = Builder.frame({
		Name = "Notifications",
		AnchorPoint = Runtime.Vector2.new(1, 1),
		Position = Runtime.UDim2.fromOffset(-INSET, -INSET),
		Size = Runtime.UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		ZIndex = layers:next("toast"),
	})
	stack.Parent = layers:frame("toast")
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 8),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Runtime.Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Runtime.Enum.HorizontalAlignment.Right,
	}).Parent = stack
	state.stack = stack
end

local function dismiss(id: string)
	for index = #state.entries, 1, -1 do
		local entry = state.entries[index]
		if entry.id == id then
			table.remove(state.entries, index)
			if entry.timer ~= nil then
				entry.timer:Cancel()
			end
			if entry.card ~= nil then
				entry.card:Destroy()
			end
			break
		end
	end
	for index = #state.queue, 1, -1 do
		if state.queue[index].id == id then
			table.remove(state.queue, index)
		end
	end
	local nextEntry = table.remove(state.queue, 1)
	if nextEntry ~= nil then
		Notifications.show(state.root, state.binder, nextEntry.options)
	end
end

local function restartTimer(entry: any)
	if entry.timer ~= nil then
		entry.timer:Cancel()
		entry.timer = nil
	end
	if entry.duration <= 0 then
		if entry.fill ~= nil then
			entry.fill.Visible = false
		end
		return
	end
	entry.remaining = entry.duration

	local function tick()
		if entry.card == nil or entry.card.Parent == nil then
			return
		end
		if not entry.paused then
			entry.remaining -= TICK
			local ratio = math.clamp(entry.remaining / entry.duration, 0, 1)
			if entry.fill ~= nil then
				entry.fill.Size = Runtime.UDim2.new(ratio, 0, 1, 0)
			end
			if entry.remaining <= 0 then
				dismiss(entry.id)
				return
			end
		end
		entry.timer = Scheduler:after(TICK, tick)
	end

	if entry.fill ~= nil then
		entry.fill.Visible = true
		entry.fill.Size = Runtime.UDim2.fromScale(1, 1)
	end
	entry.timer = Scheduler:after(TICK, tick)
end

local function buildCard(entry: any, options: any)
	local binder = state.binder
	local token = TYPES[options.Type or "info"] or TYPES.info

	local card = Builder.new("CanvasGroup", {
		Name = "Notification",
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		BackgroundColor3 = binder:resolve("surface.raised"),
		BackgroundTransparency = 0,
		GroupTransparency = 1,
		LayoutOrder = entry.order,
		ZIndex = state.stack.ZIndex + entry.order,
	})
	Builder.corner(6).Parent = card
	Builder.stroke(binder:resolve("border.hairline"), 1).Parent = card
	Builder.padding(12).Parent = card
	Builder.new("UIListLayout", {
		Padding = Runtime.UDim.new(0, 6),
		SortOrder = Runtime.Enum.SortOrder.LayoutOrder,
	}).Parent = card
	card.Parent = state.stack

	local seam = Builder.frame({
		Name = "seam",
		Position = Runtime.UDim2.fromOffset(-12, 0),
		Size = Runtime.UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = binder:resolve(token),
		ZIndex = card.ZIndex + 2,
	})
	seam.Parent = card

	local header = Builder.frame({
		Name = "header",
		LayoutOrder = 1,
		Size = Runtime.UDim2.new(1, 0, 0, 18),
		ZIndex = card.ZIndex + 1,
	})
	header.Parent = card

	local title = Builder.label({
		Name = "title",
		Size = Runtime.UDim2.new(1, -22, 1, 0),
		Text = options.Title or "Notice",
		TextColor3 = binder:resolve("text.primary"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamBold,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextTruncate = Runtime.Enum.TextTruncate.AtEnd,
		ZIndex = card.ZIndex + 2,
	})
	title.Parent = header

	local close = Builder.button({
		Name = "close",
		AnchorPoint = Runtime.Vector2.new(1, 0.5),
		Position = Runtime.UDim2.new(1, 0, 0.5, 0),
		Size = Runtime.UDim2.fromOffset(18, 18),
		Text = "x",
		TextColor3 = binder:resolve("text.muted"),
		TextSize = 12,
		Font = Runtime.Enum.Font.GothamMedium,
		ZIndex = card.ZIndex + 2,
	})
	close.Parent = header

	local content = Builder.label({
		Name = "content",
		LayoutOrder = 2,
		Size = Runtime.UDim2.new(1, 0, 0, 0),
		AutomaticSize = Runtime.Enum.AutomaticSize.Y,
		Text = options.Content or "",
		TextColor3 = binder:resolve("text.secondary"),
		TextSize = 11,
		Font = Runtime.Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Runtime.Enum.TextXAlignment.Left,
		TextYAlignment = Runtime.Enum.TextYAlignment.Top,
		ZIndex = card.ZIndex + 1,
	})
	content.Parent = card

	local actionButton = nil
	if options.Action ~= nil then
		actionButton = Builder.button({
			Name = "action",
			LayoutOrder = 3,
			Size = Runtime.UDim2.fromOffset(96, 24),
			BackgroundColor3 = binder:resolve("surface.sunken"),
			Text = options.Action.Text or "Action",
			TextColor3 = binder:resolve("text.primary"),
			TextSize = 11,
			Font = Runtime.Enum.Font.GothamMedium,
			ZIndex = card.ZIndex + 1,
		})
		Builder.corner(4).Parent = actionButton
		actionButton.Parent = card
		actionButton.MouseButton1Click:Connect(function()
			if options.Action.Callback ~= nil then
				options.Action.Callback()
			end
			dismiss(entry.id)
		end)
	end

	local track = Builder.frame({
		Name = "track",
		LayoutOrder = 4,
		Size = Runtime.UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = binder:resolve("surface.sunken"),
		ZIndex = card.ZIndex + 1,
	})
	track.Parent = card

	local fill = Builder.frame({
		Name = "fill",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundColor3 = binder:resolve(token),
		ZIndex = card.ZIndex + 2,
	})
	fill.Parent = track

	entry.card = card
	entry.title = title
	entry.content = content
	entry.actionButton = actionButton
	entry.fill = fill
	entry.seam = seam
	entry.track = track

	close.MouseButton1Click:Connect(function()
		dismiss(entry.id)
	end)

	card.MouseEnter:Connect(function()
		entry.paused = true
	end)
	card.MouseLeave:Connect(function()
		entry.paused = false
	end)

	local scale = Builder.new("UIScale", { Name = "__londra_notify", Scale = 0.98 })
	scale.Parent = card
	Motion.tween(scale, { Scale = 1 }, { duration = Motion.duration("toast") })
	Motion.tween(card, { GroupTransparency = 0 }, { duration = Motion.duration("toast") })
end

function Notifications.show(root: any, binder: any, options: any): any
	if root == nil or binder == nil then
		return nil
	end
	ensureStack(root, binder)

	local config = options or {}
	state.sequence += 1
	local id = config.Id or ("notification-" .. tostring(state.sequence))

	for _, entry in ipairs(state.entries) do
		if entry.id == id then
			entry.title.Text = config.Title or entry.title.Text
			entry.content.Text = config.Content or entry.content.Text
			local token = TYPES[config.Type or "info"] or TYPES.info
			entry.seam.BackgroundColor3 = state.binder:resolve(token)
			entry.fill.BackgroundColor3 = state.binder:resolve(token)
			entry.duration = config.Duration or DEFAULT_DURATION
			restartTimer(entry)
			return {
				Id = id,
				Dismiss = function()
					dismiss(id)
				end,
			}
		end
	end

	if #state.entries >= MAX_VISIBLE then
		local queued = {
			id = id,
			options = config,
		}
		table.insert(state.queue, queued)
		return {
			Id = id,
			Dismiss = function()
				dismiss(id)
			end,
		}
	end

	local entry = {
		id = id,
		order = state.sequence,
		duration = config.Duration or DEFAULT_DURATION,
		remaining = config.Duration or DEFAULT_DURATION,
		paused = false,
	}
	table.insert(state.entries, entry)
	buildCard(entry, config)
	restartTimer(entry)

	return {
		Id = id,
		Dismiss = function()
			dismiss(id)
		end,
	}
end

function Notifications.dismiss(id: string)
	dismiss(id)
end

function Notifications.clear()
	for _, entry in ipairs(state.entries) do
		if entry.timer ~= nil then
			entry.timer:Cancel()
		end
		if entry.card ~= nil then
			entry.card:Destroy()
		end
	end
	table.clear(state.entries)
	table.clear(state.queue)
end

function Notifications.count(): number
	return #state.entries
end

function Notifications.reset()
	teardown()
	state.sequence = 0
end

return Notifications
