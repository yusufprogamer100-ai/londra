--!nocheck
-- Headless Roblox runtime. Enough of the engine to exercise every code path the
-- library owns, including the degraded executor paths.

local Mock = {}

Mock.created = 0
Mock.destroyed = 0
Mock.stepCount = 0
Mock.clock = 0
Mock.descendantCalls = 0
Mock.capabilities = {}
Mock.responses = {}
Mock.logs = {}

local function signal()
	local handlers = {}
	local api = {}
	function api:Connect(fn)
		local handler = { fn = fn, alive = true }
		table.insert(handlers, handler)
		local connection = { Connected = true }
		function connection:Disconnect()
			handler.alive = false
			connection.Connected = false
			for index = #handlers, 1, -1 do
				if handlers[index] == handler then
					table.remove(handlers, index)
					break
				end
			end
		end
		return connection
	end
	function api:Once(fn)
		local connection
		connection = api:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function api:Fire(...)
		for _, handler in ipairs(table.clone(handlers)) do
			if handler.alive then
				handler.fn(...)
			end
		end
	end
	function api:GetCount()
		return #handlers
	end
	function api:DisconnectAll()
		for _, handler in ipairs(handlers) do
			handler.alive = false
		end
		table.clear(handlers)
	end
	return api
end

Mock.signal = signal

-- ---------------------------------------------------------------- value types

local Color3 = {}
Color3.__index = Color3

function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end

function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

local function hueToRgb(p, q, t)
	if t < 0 then
		t += 1
	elseif t > 1 then
		t -= 1
	end
	if t < 1 / 6 then
		return p + (q - p) * 6 * t
	end
	if t < 1 / 2 then
		return q
	end
	if t < 2 / 3 then
		return p + (q - p) * (2 / 3 - t) * 6
	end
	return p
end

function Color3.fromHSV(h, s, v)
	local hue = (h % 1) * 360 / 360
	local sat = math.clamp(s or 0, 0, 1)
	local val = math.clamp(v or 0, 0, 1)
	if sat == 0 then
		return Color3.new(val, val, val)
	end
	local q = val < 0.5 and val * (1 + sat) or val + sat - val * sat
	local p = 2 * val - q
	return Color3.new(hueToRgb(p, q, hue + 1 / 3), hueToRgb(p, q, hue), hueToRgb(p, q, hue - 1 / 3))
end

function Color3.toHSV(color)
	local r, g, b = color.R, color.G, color.B
	local max = math.max(r, g, b)
	local min = math.min(r, g, b)
	local delta = max - min
	local h = 0
	if delta ~= 0 then
		if max == r then
			h = ((g - b) / delta) % 6
		elseif max == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h = h / 6
	end
	local s = max == 0 and 0 or delta / max
	return h, s, max
end

function Color3:Lerp(other, alpha)
	return Color3.new(
		self.R + (other.R - self.R) * alpha,
		self.G + (other.G - self.G) * alpha,
		self.B + (other.B - self.B) * alpha
	)
end

Color3.__tostring = function(self)
	return string.format("Color3(%0.3f, %0.3f, %0.3f)", self.R, self.G, self.B)
end

local Vector2 = {}
Vector2.__index = Vector2

function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end

Vector2.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
Vector2.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2.__mul = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
Vector2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2.__tostring = function(self)
	return string.format("Vector2(%0.1f, %0.1f)", self.X, self.Y)
end

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end

local UDim = {}
UDim.__index = UDim
function UDim.new(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDim)
end

local UDim2 = {}
UDim2.__index = UDim2
function UDim2.new(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UDim2)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
UDim2.__tostring = function(self)
	return "UDim2"
end

local CFrame = {}
CFrame.__index = CFrame
function CFrame.new()
	return setmetatable({}, CFrame)
end

local NumberRange = {}
NumberRange.__index = NumberRange
function NumberRange.new(a, b)
	return setmetatable({ Min = a, Max = b or a }, NumberRange)
end

