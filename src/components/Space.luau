--!strict
-- Layout breathing room. A component, not a magic padding number scattered
-- through every section.

local Base = require("./Base")
local Builder = require("../ui/Builder")
local Runtime = require("../core/Runtime")

local Space = Base:extends("Space")

function Space:init(context: any, options: any)
	Base.init(self, context, options)

	local config = self.options
	local frame = Builder.frame({
		Name = "space",
		Size = Runtime.UDim2.new(1, 0, 0, config.Size or 8),
		ZIndex = 1,
	})
	frame.Parent = config.Parent
	self.element = frame
end

return Space
