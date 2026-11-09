--!strict
-- Numeric constants. No colours here: colour lives in themes as hex strings so
-- the contrast checker and the runtime resolve the exact same values.

local Tokens = {}

Tokens.space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 16,
	xl = 24,
	xxl = 32,
}

Tokens.radius = {
	window = 10,
	section = 8,
	control = 6,
	chip = 4,
}

Tokens.row = {
	height = 34,
	touchHeight = 44,
	titlebar = 40,
	tab = 36,
	status = 22,
	sectionHeader = 30,
}

Tokens.size = {
	tabRail = 132,
	notification = 320,
	icon = 14,
	iconLarge = 16,
	swatch = 24,
	sliderKnob = 12,
	sliderHit = 20,
	toggleWidth = 36,
	toggleHeight = 20,
}

Tokens.motion = {
	state = 0.12,
	open = 0.18,
	close = 0.14,
	press = 0.08,
	toast = 0.22,
}

Tokens.font = {
	title = "GothamBold",
	tab = "GothamMedium",
	section = "GothamBold",
	label = "Gotham",
	body = "Gotham",
	value = "GothamMedium",
	code = "Code",
}

Tokens.z = {
	baseMin = 1,
	baseMax = 99,
	popupMin = 100,
	popupMax = 199,
	overlayMin = 200,
	overlayMax = 299,
	toastMin = 300,
	toastMax = 399,
}

Tokens.strokeBudget = 300

function Tokens.scaledRow(touch: boolean?): number
	if touch then
		return Tokens.row.touchHeight
	end
	return Tokens.row.height
end

return Tokens