local TweenInfo = {}
TweenInfo.__index = TweenInfo
function TweenInfo.new(duration, style, direction, repeatCount, reverses, delay)
	return setmetatable({
		Time = duration or 0,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delay or 0,
	}, TweenInfo)
end

-- ---------------------------------------------------------------- enum shim

local function enumCategory(name)
	local category = { EnumType = name }
	return setmetatable(category, {
		__index = function(self, key)
			local item = {
				Name = key,
				Value = 1000 + #tostring(key),
				EnumType = name,
			}
			rawset(self, key, item)
			return item
		end,
	})
end

local Enum = setmetatable({}, {
	__index = function(self, key)
		local category = enumCategory(key)
		rawset(self, key, category)
		return category
	end,
})

-- ---------------------------------------------------------------- instances

local instanceSet = setmetatable({}, { __mode = "k" })
local methods = {}

local hierarchy = {
	Frame = { "GuiObject", "GuiBase2d" },
	ScrollingFrame = { "GuiObject", "GuiBase2d" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiObject", "GuiBase2d" },
	ImageLabel = { "GuiObject", "GuiBase2d" },
	ImageButton = { "GuiObject", "GuiBase2d" },
	TextBox = { "GuiObject", "GuiBase2d" },
	ScreenGui = { "LayerCollector", "GuiBase2d" },
	BillboardGui = { "LayerCollector", "GuiBase2d" },
	PlayerGui = { "BasePlayerGui" },
	CoreGui = { "BasePlayerGui" },
	UICorner = { "UIComponent" },
	UIStroke = { "UIComponent" },
	UIPadding = { "UIComponent" },
	UIListLayout = { "UIGridStyleLayout", "UILayout" },
	UIGridLayout = { "UIGridStyleLayout", "UILayout" },
	UIScale = { "UIComponent" },
	UIAspectRatioConstraint = { "UIConstraint", "UIComponent" },
	UISizeConstraint = { "UIConstraint", "UIComponent" },
	UITextSizeConstraint = { "UIConstraint", "UIComponent" },
	BlurEffect = { "PostEffect" },
	Lighting = {},
	Workspace = {},
	Folder = {},
	TextService = {},
}

local instanceMt = {}

local lazySignals = {
	MouseEnter = true,
	MouseLeave = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	InputBegan = true,
	InputChanged = true,
	InputEnded = true,
	FocusLost = true,
	Focused = true,
	ReturnPressed = true,
	TextChanged = true,
	Activated = true,
}

instanceMt.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	if lazySignals[key] then
		local signals = rawget(self, "_signals")
		local created = signals[key]
		if created == nil then
			created = signal()
			signals[key] = created
		end
		return created
	end
	local method = methods[key]
	if method ~= nil then
		return method
	end
	return nil
end

instanceMt.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old == value then
			return
		end
		if old ~= nil then
			local siblings = rawget(old, "_children")
			if siblings ~= nil then
				for index = #siblings, 1, -1 do
					if siblings[index] == self then
						table.remove(siblings, index)
						break
					end
				end
			end
		end
		rawset(self, "_parent", value)
		if value ~= nil then
			table.insert(rawget(value, "_children"), self)
		end
		return
	end

	local previous = rawget(self, key)
	rawset(self, key, value)
	if previous ~= value then
		local signals = rawget(self, "_signals")
		local changed = signals and signals[key]
		if changed ~= nil then
			changed:Fire(value)
		end
		local any = signals and signals["*"]
		if any ~= nil then
			any:Fire(key)
		end
	end
end

local Instance = {}

function Instance.new(className, parent)
	Mock.created += 1
	local object = setmetatable({
		ClassName = className,
		Name = className,
		_children = {},
		_signals = {},
		_parent = nil,
		_destroyed = false,
		_attributes = {},
		Visible = true,
		Enabled = true,
		Active = true,
		Selectable = true,
		ZIndex = 1,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		TextColor3 = Color3.fromRGB(0, 0, 0),
		TextTransparency = 0,
		ImageTransparency = 0,
		BorderSizePixel = 1,
		Text = "",
		TextSize = 14,
		TextWrapped = false,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromOffset(100, 100),
		Position = UDim2.fromOffset(0, 0),
		AnchorPoint = Vector2.new(0, 0),
		AbsoluteSize = Vector2.new(100, 100),
		AbsolutePosition = Vector2.new(0, 0),
		ClipsDescendants = false,
		LayoutOrder = 0,
		Rotation = 0,
		AutomaticSize = Enum.AutomaticSize.None,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, 0),
		CanvasPosition = Vector2.new(0, 0),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0),
		Image = "",
		ImageColor3 = Color3.fromRGB(255, 255, 255),
		CornerRadius = UDim.new(0, 0),
		Thickness = 1,
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0,
		Padding = UDim.new(0, 0),
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Width,
		MaxTextSize = 100,
		MinTextSize = 1,
		TextBounds = Vector2.new(0, 0),
		PlaceholderText = "",
		MultiLine = false,
		ClearTextOnFocus = false,
		TextEditable = true,
		Modal = false,
		IgnoreGuiInset = false,
		DisplayOrder = 0,
		ResetOnSpawn = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, instanceMt)
	instanceSet[object] = true
	if parent ~= nil then
		object.Parent = parent
	end
	return object
