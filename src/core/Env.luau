--!strict
-- Executor capability probe. A missing capability must be visible, never
-- silently swallowed: the feature that depends on it degrades and says so.

local Runtime = require("./Runtime")
local Log = require("./Log")

local Env = {}

local CAPABILITIES = {
	"gethui",
	"protect_gui",
	"writefile",
	"readfile",
	"isfolder",
	"makefolder",
	"delfile",
	"setclipboard",
	"gethwid",
	"openbrowser",
	"hookfunction",
	"crypt_hash",
}

local probed: any = nil

local function httpAvailable(): boolean
	local ok, service = pcall(function()
		return Runtime.service("HttpService")
	end)
	if not ok or service == nil then
		return false
	end
	local okJson = pcall(function()
		return service.JSONEncode
	end)
	return okJson
end

function Env.probe(force: boolean?): any
	if probed ~= nil and not force then
		return probed
	end

	local engine = Runtime.get()
	local capabilities = {}

	for _, name in ipairs(CAPABILITIES) do
		capabilities[name] = type(engine[name]) == "function"
	end

	capabilities.http = httpAvailable()

	probed = capabilities

	local missing = {}
	for _, name in ipairs(CAPABILITIES) do
		if not capabilities[name] then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		Log.info("executor capabilities missing: %s", table.concat(missing, ", "))
	end

	return probed
end

function Env.has(name: string): boolean
	return Env.probe()[name] == true
end

function Env.reset()
	probed = nil
end

function Env.summary(): string
	local capabilities = Env.probe()
	local available = {}
	for name, value in pairs(capabilities) do
		if value then
			table.insert(available, name)
		end
	end
	table.sort(available)
	return table.concat(available, ",")
end

return Env
