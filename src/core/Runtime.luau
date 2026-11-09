--!strict
-- Engine access point.
-- Modules never touch Roblox globals directly, so the same code runs inside a
-- real executor and inside the headless test harness. Lookups are lazy: the
-- runtime is resolved on first property access, never at require time.

local Runtime = {}

local current: any = nil

local function detect(): any
	local ok, engine = pcall(function()
		return game
	end)
	if not ok or engine == nil then
		return nil
	end
	return {
		game = engine,
		Instance = Instance,
		Enum = Enum,
		Color3 = Color3,
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		TweenInfo = TweenInfo,
		NumberRange = NumberRange,
		workspace = workspace,
		typeof = typeof,
		task = task,
		warn = warn,
		tick = tick,
	}
end

function Runtime.inject(engine: any)
	current = engine
end

function Runtime.get(): any
	if current ~= nil then
		return current
	end
	current = detect()
	if current == nil then
		error("Londra: no runtime available. Call Londra.__inject(runtime) before use.", 0)
	end
	return current
end

local services: { [string]: any } = {}

function Runtime.service(name: string): any
	local cached = services[name]
	if cached ~= nil then
		return cached
	end
	local engine = Runtime.get()
	local ok, service = pcall(function()
		return engine.game:GetService(name)
	end)
	if not ok or service == nil then
		error("Londra: service unavailable: " .. name, 0)
	end
	services[name] = service
	return service
end

function Runtime.reset()
	services = {}
end

return setmetatable(Runtime, {
	__index = function(_, key)
		return Runtime.get()[key]
	end,
})