end

function methods:IsA(className)
	local own = rawget(self, "ClassName")
	if own == className then
		return true
	end
	local chain = hierarchy[own]
	if chain ~= nil then
		for _, name in ipairs(chain) do
			if name == className then
				return true
			end
		end
	end
	return className == "Instance"
end

function methods:GetChildren()
	return table.clone(rawget(self, "_children"))
end

function methods:GetDescendants()
	Mock.descendantCalls += 1
	local out = {}
	local function walk(node)
		for _, child in ipairs(rawget(node, "_children")) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function methods:FindFirstChild(name, recursive)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(rawget(self, "_children")) do
			local found = child:FindFirstChild(name, true)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

function methods:FindFirstChildOfClass(className)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function methods:FindFirstChildWhichIsA(className)
	for _, child in ipairs(rawget(self, "_children")) do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

function methods:WaitForChild(name)
	local found = self:FindFirstChild(name)
	if found == nil then
		error("mock WaitForChild timeout: " .. tostring(name), 2)
	end
	return found
end

function methods:GetPropertyChangedSignal(property)
	local signals = rawget(self, "_signals")
	local existing = signals[property]
	if existing == nil then
		existing = signal()
		signals[property] = existing
	end
	return existing
end

function methods:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end

function methods:CaptureFocus()
	self._focused = true
	local signals = rawget(self, "_signals")
	if signals.Focused ~= nil then
		signals.Focused:Fire()
	end
end

function methods:ReleaseFocus()
	self._focused = false
	local signals = rawget(self, "_signals")
	if signals.FocusLost ~= nil then
		signals.FocusLost:Fire(false, nil)
	end
end

function methods:SetAttribute(name, value)
	rawget(self, "_attributes")[name] = value
end

function methods:GetFullName()
	local parts = { self.Name }
	local node = rawget(self, "_parent")
	while node ~= nil do
		table.insert(parts, 1, node.Name)
		node = rawget(node, "_parent")
	end
	return table.concat(parts, ".")
end

function methods:ClearAllChildren()
	for _, child in ipairs(table.clone(rawget(self, "_children"))) do
		child:Destroy()
	end
end

function methods:Destroy()
	if rawget(self, "_destroyed") then
		return
	end
	rawset(self, "_destroyed", true)
	for _, child in ipairs(table.clone(rawget(self, "_children"))) do
		child:Destroy()
	end
	table.clear(rawget(self, "_children"))
	local parent = rawget(self, "_parent")
	if parent ~= nil then
		local siblings = rawget(parent, "_children")
		for index = #siblings, 1, -1 do
			if siblings[index] == self then
				table.remove(siblings, index)
				break
			end
		end
		rawset(self, "_parent", nil)
	end
	Mock.destroyed += 1
