--!nocheck
local Harness = require("../mock/Harness")
local describe, it, expect = Harness.describe, Harness.it, Harness.expect
local Mock = require("../mock/Roblox")
local Londra = require("../../src/Londra")
local Color = require("../../src/design/Color")

local function fresh()
	Londra.__reset()
	Mock.reset()
	Londra.__inject(Mock.runtime)
end

describe("Window", function()
	it("builds a shell in the base layer", function()
		fresh()
		local win = Londra:Window({
			Title = "Probe",
			Size = Mock.UDim2.fromOffset(760, 500),
			ToggleKey = nil,
		})
		expect(Londra.Info().root):toBe("gethui")
		expect(win.frame.Parent):toBeTruthy()
		expect(win.titleBar.title.Text):toBe("Probe")
		expect(win.body.Visible):toBe(true)
		expect(#win.tabs):toBe(0)
		win:Destroy()
	end)

	it("creates tabs, sections and a working toggle", function()
		fresh()
		local win = Londra:Window({ Title = "Probe", Size = Mock.UDim2.fromOffset(760, 500), ToggleKey = nil })
		local tab = win:Tab({ Title = "Combat" })
		local section = tab:Section({ Title = "Aim", Description = "Targeting" })
		local toggle = section:Toggle({ Key = "aim.enabled", Title = "Enabled", Default = false })

		expect(win.rail.active):toBe(1)
		expect(tab:isVisible()):toBe(true)
		expect(Londra.Flags:Get("aim.enabled")):toBe(false)
		expect(toggle.knob.Position.X.Offset):toBe(2)

		toggle.element.MouseButton1Click:Fire()
		expect(Londra.Flags:Get("aim.enabled")):toBe(true)
		expect(toggle.knob.Position.X.Offset):toBe(18)

		toggle.element.MouseButton1Click:Fire()
		expect(Londra.Flags:Get("aim.enabled")):toBe(false)
		win:Destroy()
	end)

	it("follows a theme switch", function()
		fresh()
		local win = Londra:Window({ Title = "Probe", Size = Mock.UDim2.fromOffset(760, 500), ToggleKey = nil })
		expect(Color.toHex(win.frame.BackgroundColor3)):toBe("#0F1114")
		win.binder:setTheme("day")
		expect(Color.toHex(win.frame.BackgroundColor3)):toBe("#F4F4F2")
		win:Destroy()
	end)

	it("drags by the title bar", function()
		fresh()
		local win = Londra:Window({ Title = "Probe", Size = Mock.UDim2.fromOffset(760, 500), ToggleKey = nil, Resizable = false })
		local startX = win:getPosition().X
		local startY = win:getPosition().Y
		Mock.press(10, 10)
		Mock.move(60, 40)
		Mock.release(60, 40)
		expect(win:getPosition().X):toBe(startX + 50)
		expect(win:getPosition().Y):toBe(startY + 30)
		win:Destroy()
	end)

	it("minimizes and restores its height", function()
		fresh()
		local win = Londra:Window({ Title = "Probe", Size = Mock.UDim2.fromOffset(760, 500), ToggleKey = nil })
		win:minimize()
		Mock.step(0.2)
		expect(win.body.Visible):toBe(false)
		win:minimize()
		Mock.step(0.2)
		expect(win.body.Visible):toBe(true)
		expect(win:getSize().Y):toBe(500)
		win:Destroy()
	end)

	it("closes, cleans up and tears down the root", function()
		fresh()
		local win = Londra:Window({ Title = "Probe", Size = Mock.UDim2.fromOffset(760, 500), ToggleKey = nil })
		win:close()
		Mock.step(0.2)
		expect(win:isDestroyed()):toBe(true)
		expect(Londra.Info().root):toBe("none")
	end)
end)

return true
