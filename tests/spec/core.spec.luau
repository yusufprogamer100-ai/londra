--!nocheck
local Harness = require("../mock/Harness")
local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local Signal = require("../../src/core/Signal")
local Janitor = require("../../src/core/Janitor")
local Class = require("../../src/core/Class")
local Scheduler = require("../../src/core/Scheduler")
local Runtime = require("../../src/core/Runtime")
local Mock = require("../mock/Roblox")

describe("Signal", function()
	it("delivers arguments to every listener", function()
		local signal = Signal.new("test")
		local received = {}
		signal:Connect(function(a, b)
			table.insert(received, a .. b)
		end)
		signal:Connect(function(a, b)
			table.insert(received, b .. a)
		end)
		signal:Fire("x", "y")
		expect(#received):toBe(2)
		expect(received[1]):toBe("xy")
		expect(received[2]):toBe("yx")
	end)

	it("isolates a throwing listener", function()
		local signal = Signal.new("test")
		local reached = false
		signal:Connect(function()
			error("boom")
		end)
		signal:Connect(function()
			reached = true
		end)
		signal:Fire()
		expect(reached):toBe(true)
	end)

	it("disconnects without disturbing the snapshot", function()
		local signal = Signal.new("test")
		local calls = 0
		local second
		signal:Connect(function()
			calls += 1
			if second then
				second:Disconnect()
			end
		end)
		second = signal:Connect(function()
			calls += 1
		end)
		signal:Fire()
		signal:Fire()
		expect(calls):toBe(2)
		expect(signal:GetCount()):toBe(1)
	end)

	it("stops firing after Destroy", function()
		local signal = Signal.new("test")
		local calls = 0
		signal:Connect(function()
			calls += 1
		end)
		signal:Destroy()
		signal:Fire()
		expect(calls):toBe(0)
		expect(signal:GetCount()):toBe(0)
	end)
end)

describe("Janitor", function()
	it("cleans in LIFO order", function()
		local janitor = Janitor.new()
		local order = {}
		janitor:Add(function()
			table.insert(order, 1)
		end)
		janitor:Add(function()
			table.insert(order, 2)
		end)
		janitor:Add(function()
			table.insert(order, 3)
		end)
		janitor:Clean()
		expect(order[1]):toBe(3)
		expect(order[2]):toBe(2)
		expect(order[3]):toBe(1)
	end)

	it("destroys instances and disconnects connections", function()
		local janitor = Janitor.new()
		local frame = Mock.Instance.new("Frame")
		local fired = 0
		local connection = Mock.signal():Connect(function()
			fired += 1
		end)
		janitor:Add(frame)
		janitor:Add(connection)
		janitor:Clean()
		expect(frame.Parent):toBeNil()
		expect(fired):toBe(0)
	end)

	it("is idempotent", function()
		local janitor = Janitor.new()
		local calls = 0
		janitor:Add(function()
			calls += 1
		end)
		janitor:Clean()
		janitor:Clean()
		expect(calls):toBe(1)
	end)

	it("survives a failing cleanup", function()
		local janitor = Janitor.new()
		local reached = false
		janitor:Add(function()
			error("cleanup failed")
		end)
		janitor:Add(function()
			reached = true
		end)
		janitor:Clean()
		expect(reached):toBe(true)
	end)
end)

describe("Class", function()
	local Animal = Class:extends("Animal")

	function Animal:init(name)
		self.name = name
	end

	function Animal:speak()
		return self.name .. " speaks"
	end

	local Dog = Animal:extends("Dog")

	function Dog:speak()
		return self.name .. " barks"
	end

	it("inherits and overrides", function()
		local dog = Dog.new("Rex")
		expect(dog:speak()):toBe("Rex barks")
		expect(dog.name):toBe("Rex")
	end)

	it("destroys once", function()
		local dog = Dog.new("Rex")
		dog:Destroy()
		dog:Destroy()
		expect(dog:isDestroyed()):toBe(true)
	end)
end)

describe("Scheduler", function()
	it("coalesces queued work by key", function()
		Scheduler:stop()
		local calls = {}
		Scheduler:queue("a", function()
			table.insert(calls, "first")
		end)
		Scheduler:queue("a", function()
			table.insert(calls, "second")
		end)
		Mock.step()
		expect(#calls):toBe(1)
		expect(calls[1]):toBe("second")
	end)

	it("runs timers once their time has passed", function()
		Scheduler:stop()
		local fired = false
		Scheduler:after(0.5, function()
			fired = true
		end)
		Mock.step(0.25)
		expect(fired):toBe(false)
		Mock.step(0.3)
		expect(fired):toBe(true)
	end)

	it("disconnects the heartbeat when idle", function()
		Scheduler:stop()
		Scheduler:queue("x", function() end)
		expect(Scheduler:stats().connected):toBe(true)
		Mock.step()
		expect(Scheduler:stats().connected):toBe(false)
	end)

	it("resolves services through the injected runtime", function()
		expect(Runtime.service("RunService")):toBe(Mock.services.RunService)
	end)
end)

return true
