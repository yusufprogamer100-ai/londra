--!nocheck
local Mock = require("./mock/Roblox")
local Runtime = require("../src/core/Runtime")

Runtime.inject(Mock.runtime)

local Harness = require("./mock/Harness")

require("./spec/core.spec")
require("./spec/theme.spec")
require("./spec/flags.spec")
require("./spec/window.spec")
require("./spec/controls.spec")
require("./spec/dist.spec")

local failed = Harness.run()
if failed > 0 then
	error(string.format("%d test(s) failed", failed), 0)
end
