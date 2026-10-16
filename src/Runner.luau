--!nonstrict
-- Property runner: generate, test, shrink, report.

local function req(name)
	if script then
		return require(script.Parent[name]) -- Roblox
	end
	return require("./" .. name) -- Lune
end

local Rng = req("Rng")
local Gen = req("Gen")
local Inspect = req("Inspect")

local Runner = {}

local DISCARD = {}

-- Skip inputs that don't meet a precondition without counting them as pass or fail.
function Runner.assume(condition)
	if not condition then
		error(DISCARD, 0)
	end
end

-- Accepts either a Gen (property receives one value) or an array of Gens
-- (property receives one argument per generator).
local function normalize(gens, prop)
	if Gen.isGen(gens) then
		return gens, prop
	end
	assert(type(gens) == "table", "expected a generator or an array of generators")
	local n = #gens
	return Gen.tuple(gens), function(values)
		return prop(table.unpack(values, 1, n))
	end
end

-- A property passes if it returns anything but `false` and doesn't throw.
local function runOnce(prop, value)
	local ok, result = pcall(prop, value)
	if not ok then
		if result == DISCARD then
			return "discard"
		end
		return "fail", tostring(result)
	end
	if result == false then
		return "fail", "property returned false"
	end
	return "pass"
end

local function shrink(tree, prop, maxShrinks, firstMessage)
	local current, message = tree, firstMessage
	local steps, tests = 0, 0
	local progressed = true
	while progressed and tests < maxShrinks do
		progressed = false
		for _, child in ipairs(current.children()) do
			tests += 1
			local status, msg = runOnce(prop, child.value)
			if status == "fail" then
				current, message = child, msg
				steps += 1
				progressed = true
				break
			end
			if tests >= maxShrinks then
				break
			end
		end
	end
	return current, steps, message
end

--[[
	opts: numRuns (100), seed (random), maxSize (100), maxShrinks (500), maxDiscards (numRuns*10),
	      show (value -> string, for custom counterexample printing)
	Returns { ok, seed, numRuns, discarded } on success, or additionally
	{ counterexample, original, shrinks, error, run } on failure.
]]
function Runner.check(gens, prop, opts)
	opts = opts or {}
	local gen, p = normalize(gens, prop)
	local numRuns = opts.numRuns or 100
	local seed = math.floor(opts.seed or Rng.defaultSeed())
	local maxSize = opts.maxSize or 100
	local maxShrinks = opts.maxShrinks or 500
	local maxDiscards = opts.maxDiscards or numRuns * 10

	local passed, attempts, discarded = 0, 0, 0
	while passed < numRuns do
		attempts += 1
		local rng = Rng.forRun(seed, attempts)
		local size = math.min(maxSize, math.floor(passed * maxSize / math.max(numRuns, 1)))
		local tree = gen.sample(rng, size)
		local status, message = runOnce(p, tree.value)
		if status == "pass" then
			passed += 1
		elseif status == "discard" then
			discarded += 1
			if discarded > maxDiscards then
				return { ok = false, gaveUp = true, seed = seed, numRuns = passed, discarded = discarded }
			end
		else
			local smallest, steps, finalMessage = shrink(tree, p, maxShrinks, message)
			return {
				ok = false,
				seed = seed,
				run = attempts,
				numRuns = passed + 1,
				discarded = discarded,
				original = tree.value,
				counterexample = smallest.value,
				shrinks = steps,
				error = finalMessage,
				show = opts.show,
			}
		end
	end
	return { ok = true, seed = seed, numRuns = passed, discarded = discarded }
end

function Runner.format(result)
	if result.ok then
		return ("OK: passed %d tests (seed = %d)"):format(result.numRuns, result.seed)
	end
	if result.gaveUp then
		return ("Gave up: too many discarded inputs (%d passed, %d discarded, seed = %d). Loosen assume() or generate valid values directly."):format(
			result.numRuns,
			result.discarded,
			result.seed
		)
	end
	local show = result.show or Inspect
	local lines = {
		("Property failed after %d test(s) (seed = %d)"):format(result.numRuns, result.seed),
		("  Counterexample (after %d shrinks): %s"):format(result.shrinks, show(result.counterexample)),
	}
	if result.shrinks > 0 then
		lines[#lines + 1] = "  Original: " .. show(result.original)
	end
	lines[#lines + 1] = "  Error: " .. tostring(result.error)
	lines[#lines + 1] = ("  Replay: pass { seed = %d } in the options"):format(result.seed)
	return table.concat(lines, "\n")
end

-- Throws a formatted error if the property fails. Use inside any test framework.
function Runner.assertProperty(gens, prop, opts)
	local result = Runner.check(gens, prop, opts)
	if not result.ok then
		error(Runner.format(result), 0)
	end
	return result
end

return Runner
