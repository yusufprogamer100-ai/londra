--!strict
local Version = require("./version")
local Runtime = require("./core/Runtime")
local Log = require("./core/Log")
local Env = require("./core/Env")
local Class = require("./core/Class")
local Signal = require("./core/Signal")
local Janitor = require("./core/Janitor")
local Guard = require("./core/Guard")
local Motion = require("./core/Motion")
local Scheduler = require("./core/Scheduler")
local Theme = require("./design/Theme")
local Color = require("./design/Color")
local Tokens = require("./design/Tokens")
local Builder = require("./ui/Builder")
local Root = require("./ui/Root")
local Flags = require("./state/Flags")
local Config = require("./state/Config")
local Locale = require("./state/Locale")
local KeySystem = require("./state/KeySystem")
local Window = require("./components/Window")
local ColorPicker = require("./components/ColorPicker")
local Modal = require("./components/Modal")
local Progress = require("./components/Progress")
local RangeSlider = require("./components/RangeSlider")
local Table = require("./components/Table")
local ContextMenu = require("./ui/ContextMenu")
local Notifications = require("./ui/Notifications")
local Tooltip = require("./ui/Tooltip")
local CommandPalette = require("./ui/CommandPalette")

local Londra = {
	version = Version.version,
	codename = Version.codename,
	Log = Log,
	Theme = Theme,
	Color = Color,
	Tokens = Tokens,
	Env = Env,
	Motion = Motion,
	Scheduler = Scheduler,
	Builder = Builder,
	Class = Class,
	Signal = Signal,
	Janitor = Janitor,
	Guard = Guard,
	WindowClass = Window,
	__inject = function(engine: any)
		Runtime.inject(engine)
		Runtime.reset()
		Env.reset()
	end,
}

local state = {
	root = nil,
	windows = {},
	flags = Flags.new(),
}

function Londra.__inject(engine: any)
	Runtime.inject(engine)
	Runtime.reset()
	Env.reset()
end

function Londra.Info()
	return {
		version = Version.version,
		codename = Version.codename,
		root = state.root and state.root.source or "none",
		env = Env.summary(),
		theme = Theme.list(),
	}
end

function Londra.Stats()
	local instances = 0
	if state.root ~= nil and state.root.gui ~= nil then
		instances = #state.root.gui:GetDescendants()
	end
	return {
		windows = #state.windows,
		controls = 0,
		instances = instances,
		connections = 0,
		queued = Scheduler:stats().queued,
	}
end

function Londra.__setRoot(root: any)
	state.root = root
end

function Londra.__reset()
	for index = #state.windows, 1, -1 do
		local window = state.windows[index]
		if window ~= nil and not window:isDestroyed() then
			window:Destroy()
		end
	end
	table.clear(state.windows)
	if state.root ~= nil then
		state.root.destroy()
		state.root = nil
	end
	state.flags:Destroy()
	state.flags = Flags.new()
	Londra.Flags = state.flags
	Scheduler:stop()
end

function Londra.__root(): any
	if state.root == nil then
		state.root = Root.create()
	end
	return state.root
end

local function focusWindow(target: any)
	for index, window in ipairs(state.windows) do
		if window.frame ~= nil then
			window.frame.ZIndex = Tokens.z.baseMin + index
		end
	end
	local position = 0
	for index, window in ipairs(state.windows) do
		if window == target then
			position = index
			break
		end
	end
	if position > 0 and position < #state.windows then
		table.remove(state.windows, position)
		table.insert(state.windows, target)
		for index, window in ipairs(state.windows) do
			window.frame.ZIndex = Tokens.z.baseMin + index
		end
	end
end

local function windowClosed(target: any)
	for index = #state.windows, 1, -1 do
		if state.windows[index] == target then
			table.remove(state.windows, index)
			break
		end
	end
	if #state.windows == 0 and state.root ~= nil then
		state.root.destroy()
		state.root = nil
	end
end

function Londra:Window(options: any)
	local config = table.clone(options or {})
	local root = Londra.__root()
	local binder = Theme.binder(config.Theme or "night")

	local context = {
		root = root,
		binder = binder,
		layers = root.layers,
		flags = state.flags,
		version = Version.version,
		focusWindow = focusWindow,
		windowClosed = windowClosed,
	}

	local window = Window.new(context, config)
	table.insert(state.windows, window)
	focusWindow(window)
	return window
end

function Londra:SetTheme(name: string)
	Theme.get(name)
	for _, window in ipairs(state.windows) do
		if window.binder ~= nil then
			window.binder:setTheme(name)
		end
	end
end

function Londra:GetFlags(): any
	return state.flags
end

Londra.Flags = state.flags

return Londra
