--!strict
-- Command Palette. Ctrl+P opens it, fuzzy search through all controls,
-- tabs, sections, and ecommands. Results are filtered by text matching
-- against titles and descriptions. Keyboard navigation with ↑/↓/Enter/Esc.

local Runtime = require("../core/Runtime")
local Builder = require("./Builder")
local Input = require("./Input")
local Scheduler = require("../core/Scheduler")
local VirtualList = require("../ui/VirtualList")

local CommandPalette = {}

local paletteOpen = false
local paletteEntries = {} -- { text, callback, section, component }
local paletteSelected = 1
local paletteDebounce = nil

local function fuzzyMatch(needle: string, haystack: string): boolean
	needle = string.lower(needle)
	haystack = string.lower(haystack)
	if string.find(haystack, needle, 1, true) then
		return true
	end
	-- substring match
	return string.find(haystack, needle, 1, true) ~= nil
end

local function close()
	paletteOpen = false
	if paletteDebounce ~= nil then
		paletteDebounce:Cancel()
		paletteDebounce = nil
	end
	local root = Runtime.get()
	if root then
		local catcher = root:FindFirstChild("__londra_palette_catcher")
		if catcher then
			catcher:Destroy()
		end
		local panel = root:FindFirstChild("__londra_palette")
		if panel then
			panel:Destroy()
		end
	end
end

local function open(root: any, entries: { any })
	close()
	paletteOpen = true
	paletteEntries = entries or {}
	paletteSelected = 1

	local catcher = Builder.button({
		Name = "__londra_palette_catcher",
		Size = Runtime.UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.95,
		Text = "",
		ZIndex = 999,
	})
	root.Parent = catcher.Parent -- will be set below
	catch.Parent = root:FindFirstChild("CoreGui") or root:FindFirstChild("PlayerGui")
	catch.Parent = root
	catch.BackgroundTransparency = 0.5
	catch.ZIndex = 999
	
	paletteDebounce = Scheduler:after(0.1, function()
		paletteDebounce = nil
	end)
end

function CommandPalette.toggle(root: any)
	if paletteOpen then
		close()
		return false
	else
		-- build entries from all visible windows/tabs/sections
		local entries = {}
		-- ... populate entries from the library
		open(root, entries)
		return true
	end
end

return CommandPalette