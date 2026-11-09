--!nocheck
local Harness = require("../mock/Harness")
local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local Mock = require("../mock/Roblox")
local Color = require("../../src/design/Color")
local Theme = require("../../src/design/Theme")
local Root = require("../../src/ui/Root")

describe("Color", function()
	it("round trips hex", function()
		local color = Color.fromHex("#D4AF37")
		expect(color):toBeTruthy()
		expect(Color.toHex(color)):toBe("#D4AF37")
	end)

	it("expands short hex", function()
		local color = Color.fromHex("#fa0")
		expect(Color.toHex(color)):toBe("#FFAA00")
	end)

	it("rejects invalid hex", function()
		expect(Color.fromHex("#12")):toBeNil()
		expect(Color.fromHex("zzzzzz")):toBeNil()
	end)

	it("matches the WCAG contrast formula", function()
		local foreground = Color.fromHex("#E7E9EC")
		local background = Color.fromHex("#0F1114")
		expect(Color.contrast(foreground, background)):toBeCloseTo(15.55, 0.05)
	end)

	it("converts HSV both ways", function()
		local color = Color.fromHSV(0.5, 1, 1)
		expect(Color.toHex(color)):toBe("#00FFFF")
		local h, s, v = Color.toHSV(color)
		expect(h):toBeCloseTo(0.5, 0.001)
		expect(s):toBeCloseTo(1, 0.001)
		expect(v):toBeCloseTo(1, 0.001)
	end)

	it("picks a readable foreground", function()
		expect(Color.toHex(Color.bestOn(Color.fromHex("#D4AF37")))):toBe("#000000")
		expect(Color.toHex(Color.bestOn(Color.fromHex("#101010")))):toBe("#FFFFFF")
	end)
end)

describe("Theme", function()
	it("ships three themes that pass AA", function()
		for _, name in ipairs({ "night", "day", "contrast" }) do
			local report = Theme.validateTheme(name)
			for _, entry in ipairs(report) do
				if not entry.pass then
					error(string.format("%s fails %s at %.2f", name, entry.pair, entry.ratio))
				end
			end
		end
	end)

	it("binds a property and follows a theme switch", function()
		local frame = Mock.Instance.new("Frame")
		local binder = Theme.binder("night")
		local handle = binder:bind(frame, "BackgroundColor3", "surface.base")
		expect(Color.toHex(frame.BackgroundColor3)):toBe("#0F1114")

		binder:setTheme("day")
		expect(Color.toHex(frame.BackgroundColor3)):toBe("#F4F4F2")

		handle:Disconnect()
		expect(binder:count()):toBe(0)
	end)

	it("never walks the instance tree on switch", function()
		local frame = Mock.Instance.new("Frame")
		local child = Mock.Instance.new("Frame")
		child.Parent = frame
		local binder = Theme.binder("night")
		binder:bind(frame, "BackgroundColor3", "surface.base")
		binder:bind(child, "BackgroundColor3", "surface.raised")

		Mock.descendantCalls = 0
		binder:setTheme("contrast")
		expect(Mock.descendantCalls):toBe(0)
	end)

	it("derives accent tokens with readable foreground", function()
		Theme.derive("custom-probe", { from = "night", accent = "#2F6F5E" })
		local tokens = Theme.get("custom-probe")
		expect(tokens["accent.base"]):toBe("#2F6F5E")
		expect(tokens["accent.hover"]):toBeTruthy()
		expect(tokens["accent.on"]):toBeTruthy()
		local report = Theme.validate(tokens)
		expect(#report):toBeGreaterThan(0)
	end)

	it("warns and falls back on an unknown token", function()
		local frame = Mock.Instance.new("Frame")
		local binder = Theme.binder("night")
		binder:bind(frame, "BackgroundColor3", "does.not.exist")
		expect(Color.toHex(frame.BackgroundColor3)):toBe("#0F1114")
	end)
end)

describe("Root", function()
	it("resolves gethui and builds four layers", function()
		Mock.reset()
		local root = Root.create({ Scale = 1 })
		expect(root.source):toBe("gethui")
		expect(root.gui.Parent):toBe(Mock.services.CoreGui)
		expect(root.gui.DisplayOrder):toBe(999999)
		for _, layer in ipairs({ "base", "popup", "overlay", "toast" }) do
			expect(root.layers:frame(layer)):toBeTruthy()
		end
		root.destroy()
		expect(root.gui.Parent):toBeNil()
	end)

	it("falls back to CoreGui without gethui", function()
		Mock.reset()
		Mock.disable("gethui")
		local root = Root.create({ Scale = 1 })
		expect(root.source):toBe("coregui")
		root.destroy()
		Mock.enable("gethui", function()
			return Mock.services.CoreGui
		end)
	end)
end)

return true
