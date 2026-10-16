--!nonstrict
-- luau-propcheck: property-based testing for Luau & Roblox.

local function req(name)
	if script then
		return require(script.Parent[name]) -- Roblox
	end
	return require("./" .. name) -- Lune
end

local Rng = req("Rng")
local Tree = req("Tree")
local Gen = req("Gen")
local Inspect = req("Inspect")
local Runner = req("Runner")
local Stateful = req("Stateful")
req("Roblox").install(Gen)

local PropCheck = {
	Gen = Gen,
	Rng = Rng,
	Tree = Tree,
	inspect = Inspect,
	check = Runner.check,
	assertProperty = Runner.assertProperty,
	assume = Runner.assume,
	format = Runner.format,
	stateful = Stateful,
}

-- Lune-friendly: runs a property, prints PASS/FAIL, returns a boolean.
function PropCheck.run(name, gens, prop, opts)
	local result = Runner.check(gens, prop, opts)
	if result.ok then
		print(("PASS %s (%d tests, seed %d)"):format(name, result.numRuns, result.seed))
	else
		print(("FAIL %s\n%s"):format(name, Runner.format(result)))
	end
	return result.ok
end

-- Bind to a test framework's `it`/`test` (Jest-Lua, TestEZ):
--   local property = PropCheck.property(it)
--   property("reverse twice is identity", Gen.array(Gen.int()), function(xs) ... end)
function PropCheck.property(testFn)
	return function(name, gens, prop, opts)
		testFn(name, function()
			Runner.assertProperty(gens, prop, opts)
		end)
	end
end

-- Draw example values, handy for eyeballing a generator.
function PropCheck.sample(gen, count, seed)
	count = count or 10
	seed = seed or Rng.defaultSeed()
	local out = {}
	for i = 1, count do
		out[i] = gen.sample(Rng.forRun(seed, i), math.floor((i - 1) * 100 / count)).value
	end
	return out
end

return PropCheck
