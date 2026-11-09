--!strict
-- Secure root resolution. gethui first, then CoreGui, then PlayerGui. Every
-- step is pcall guarded and the chosen source is reported instead of hidden.

local Runtime = require("../core/Runtime")
local Env = require("../core/Env")
local Log = require("../core/Log")
local Builder = require("./Builder")
local Layers = require("./Layers")

local Root = {}

local function tryCall(name: string, ...): (boolean, any)
	local fn = Runtime.get()[name]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		return false, nil
	end
	return true, result
end

function Root.resolveParent(): (any, string)
	local capabilities = Env.probe()

	if capabilities.gethui then
		local ok, handle = tryCall("gethui")
		if ok and handle ~= nil then
			return handle, "gethui"
		end
	end

	local okCore, coreGui = pcall(function()
		return Runtime.service("CoreGui")
	end)
	if okCore and coreGui ~= nil then
		return coreGui, "coregui"
	end

	local okPlayers, players = pcall(function()
		return Runtime.service("Players")
	end)
	if okPlayers and players ~= nil and players.LocalPlayer ~= nil then
		local okGui, playerGui = pcall(function()
			return players.LocalPlayer:WaitForChild("PlayerGui")
		end)
		if okGui and playerGui ~= nil then
			return playerGui, "playergui"
		end
	end

	error("Londra: no usable root container", 0)
end

function Root.create(options: any?): any
	local config = options or {}
	local parent, source = Root.resolveParent()
	local capabilities = Env.probe()

	local screen = Builder.new("ScreenGui", {
		Name = config.Name or "Londra",
		DisplayOrder = config.DisplayOrder or 999999,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Runtime.Enum.ZIndexBehavior.Sibling,
	})

	screen.Parent = parent

	if capabilities.protect_gui then
		local ok = tryCall("protect_gui", screen)
		if not ok then
			Log.info("protect_gui failed, continuing unprotected")
		end
	end

	local scaleValue = config.Scale
	if scaleValue == nil then
		local viewport = workspace and workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or nil
		if viewport ~= nil then
			scaleValue = math.clamp(viewport.Y / 1080, 0.85, 1.35)
		else
			scaleValue = 1
		end
	end

	local holder = Builder.frame({
		Name = "Root",
		Size = Runtime.UDim2.fromScale(1, 1),
	})

	local scale = Builder.new("UIScale", { Scale = scaleValue })
	scale.Parent = holder

	local frames = {}
	for _, layer in ipairs({ "base", "popup", "overlay", "toast" }) do
		local frame = Builder.frame({
			Name = layer,
			Size = Runtime.UDim2.fromScale(1, 1),
			ZIndex = 1,
		})
		frame.Parent = holder
		frames[layer] = frame
	end

	holder.Parent = screen

	return {
		gui = screen,
		holder = holder,
		scale = scale,
		source = source,
		layers = Layers.new(frames),
		destroy = function()
			screen:Destroy()
		end,
	}
end

return Root
