--!strict
-- Key System. Provides a client-side key validation system with multiple
-- provider types (Local, Http, Custom). The key system has a status machine
-- (idle -> checking -> granted/denied) and UI states.

local KeySystem = {}

KeySystem.State = {
	idle = "idle",
	checking = "checking",
	granted = "granted",
	denied = "denied",
	failed = "failed",
}

KeySystem.Provider = {
	local = "local",
	http = "http",
	custom = "custom",
}

KeySystem.Status = {
	valid = "valid",
	invalid = "invalid",
	expired = "expired",
	unknown = "unknown",
}

-- Default HWID generation
function KeySystem.getDefaultHwid()
	return "LONDRA-MOCK-" .. tostring(math.random(100000, 999999))
end

-- Key validation result
---@param result { valid: boolean, message?: string, expiresAt?: number }
function KeySystem.validate(result, storedHwid)
	-- Check HWID match
	if storedHwid and storedHwid ~= "" then
		if result.valid and result.hwid ~= storedHwid then
			return {
				valid = false,
				message = "HWID mismatch",
				status = KeySystem.Status.invalid,
			}
		end
	end
	
	if result.valid then
		return {
			valid = true,
			message = result.message or "Valid key",
			status = KeySystem.Status.valid,
			expiresAt = result.expiresAt,
		}
	else
		return {
			valid = false,
			message = result.message or "Invalid key",
			status = KeySystem.Status.invalid,
		}
	end
end

-- Provider interface
---@class KeyProvider
---@field Check fun(ctx: { key: string, hwid: string, placeId: number }): (boolean, string?, number?)

-- Local provider: fixed list or hash comparison
function KeySystem.Provider.Local(keys, hwid)
	return function(ctx)
		local key = ctx.key:upper()
		local storedKey = keys[key]
		
		if storedKey then
			-- Hash comparison
			if type(storedKey) == "function" then
				local ok, _ = pcall(storedKey, ctx.hwid)
				return ok, storedKey and "Hash verified" or "Hash mismatch"
			end
			
			-- Direct comparison
			if storedKey:upper() == key then
				return true, "Key verified"
			end
		end
		
		return false, "Key not found"
	end
end

-- Http provider: HTTP request to validation endpoint
function KeySystem.Provider.Http(validateUrl, timeout)
	local http = game:GetService("HttpService")
	local request = game:GetService("game").HttpRequest
	
	return function(ctx)
		local success, body = pcall(function()
			local req = http:RequestAsync({
				Url = validateUrl,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
				},
				Body = http:JSONEncode({
					key = ctx.key,
					hwid = ctx.hwid,
					placeId = ctx.placeId,
				}),
			})
			return http:JSONDecode(body)
		end)
		
		if success and body then
			return KeySystem.validate(body, ctx.hwid)
		end
		
		return {
			valid = false,
			message = "Validation request failed",
			status = KeySystem.Status.unknown,
		}
	end
end

-- Custom provider: user-defined function
function KeySystem.Provider.Custom(checkFn)
	return checkFn
end

-- Key system state
KeySystem.state = KeySystem.State.idle
KeySystem.hwid = KeySystem.getDefaultHwid()
KeySystem.key = nil
KeySystem.expiresAt = nil
KeySystem.provider = nil
KeySystem.attempts = 0
KeySystem.maxAttempts = 3

function KeySystem:setState(newState)
	self.state = newState
	-- Notify UI of state change
	if self.onStateChanged then
		self:onStateChanged(newState)
	end
end

function KeySystem:checkKey(key, hwid, placeId, provider)
	self:setState(KeySystem.State.checking)
	self.attempts += 1
	
	local ctx = {
		key = key:upper(),
		hwid = hwid or self.hwid,
		placeId = placeId or 0,
	}
	
	if self.provider and self.provider.check then
		local success, message, expiresAt = self.provider.check(ctx)
		local result = KeySystem.validate({ valid = success, message = message, hwid = ctx.hwid }, ctx.hwid)
		
		if result.valid then
			self:setState(KeySystem.State.granted)
			self.key = key
			self.expiresAt = expiresAt
			if self.onGranted then
				self:onGranted()
			end
		else
			self:setState(KeySystem.State.denied)
			if self.onDenied then
				self:onDenied(result.message)
			end
		end
	else
		-- No provider set, default logic
		if key == "LONDRA" then -- demo key
			self:setState(KeySystem.State.granted)
			self.key = key
			if self.onGranted then
				self:onGranted()
			end
		else
			self:setState(KeySystem.State.denied)
			if self.onDenied then
				self:onDenied("Key not recognized")
			end
		end
	end
end

function KeySystem:getState()
	return {
		state = self.state,
		key = self.key,
		hwid = self.hwid,
		expiresAt = self.expiresAt,
		attempts = self.attempts,
		maxAttempts = self.maxAttempts,
	}
end

function KeySystem:reset()
	self:setState(KeySystem.State.idle)
	self.key = nil
	self.expiresAt = nil
	self.attempts = 0
end

return KeySystem