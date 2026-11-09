--!strict
-- Minimal object model. Two levels of inheritance cover the whole library:
--   Class -> (Window, Tab, Section, Component) -> concrete component

local Janitor = require("./Janitor")

local Class = {}
Class.__index = Class

function Class.new(ctor: any, ...): any
	local self = setmetatable({}, ctor)
	self._janitor = Janitor.new()
	self._destroyed = false
	if self.init ~= nil then
		self:init(...)
	end
	return self
end

function Class:extends(name: string): any
	local subclass = setmetatable({}, { __index = self })
	subclass.__index = subclass
	subclass.super = self
	subclass.__name = name
	subclass.new = function(...)
		return Class.new(subclass, ...)
	end
	return subclass
end

function Class:isDestroyed(): boolean
	return self._destroyed == true
end

function Class:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self.beforeDestroy ~= nil then
		local ok = pcall(self.beforeDestroy, self)
		if not ok then
			-- teardown must continue even when a hook fails
		end
	end
	self._janitor:Clean()
	if self.afterDestroy ~= nil then
		pcall(self.afterDestroy, self)
	end
end

return Class
