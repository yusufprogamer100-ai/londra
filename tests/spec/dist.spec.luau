--!nocheck
local Harness = require("../mock/Harness")
local describe, it, expect = Harness.describe, Harness.it, Harness.expect
local Mock = require("../mock/Roblox")
local Londra = require("../../dist/londra")

describe("dist bundle", function()
	it("loads, injects and builds a window", function()
		Mock.reset()
		Londra.__inject(Mock.runtime)
		Londra.__reset()

		local root = Londra.__root()
		expect(root.source):toBe("gethui")

		local win = Londra:Window({ Title = "Bundle", ToggleKey = nil })
		local tab = win:Tab({ Title = "Main" })
		local section = tab:Section({ Title = "Core" })
		local toggle = section:Toggle({ Key = "bundle.enabled", Title = "Enabled", Default = true })

		expect(Londra.Flags:Get("bundle.enabled")):toBe(true)
		expect(toggle.knob.Position.X.Offset):toBe(18)

		local before = #root.gui:GetDescendants()
		expect(before):toBeGreaterThan(10)

		win:close()
		Mock.step(0.2)
		expect(win:isDestroyed()):toBe(true)
		expect(Londra.Info().root):toBe("none")
	end)
end)

return true
