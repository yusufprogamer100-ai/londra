--!nocheck
-- Tiny test harness. Deliberately small: no matcher zoo, no async, no magic.

local Harness = {}

local tests = {}
local currentSuite = "root"

function Harness.describe(name, fn)
	local previous = currentSuite
	currentSuite = name
	local ok, err = pcall(fn)
	currentSuite = previous
	if not ok then
		table.insert(tests, {
			suite = name,
			name = "<describe body>",
			fn = function()
				error(err, 0)
			end,
		})
	end
end

function Harness.it(name, fn)
	table.insert(tests, { suite = currentSuite, name = name, fn = fn })
end

local function fail(message)
	error(message, 3)
end

local Expectation = {}
Expectation.__index = Expectation

local function expect(value)
	return setmetatable({ value = value }, Expectation)
end

function Expectation:toBe(expected)
	if self.value ~= expected then
		fail(string.format("expected %s, got %s", tostring(expected), tostring(self.value)))
	end
end

function Expectation:toBeNil()
	if self.value ~= nil then
		fail(string.format("expected nil, got %s", tostring(self.value)))
	end
end

function Expectation:toBeTruthy()
	if not self.value then
		fail(string.format("expected truthy, got %s", tostring(self.value)))
	end
end

function Expectation:toBeFalsy()
	if self.value then
		fail(string.format("expected falsy, got %s", tostring(self.value)))
	end
end

function Expectation:toBeCloseTo(expected, epsilon)
	local delta = math.abs(self.value - expected)
	if delta > (epsilon or 1e-6) then
		fail(string.format("expected %s +/- %s, got %s", tostring(expected), tostring(epsilon), tostring(self.value)))
	end
end

function Expectation:toBeGreaterThan(expected)
	if not (self.value > expected) then
		fail(string.format("expected > %s, got %s", tostring(expected), tostring(self.value)))
	end
end

function Expectation:toBeGreaterThanOrEqual(expected)
	if not (self.value >= expected) then
		fail(string.format("expected >= %s, got %s", tostring(expected), tostring(self.value)))
	end
end

function Expectation:toBeLessThan(expected)
	if not (self.value < expected) then
		fail(string.format("expected < %s, got %s", tostring(expected), tostring(self.value)))
	end
end

function Expectation:toDeepEqual(expected)
	local function same(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for key, value in pairs(a) do
			if not same(value, b[key]) then
				return false
			end
		end
		for key in pairs(b) do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	if not same(self.value, expected) then
		fail("deep equality failed")
	end
end

function Expectation:toThrow()
	local ok = pcall(self.value)
	if ok then
		fail("expected function to throw")
	end
end

function Expectation:notToThrow()
	local ok, err = pcall(self.value)
	if not ok then
		fail("expected no throw, got: " .. tostring(err))
	end
end

Harness.expect = expect

function Harness.run()
	local passed = 0
	local failed = 0
	local failures = {}

	for _, test in ipairs(tests) do
		local ok, err = pcall(test.fn)
		if ok then
			passed += 1
			print(string.format("  pass  %s > %s", test.suite, test.name))
		else
			failed += 1
			table.insert(failures, string.format("%s > %s\n        %s", test.suite, test.name, tostring(err)))
			print(string.format("  FAIL  %s > %s", test.suite, test.name))
		end
	end

	print("")
	if failed > 0 then
		for _, failure in ipairs(failures) do
			print("  " .. failure)
		end
		print("")
	end
	print(string.format("%d passed, %d failed, %d total", passed, failed, #tests))
	return failed
end

function Harness.count()
	return #tests
end

return Harness
