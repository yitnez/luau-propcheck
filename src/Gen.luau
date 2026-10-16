--!nonstrict
-- Generators. A Gen is { sample = (rng, size) -> Tree }. Constructors live on the Gen table
-- and combinators work as methods too:  Gen.integer(0, 9):map(f)  ==  Gen.map(Gen.integer(0, 9), f)

local function req(name)
	if script then
		return require(script.Parent[name]) -- Roblox
	end
	return require("./" .. name) -- Lune
end

local Rng = req("Rng")
local Tree = req("Tree")

local Gen = {}
Gen.__index = Gen

function Gen.new(sampleFn)
	return setmetatable({ sample = sampleFn }, Gen)
end

function Gen.isGen(x)
	return getmetatable(x) == Gen
end

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

---------------------------------------------------------------- primitives

function Gen.constant(value)
	return Gen.new(function()
		return Tree.singleton(value)
	end)
end

-- Build a generator from the current size (0..maxSize, grows over the run).
function Gen.sized(fn)
	return Gen.new(function(rng, size)
		return fn(size).sample(rng, size)
	end)
end

-- Uniform integer in [min, max]; shrinks toward 0 (or the nearest bound).
function Gen.integer(min, max)
	assert(min <= max, "Gen.integer: min > max")
	local origin = clamp(0, min, max)
	return Gen.new(function(rng)
		return Tree.integral(rng:int(min, max), origin)
	end)
end

-- Integers whose magnitude grows with size.
function Gen.int()
	return Gen.sized(function(size)
		return Gen.integer(-size, size)
	end)
end

function Gen.natural()
	return Gen.sized(function(size)
		return Gen.integer(0, size)
	end)
end

-- Uniform float in [min, max); shrinks toward 0 (or the nearest bound).
function Gen.float(min, max)
	assert(min <= max, "Gen.float: min > max")
	local origin = clamp(0, min, max)
	return Gen.new(function(rng)
		return Tree.fractional(min + rng:float() * (max - min), origin)
	end)
end

function Gen.number()
	return Gen.sized(function(size)
		return Gen.float(-size, size)
	end)
end

-- Picks from a list; shrinks toward the first element.
function Gen.elements(list)
	assert(#list > 0, "Gen.elements: empty list")
	return Gen.integer(1, #list):map(function(i)
		return list[i]
	end)
end

function Gen.boolean()
	return Gen.elements({ false, true })
end

---------------------------------------------------------------- combinators

function Gen.map(g, f)
	return Gen.new(function(rng, size)
		return Tree.map(g.sample(rng, size), f)
	end)
end

function Gen.filter(g, pred, maxTries)
	maxTries = maxTries or 100
	return Gen.new(function(rng, size)
		for _ = 1, maxTries do
			local tree = g.sample(rng, size)
			if pred(tree.value) then
				return Tree.filter(tree, pred)
			end
		end
		error(
			("Gen.filter: predicate rejected %d candidates in a row; loosen it or generate valid values directly"):format(
				maxTries
			),
			0
		)
	end)
end

-- Monadic bind: f(value) returns a generator. Shrinks the outer value first, then the inner.
function Gen.bind(g, f)
	return Gen.new(function(rng, size)
		local outer = g.sample(rng, size)
		local innerSeed = rng:nextUint32()
		local function build(tree)
			local inner = f(tree.value).sample(Rng.new(innerSeed), size)
			return {
				value = inner.value,
				children = function()
					local out = {}
					for _, child in ipairs(tree.children()) do
						out[#out + 1] = build(child)
					end
					for _, child in ipairs(inner.children()) do
						out[#out + 1] = child
					end
					return out
				end,
			}
		end
		return build(outer)
	end)
end
Gen.flatMap = Gen.bind

-- Picks one of several generators; shrinks toward the first.
function Gen.oneOf(gens)
	assert(#gens > 0, "Gen.oneOf: empty list")
	return Gen.integer(1, #gens):bind(function(i)
		return gens[i]
	end)
end

-- frequency({ {3, genA}, {1, genB} })
function Gen.frequency(weighted)
	local total = 0
	for _, pair in ipairs(weighted) do
		total += pair[1]
	end
	return Gen.integer(1, total):bind(function(roll)
		local acc = 0
		for _, pair in ipairs(weighted) do
			acc += pair[1]
			if roll <= acc then
				return pair[2]
			end
		end
		return weighted[#weighted][2]
	end)
end

---------------------------------------------------------------- collections

-- Array of elem. Length is in [minLen, maxLen] and grows with size. Shrinks by dropping
-- chunks of elements, then shrinking the elements themselves.
function Gen.array(elem, minLen, maxLen)
	minLen = minLen or 0
	assert(not maxLen or maxLen >= minLen, "Gen.array: maxLen < minLen")
	return Gen.new(function(rng, size)
		local hi = math.max(minLen, math.min(maxLen or math.huge, size))
		local n = rng:int(minLen, hi)
		local trees = {}
		for i = 1, n do
			trees[i] = elem.sample(rng, size)
		end
		return Tree.sequence(trees, minLen)
	end)
end

-- Fixed-length array with one generator per slot: Gen.tuple({ Gen.int(), Gen.boolean() })
function Gen.tuple(gens)
	return Gen.new(function(rng, size)
		local trees = {}
		for i, g in ipairs(gens) do
			trees[i] = g.sample(rng, size)
		end
		return Tree.sequence(trees, #gens, true)
	end)
end

-- Table with fixed keys: Gen.record({ name = Gen.string(1, 8), age = Gen.integer(0, 99) })
function Gen.record(spec)
	local keys = {}
	for k in pairs(spec) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return Gen.new(function(rng, size)
		local trees = {}
		for i, k in ipairs(keys) do
			trees[i] = spec[k].sample(rng, size)
		end
		return Tree.map(Tree.sequence(trees, #keys, true), function(values)
			local out = {}
			for i, k in ipairs(keys) do
				out[k] = values[i]
			end
			return out
		end)
	end)
end

local DEFAULT_CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

-- String of single-byte characters drawn from `charset` (default: alphanumerics + space).
function Gen.string(minLen, maxLen, charset)
	charset = charset or DEFAULT_CHARSET
	local chars = {}
	for i = 1, #charset do
		chars[i] = charset:sub(i, i)
	end
	return Gen.array(Gen.elements(chars), minLen, maxLen):map(function(parts)
		return table.concat(parts)
	end)
end

return Gen
