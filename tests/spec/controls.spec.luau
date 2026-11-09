--!nocheck
local Harness = require("../mock/Harness")
local describe, it, expect = Harness.describe, Harness.it, Harness.expect
local Mock = require("../mock/Roblox")
local Londra = require("../../src/Londra")

local function fresh()
	Londra.__reset()
	Mock.reset()
	Londra.__inject(Mock.runtime)
	local win = Londra:Window({ Title = "Controls", Size = Mock.UDim2.fromOffset(760, 500), ToggleKey = nil, Resizable = false })
	local tab = win:Tab({ Title = "Main" })
	local section = tab:Section({ Title = "Inputs" })
	return win, section
end

describe("Controls", function()
	it("slider writes a rounded value and renders it", function()
		local win, section = fresh()
		local slider = section:Slider({ Key = "test.fov", Title = "FOV", Min = 0, Max = 360, Step = 5, Default = 90 })
		expect(Londra.Flags:Get("test.fov")):toBe(90)
		slider:setValue(123)
		expect(Londra.Flags:Get("test.fov")):toBe(125)
		expect(slider.box.Text):toBe("125")
		expect(slider.fill.Size.X.Scale):toBeCloseTo(125 / 360, 0.001)
		slider:setValue(999)
		expect(Londra.Flags:Get("test.fov")):toBe(360)
		win:Destroy()
	end)

	it("textbox rejects invalid input and keeps the last valid value", function()
		local win, section = fresh()
		local field = section:Textbox({
			Key = "test.name",
			Title = "Name",
			Default = "main",
			Validate = function(text)
				return #text > 0, "Cannot be empty"
			end,
		})
		expect(Londra.Flags:Get("test.name")):toBe("main")

		field.box.Text = ""
		field.box:ReleaseFocus()
		expect(field.errorLabel.Visible):toBe(true)
		expect(Londra.Flags:Get("test.name")):toBe("main")

		field.box.Text = "alt"
		field.box:ReleaseFocus()
		expect(field.errorLabel.Visible):toBe(false)
		expect(Londra.Flags:Get("test.name")):toBe("alt")
		win:Destroy()
	end)

	it("dropdown opens, selects and closes", function()
		local win, section = fresh()
		local dropdown = section:Dropdown({
			Key = "test.part",
			Title = "Part",
			Values = { "Head", "Torso", "HumanoidRootPart" },
			Default = "Head",
		})
		expect(dropdown.valueLabel.Text):toBe("Head")
		dropdown:openPanel()
		expect(dropdown.open):toBe(true)
		expect(dropdown.panel):toBeTruthy()
		dropdown:choose("Torso")
		expect(Londra.Flags:Get("test.part")):toBe("Torso")
		expect(dropdown.open):toBe(false)
		expect(dropdown.valueLabel.Text):toBe("Torso")
		win:Destroy()
	end)

	it("keybind captures a key and changes mode", function()
		local win, section = fresh()
		local bind = section:Keybind({
			Key = "test.key",
			Title = "Key",
			Default = Mock.Enum.KeyCode.E,
			Mode = "hold",
		})
		expect(bind.keyButton.Text):toBe("E")
		bind:setKey(Mock.Enum.KeyCode.Q)
		expect(bind.keyButton.Text):toBe("Q")
		expect(Londra.Flags:Get("test.key").key):toBe(Mock.Enum.KeyCode.Q)
		bind:setMode("always")
		expect(bind.keyButton.Text):toBe("Always")
		expect(Londra.Flags:Get("test.key").mode):toBe("always")
		win:Destroy()
	end)
end)

return true
