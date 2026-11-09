--!nocheck
local Harness = require("../mock/Harness")
local describe, it, expect = Harness.describe, Harness.it, Harness.expect
local Mock = require("../mock/Roblox")
local Flags = require("../../src/state/Flags")
local Color = require("../../src/design/Color")

describe("Flags", function()
	it("stores and reads a value", function()
		local flags = Flags.new()
		expect(flags:Set("aim.enabled", true)):toBe(true)
		expect(flags:Get("aim.enabled")):toBe(true)
		expect(flags:Has("aim.enabled")):toBe(true)
		flags:Destroy()
	end)

	it("does not fire on an equal value", function()
		local flags = Flags.new()
		flags:Set("aim.fov", 90)
		local calls = 0
		flags:OnChanged("aim.fov", function()
			calls += 1
		end)
		flags:Set("aim.fov", 90)
		expect(calls):toBe(0)
		flags:Set("aim.fov", 91)
		expect(calls):toBe(1)
		flags:Destroy()
	end)

	it("compares tables and Color3 deeply", function()
		local flags = Flags.new()
		flags:Set("aim.range", { 40, 120 })
		local calls = 0
		flags:OnChanged("aim.range", function()
			calls += 1
		end)
		flags:Set("aim.range", { 40, 120 })
		expect(calls):toBe(0)

		flags:Set("ui.accent", Color.fromHex("#D4AF37"))
		local colorCalls = 0
		flags:OnChanged("ui.accent", function()
			colorCalls += 1
		end)
		flags:Set("ui.accent", Color.fromHex("#D4AF37"))
		expect(colorCalls):toBe(0)
		flags:Destroy()
	end)

	it("rejects a type change", function()
		local flags = Flags.new()
		flags:Set("aim.fov", 90)
		expect(flags:Set("aim.fov", "ninety")):toBe(false)
		expect(flags:Get("aim.fov")):toBe(90)
		flags:Destroy()
	end)

	it("rejects malformed keys", function()
		local flags = Flags.new()
		expect(flags:Set("Aim Fov", 1)):toBe(false)
		expect(flags:Set("aim", 1)):toBe(false)
		expect(flags:Set("aim.fov", 1)):toBe(true)
		flags:Destroy()
	end)

	it("snapshots and loads", function()
		local flags = Flags.new()
		flags:Set("aim.fov", 120)
		flags:Set("aim.enabled", true)
		local snapshot = flags:Snapshot()
		local other = Flags.new()
		expect(other:Load(snapshot)):toBe(2)
		expect(other:Get("aim.fov")):toBe(120)
		flags:Destroy()
		other:Destroy()
	end)
end)

return true
