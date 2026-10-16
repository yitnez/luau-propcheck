--!nonstrict
-- Run with:  lune run tests/selftest
local PropCheck = require("../src/PropCheck")
local Gen = PropCheck.Gen

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("PASS " .. name)
	else
		failures += 1
		print("FAIL " .. name .. "\n  " .. tostring(err))
	end
end

test("passing property passes", function()
	local r = PropCheck.check(Gen.array(Gen.int()), function(xs)
		local copy = table.clone(xs)
		table.sort(copy)
		for i = 2, #copy do
			if copy[i - 1] > copy[i] then
				return false
			end
		end
		return true
	end, { seed = 1 })
	assert(r.ok, PropCheck.format(r))
end)

test("integers shrink to the boundary", function()
	local r = PropCheck.check(Gen.integer(0, 1000), function(n)
		return n < 10
	end, { seed = 42 })
	assert(not r.ok, "expected failure")
	assert(r.counterexample == 10, "expected 10, got " .. tostring(r.counterexample))
end)

test("arrays shrink to a minimal list", function()
	local r = PropCheck.check(Gen.array(Gen.integer(0, 100)), function(xs)
		return #xs < 3
	end, { seed = 7 })
	assert(not r.ok, "expected failure")
	assert(#r.counterexample == 3, "expected length 3, got " .. #r.counterexample)
	for _, v in ipairs(r.counterexample) do
		assert(v == 0, "elements should shrink to 0")
	end
end)

test("same seed reproduces the same failure", function()
	local prop = function(n)
		return n < 500
	end
	local a = PropCheck.check(Gen.integer(0, 1000), prop, { seed = 99 })
	local b = PropCheck.check(Gen.integer(0, 1000), prop, { seed = 99 })
	assert(not a.ok and not b.ok)
	assert(a.original == b.original and a.run == b.run)
end)

test("array of generators spreads arguments", function()
	local r = PropCheck.check({ Gen.integer(0, 100), Gen.integer(0, 100) }, function(a, b)
		return a + b == b + a
	end, { seed = 3 })
	assert(r.ok, PropCheck.format(r))
end)

test("assume discards inputs", function()
	local r = PropCheck.check(Gen.integer(0, 100), function(n)
		PropCheck.assume(n % 2 == 0)
		return n % 2 == 0
	end, { seed = 5 })
	assert(r.ok, PropCheck.format(r))
end)

test("bind shrinks both sides", function()
	local g = Gen.integer(1, 20):bind(function(n)
		return Gen.array(Gen.integer(0, 9), n, n)
	end)
	local r = PropCheck.check(g, function(xs)
		return #xs < 5
	end, { seed = 11 })
	assert(not r.ok)
	assert(#r.counterexample == 5, "expected length 5, got " .. #r.counterexample)
end)

test("stateful: finds and shrinks a buggy counter", function()
	local spec = {
		initialState = function()
			return 0
		end,
		setup = function()
			return { n = 0 }
		end,
		commands = {
			{
				name = "inc",
				run = function(sut)
					if sut.n < 3 then -- bug: silently caps at 3
						sut.n += 1
					end
					return sut.n
				end,
				post = function(state, _, result)
					return result == state + 1
				end,
				next = function(state)
					return state + 1
				end,
			},
			{
				name = "dec",
				run = function(sut)
					sut.n -= 1
					return sut.n
				end,
				post = function(state, _, result)
					return result == state - 1
				end,
				next = function(state)
					return state - 1
				end,
			},
		},
	}
	local r = PropCheck.stateful.check(spec, { seed = 2, numRuns = 200 })
	assert(not r.ok, "expected the bug to be found")
	assert(#r.counterexample == 4, "expected 4 steps, got " .. #r.counterexample)
	print(PropCheck.format(r))
end)

if failures > 0 then
	error(failures .. " test(s) failed")
end
print("all good")
