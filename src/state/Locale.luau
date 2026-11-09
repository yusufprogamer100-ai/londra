--!strict
-- Locale system. Provides string tables for multiple languages with a
-- `t()` function for localized text lookup. Falls back to English when a
-- translation key is not found.

local Locale = {}

-- English strings (default)
Locale.strings = {
	-- Window
	window = {
		title = "Londra",
	},
	-- Controls
	controls = {
		slider = "Slider",
		textbox = "Textbox",
		dropdown = "Dropdown",
		keybind = "Keybind",
	},
	-- Config
	config = {
		loaded = "Config loaded",
		saved = "Config saved",
	},
	-- Key system
	key_system = {
		hwid = "HWID",
		enter_key = "Enter key",
		validate = "Validate",
	},
	-- Generic
	generic = {
		ok = "OK",
		cancel = "Cancel",
		yes = "Yes",
		no = "No",
	},
}

-- Current locale
Locale.current = "en"

-- Set the current locale
function Locale:set(locale: string)
	self.current = locale
end

-- Get the current locale
function Locale:get(): string
	return self.current
end

-- Get localized string
function Locale:t(key: string, ...: any): string
	local strings = self.strings
	local parts = string.split(key, ".")
	
	local section = strings
	for _, part in ipairs(parts) do
		if section[part] ~= nil then
			section = section[part]
		else
			-- fallback: try without dots
			local colonPos = string.find(key, ".", 1, true)
			if colonPos then
				local before = string.sub(key, 1, colonPos - 1)
				local after = string.sub(key, colonPos + 1)
				local result = self:t(before, ...)
				if result ~= "" then
					return result .. " " .. self:t(after, ...)
				end
			end
			return key
		end
	end
	
	if type(section) == "string" then
		return string.format(section, ...)
	else
		return key
	end
end

-- Add strings for a locale
function Locale:add(localeName: string, newStrings: { any })
	self.strings[localeName] = newStrings
end

return Locale