end

function methods:Clone()
	local copy = Instance.new(self.ClassName)
	for key, value in pairs(self) do
		if type(key) == "string" and string.sub(key, 1, 1) ~= "_" and key ~= "Parent" and key ~= "ClassName" then
			copy[key] = value
		end
	end
	return copy
end

-- ---------------------------------------------------------------- services

local RunService = { Heartbeat = signal(), RenderStepped = signal(), Stepped = signal() }
local TweenService = {}
local UserInputService = {
	InputBegan = signal(),
	InputChanged = signal(),
	InputEnded = signal(),
	TouchEnabled = false,
	MouseEnabled = true,
	KeyboardEnabled = true,
}
local GuiService = { SelectedObject = nil }
local HttpService = {}
local Players = {}
local CoreGui = Instance.new("CoreGui")
local Lighting = Instance.new("Lighting")
local Workspace = Instance.new("Workspace")
Workspace.CurrentCamera = { ViewportSize = Vector2.new(1920, 1080) }
local TextService = {}

local game = { PlaceId = 1234, JobId = "mock-job", _services = {} }

function game:GetService(name)
	local existing = self._services[name]
	if existing ~= nil then
		return existing
	end
	local service
	if name == "RunService" then
		service = RunService
	elseif name == "TweenService" then
		service = TweenService
	elseif name == "UserInputService" then
		service = UserInputService
	elseif name == "GuiService" then
		service = GuiService
	elseif name == "HttpService" then
		service = HttpService
	elseif name == "Players" then
		service = Players
	elseif name == "CoreGui" then
		service = CoreGui
	elseif name == "Lighting" then
		service = Lighting
	elseif name == "Workspace" then
		service = Workspace
	elseif name == "TextService" then
		service = TextService
	elseif name == "RbxAnalyticsService" then
		service = { GetClientId = function()
			return "mock-client-id"
		end }
	else
		service = Instance.new(name)
	end
	self._services[name] = service
	return service
end

function game:IsLoaded()
	return true
end

function game:GetDescendants()
	return {}
end

Players.LocalPlayer = {
	Name = "MockPlayer",
	UserId = 1,
	PlayerGui = Instance.new("PlayerGui"),
	GetAttribute = function()
		return nil
	end,
}

function TweenService:Create(instance, info, goal)
	local tween = { _cancelled = false, Completed = signal(), _instance = instance, _goal = goal }
	function tween:Play()
		if self._cancelled then
			return
		end
		for property, value in pairs(self._goal) do
			self._instance[property] = value
		end
		self.Completed:Fire(Enum.PlaybackState.Completed)
	end
	function tween:Cancel()
		self._cancelled = true
	end
	function tween:Pause() end
	return tween
end

function UserInputService:GetMouseLocation()
	return Vector2.new(400, 300)
end

function UserInputService:GetKeysPressed()
	return {}
end

GuiService.GetGuiInset = function()
	return Vector2.new(0, 58), Vector2.new(0, 36)
end

function GuiService:GetGuiInset()
	return Vector2.new(0, 58), Vector2.new(0, 36)
end

-- ---------------------------------------------------------------- json

local function isArray(value)
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" then
			return false
		end
		count += 1
	end
	if count == 0 then
		return false
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return true
end

