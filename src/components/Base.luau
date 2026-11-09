--!strict
-- Shared component base. Owns the janitor contract and the theme binding sugar
-- so a component never touches a raw colour.

local Class = require("../core/Class")
local Tokens = require("../design/Tokens")
local Motion = require("../core/Motion")

local Base = Class:extends("Component")

function Base:init(context: any, options: any?)
	self.context = context
	self.options = options or {}
	self.binder = context.binder
	self.layers = context.layers
	self.focus = context.focus
	self.tokens = Tokens
	self.element = nil
	self.enabled = true
	self.rowHeight = Tokens.row.height
end

function Base:theme(instance: any, property: string, token: string): any
	return self._janitor:Add(self.binder:bind(instance, property, token))
end

function Base:add(instance: any): any
	return self._janitor:Add(instance)
end

function Base:track(handle: any): any
	return self._janitor:Add(handle)
end

function Base:setEnabled(value: boolean)
	self.enabled = value
	if self.element ~= nil then
		self.element.Active = value
		self.element.Selectable = value
		Motion.tween(self.element, { BackgroundTransparency = value and (self._idleTransparency or 1) or 0.6 })
	end
end

function Base:hoverable(element: any, idleTransparency: number?): any
	local idle = idleTransparency or 1
	self._idleTransparency = idle
	element.BackgroundTransparency = idle
	self:theme(element, "BackgroundColor3", "state.hover")
	self:track(element.MouseEnter:Connect(function()
		if not self.enabled then
			return
		end
		Motion.tween(element, { BackgroundTransparency = 0 }, { duration = Motion.duration("state") })
	end))
	self:track(element.MouseLeave:Connect(function()
		Motion.tween(element, { BackgroundTransparency = idle }, { duration = Motion.duration("state") })
	end))
	return element
end

return Base
