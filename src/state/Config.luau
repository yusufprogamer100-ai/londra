--!strict
-- Configuration system. Handles saving/loading config JSON, migrations, and
-- provides a default config for the key system.

local Runtime = require("../core/Runtime")
local Log = require("../core/Log")

local Config = {}

Config.configs = {} -- name -> { savedAt, flags, window }
Config.defaultSchema = 1
Config.migrations = {}

function Config:Save(name: string)
	local flags = Londra:GetFlags():Snapshot()
	local now = tick()
	local schema = 1
	
	local config = {
		schema = schema,
		savedAt = now,
		flags = flags,
		window = {
			size = Londra.__root().gui.AbsoluteSize,
			position = Londra.__root().gui.AbsolutePosition,
			theme = Londres__getCurrentTheme or "night",
		},
	}
	
	self.configs[name] = config
	
	-- Write to disk if writefile available
	local ok, err = pcall(function()
		writefile("Londra/" .. name .. ".json", game:GetService("HttpService"):JSONEncode(config))
	end)
	
	if not ok then
		Log.info("Config: save to disk skipped (" .. tostring(err) .. ")")
	end
	
	return config
end

function Config:Load(name: string): boolean
	local config = self.configs[name]
	if config == nil then
		Log.warn("Config: '" .. name .. "' not found")
		return false
	end
	
	-- Apply flags
	local flags = Londra:GetFlags()
	local applied = flags:Load(config.flags)
	
	-- Apply window geometry if root exists
	if config.window then
		local root = Londra.__root()
		if root and root.gui then
			-- geometry loading would go here
		end
	end
	
	return true
end

function Config:List(): { string }
	local names = {}
	for name in pairs(self.configs) do
		table.insert(names, name)
	end
	return names
end

function Config:Delete(name: string)
	self.configs[name] = nil
	Log.info("Config: deleted '" .. name .. "'")
end

function Config:Export(name: string): string?
	local config = self.configs[name]
	if config == nil then
		return nil
	end
	return game:GetService("HttpService"):JSONEncode(config)
end

function Config:Import(json: string, name: string?)
	local success, config = pcall(function()
		return game:GetService("HttpService"):JSONDecode(json)
	end)
	
	if success and config then
		local nameToUse = name or "imported"
		self.configs[nameToUse] = config
		Log.info("Config: imported '" .. nameToUse .. "'")
		return nameToUse
	end
	
	return nil
end

function Config:migrate(name: string, migrateFn)
	self.migrations[name] = migrateFn
end

function Config:applyMigrations(name: string)
	local config = self.configs[name]
	if config == nil then return end
	
	local migration = self.migrations[name]
	if migration then
		migration(config)
		Log.info("Config: applied migrations for '" .. name .. "'")
	end
end

return Config