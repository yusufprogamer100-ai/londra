--!strict
-- Motion is a single code path with two behaviours: real tween, or instant
-- assignment when reduced motion is on. No parallel animation system to keep in
-- sync.

local Runtime = require("./Runtime")

local Motion = {}

local reduced = false

local DEFAULTS = {
	state = 0.12,
	open = 0.18,
	close = 0.14,
	press = 0.08,
	toast = 0.22,
}

function Motion.setReduced(value: boolean)
	reduced = value == true
end

function Motion.isReduced(): boolean
	return reduced
end

function Motion.duration(kind: string?): number
	if reduced then
		return 0
	end
	return DEFAULTS[kind or "state"] or DEFAULTS.state
end

function Motion.tween(instance: any, goal: any, options: any?): any
	options = options or {}
	local duration = options.duration
	if duration == nil then
		duration = reduced and 0 or DEFAULTS.state
	end
	if reduced then
		duration = 0
	end

	if duration <= 0 then
		for property, value in pairs(goal) do
			instance[property] = value
		end
		return {
			Cancel = function() end,
			Complete = function() end,
		}
	end

	local info = Runtime.TweenInfo.new(
		duration,
		options.easing or Runtime.Enum.EasingStyle.Quad,
		options.direction or Runtime.Enum.EasingDirection.Out,
		0,
		false,
		0
	)
	local tween = Runtime.service("TweenService"):Create(instance, info, goal)
	tween:Play()

	return {
		Cancel = function()
			pcall(function()
				tween:Cancel()
			end)
		end,
		Complete = function()
			pcall(function()
				tween:Play()
			end)
		end,
		tween = tween,
	}
end

function Motion.fade(instance: any, target: number, options: any?): any
	return Motion.tween(instance, { BackgroundTransparency = target }, options)
end

-- Reusable press feedback. The UIScale is created once per element.
function Motion.press(instance: any, scale: number?): any
	local runtime = Runtime
	local uiscale = instance:FindFirstChild("__londra_press")
	if uiscale == nil then
		uiscale = runtime.Instance.new("UIScale")
		uiscale.Name = "__londra_press"
		uiscale.Parent = instance
	end
	return Motion.tween(uiscale, { Scale = scale or 0.985 }, { duration = Motion.duration("press") })
end

function Motion.release(instance: any): any
	local uiscale = instance:FindFirstChild("__londra_press")
	if uiscale == nil then
		return nil
	end
	return Motion.tween(uiscale, { Scale = 1 }, { duration = Motion.duration("press") })
end

return Motion