local function encode(value)
	local kind = type(value)
	if value == nil then
		return "null"
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		if math.floor(value) == value then
			return string.format("%d", value)
		end
		return string.format("%.14g", value)
	elseif kind == "string" then
		return string.format("%q", value):gsub("\\\n", "\\n")
	elseif kind == "table" then
		if isArray(value) then
			local parts = {}
			for _, item in ipairs(value) do
				table.insert(parts, encode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for key, item in pairs(value) do
			if item ~= nil then
				table.insert(parts, string.format("%q", tostring(key)) .. ":" .. encode(item))
			end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local function decode(text)
	local index = 1
	local length = #text

	local function skip()
		while index <= length do
			local char = string.sub(text, index, index)
			if char == " " or char == "\t" or char == "\n" or char == "\r" then
				index += 1
			else
				break
			end
		end
	end

	local parseValue

	local function parseString()
		local quote = string.sub(text, index, index)
		index += 1
		local out = {}
		while index <= length do
			local char = string.sub(text, index, index)
			if char == "\\" then
				local nextChar = string.sub(text, index + 1, index + 1)
				if nextChar == "n" then
					table.insert(out, "\n")
				elseif nextChar == "t" then
					table.insert(out, "\t")
				elseif nextChar == "r" then
					table.insert(out, "\r")
				elseif nextChar == "b" then
					table.insert(out, "\b")
				elseif nextChar == "f" then
					table.insert(out, "\f")
				elseif nextChar == "u" then
					local hex = string.sub(text, index + 2, index + 5)
					local code = tonumber(hex, 16) or 63
					table.insert(out, utf8.char(code))
					index += 4
				else
					table.insert(out, nextChar)
				end
				index += 2
			elseif char == quote then
				index += 1
				return table.concat(out)
			else
				table.insert(out, char)
				index += 1
			end
		end
		error("mock json: unterminated string", 0)
	end

	function parseValue()
		skip()
		local char = string.sub(text, index, index)
		if char == "{" then
			index += 1
			local object = {}
			skip()
			if string.sub(text, index, index) == "}" then
				index += 1
				return object
			end
			while true do
				skip()
				local key = parseString()
				skip()
				index += 1
				object[key] = parseValue()
				skip()
				local delimiter = string.sub(text, index, index)
				index += 1
				if delimiter == "}" then
					return object
				end
			end
		elseif char == "[" then
			index += 1
			local array = {}
			skip()
			if string.sub(text, index, index) == "]" then
				index += 1
				return array
			end
			while true do
				table.insert(array, parseValue())
				skip()
				local delimiter = string.sub(text, index, index)
				index += 1
				if delimiter == "]" then
					return array
				end
			end
		elseif char == '"' then
			return parseString()
		elseif string.sub(text, index, index + 3) == "true" then
			index += 4
			return true
		elseif string.sub(text, index, index + 4) == "false" then
			index += 5
			return false
		elseif string.sub(text, index, index + 3) == "null" then
			index += 4
			return nil
		else
			local start = index
			while index <= length do
				local current = string.sub(text, index, index)
				if current == "," or current == "}" or current == "]" or current == " " or current == "\n" then
					break
				end
				index += 1
			end
			local number = tonumber(string.sub(text, start, index - 1))
			if number == nil then
				error("mock json: invalid value at " .. tostring(start), 0)
			end
			return number
		end
	end

	local result = parseValue()
	return result
end

function HttpService:JSONEncode(value)
	return encode(value)
end

function HttpService:JSONDecode(text)
	return decode(text)
end

function HttpService:GenerateGUID()
	return string.format("%08x-0000-4000-8000-%012x", Mock.created, Mock.stepCount)
end

function HttpService:RequestAsync(request)
	local queued = table.remove(Mock.responses, 1)
	if queued == nil then
		return { Success = false, StatusCode = 0, StatusMessage = "no mock response", Body = "" }
	end
	if type(queued) == "function" then
		return queued(request)
	end
	return queued
end

function TextService:GetTextSize(text, size, font, bounds)
	return Vector2.new(#tostring(text) * (size or 14) * 0.55, size or 14)
end

-- ---------------------------------------------------------------- executor

local runtime = {
	game = game,
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
	workspace = Workspace,
	typeof = function(value)
		if instanceSet[value] then
			return "Instance"
		end
		if type(value) == "table" then
			local meta = getmetatable(value)
			if meta == Color3 then
				return "Color3"
			elseif meta == Vector2 then
				return "Vector2"
			elseif meta == UDim2 then
				return "UDim2"
			elseif meta == UDim then
				return "UDim"
			elseif meta == TweenInfo then
				return "TweenInfo"
			end
		end
		return type(value)
	end,
	task = {
		spawn = function(fn, ...)
			return fn(...)
		end,
		defer = function(fn, ...)
			return fn(...)
		end,
		delay = function(_, fn, ...)
			return fn(...)
		end,
		wait = function()
			error("mock: task.wait is not available in headless tests", 0)
		end,
	},
	warn = function(...)
		table.insert(Mock.logs, table.concat({ ... }, " "))
	end,
	tick = function()
		return Mock.clock
	end,
}

-- Capabilities default to a fully featured executor. Tests disable them.
runtime.gethui = function()
	return CoreGui
end
runtime.protect_gui = function() end
runtime.writefile = function(path, contents)
	Mock.files = Mock.files or {}
	Mock.files[path] = contents
end
runtime.readfile = function(path)
	return Mock.files and Mock.files[path]
end
runtime.isfolder = function(path)
	return Mock.folders ~= nil and Mock.folders[path] == true
end
runtime.makefolder = function(path)
	Mock.folders = Mock.folders or {}
	Mock.folders[path] = true
end
runtime.delfile = function(path)
	if Mock.files then
		Mock.files[path] = nil
	end
end
runtime.setclipboard = function(text)
	Mock.clipboard = text
end
runtime.gethwid = function()
	return "MOCK-HWID-0001"
end
runtime.openbrowser = function(url)
	Mock.opened = url
end

function Mock.disable(capability)
	runtime[capability] = nil
end

function Mock.enable(capability, value)
	runtime[capability] = value or function() end
end

function Mock.step(dt)
	Mock.stepCount += 1
	Mock.clock += dt or (1 / 60)
	RunService.Heartbeat:Fire(dt or (1 / 60))
end

function Mock.input(inputType, keyCode, gameProcessed)
	UserInputService.InputBegan:Fire({
		UserInputType = inputType or Enum.UserInputType.MouseButton1,
		KeyCode = keyCode or Enum.KeyCode.Unknown,
		Position = Vector3.new(400, 300, 0),
	}, gameProcessed or false)
end

Mock.pointer = Vector2.new(400, 300)

function Mock.press(x, y)
	Mock.pointer = Vector2.new(x, y)
	UserInputService.InputBegan:Fire({
		UserInputType = Enum.UserInputType.MouseButton1,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(x, y, 0),
	}, false)
end

function Mock.move(x, y)
	Mock.pointer = Vector2.new(x, y)
	UserInputService.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(x, y, 0),
	}, false)
end

function Mock.release(x, y)
	UserInputService.InputEnded:Fire({
		UserInputType = Enum.UserInputType.MouseButton1,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(x or Mock.pointer.X, y or Mock.pointer.Y, 0),
	}, false)
end

function Mock.key(keyCode, gameProcessed)
	UserInputService.InputBegan:Fire({
		UserInputType = Enum.UserInputType.Keyboard,
		KeyCode = keyCode,
		Position = Vector3.new(Mock.pointer.X, Mock.pointer.Y, 0),
	}, gameProcessed or false)
end

function Mock.reset()
	Mock.created = 0
	Mock.destroyed = 0
	Mock.stepCount = 0
	Mock.clock = 0
	Mock.files = {}
	Mock.folders = {}
	Mock.logs = {}
	Mock.responses = {}
	Mock.clipboard = nil
	Mock.opened = nil
	for _, child in ipairs(CoreGui:GetChildren()) do
		child:Destroy()
	end
	for _, child in ipairs(Players.LocalPlayer.PlayerGui:GetChildren()) do
		child:Destroy()
	end
end

Mock.runtime = runtime
Mock.game = game
Mock.services = {
	RunService = RunService,
	TweenService = TweenService,
	UserInputService = UserInputService,
	GuiService = GuiService,
	HttpService = HttpService,
	Players = Players,
	CoreGui = CoreGui,
	Lighting = Lighting,
}
Mock.Enum = Enum
Mock.Color3 = Color3
Mock.Vector2 = Vector2
Mock.UDim2 = UDim2
Mock.UDim = UDim
Mock.Instance = Instance

return Mock
