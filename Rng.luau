--!nonstrict
-- Small seedable PRNG (mulberry32). Deterministic across Lune, Roblox and Jest-Lua,
-- so a seed printed by a failing test replays identically everywhere.

local TWO32 = 4294967296

local function mul32(a, b)
	local lo = b % 65536
	local hi = bit32.rshift(b, 16)
	return (a * lo + ((a * hi) % 65536) * 65536) % TWO32
end

local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
	return setmetatable({ state = math.floor(seed) % TWO32 }, Rng)
end

function Rng.defaultSeed()
	return (os.time() * 1000 + math.floor(os.clock() * 1000)) % TWO32
end

-- Independent stream for the Nth attempt of a run with the given seed.
function Rng.forRun(seed, run)
	return Rng.new(seed + mul32(run, 0x9E3779B1)):split()
end

function Rng:nextUint32()
	self.state = (self.state + 0x6D2B79F5) % TWO32
	local t = self.state
	t = mul32(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, (t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
	return bit32.bxor(t, bit32.rshift(t, 14))
end

-- Float in [0, 1) with 53 bits of randomness.
function Rng:float()
	local a = self:nextUint32()
	local b = bit32.rshift(self:nextUint32(), 11)
	return (a * 2097152 + b) / 9007199254740992
end

-- Integer in [min, max], inclusive.
function Rng:int(min, max)
	assert(min <= max, "Rng:int: min > max")
	local value = min + math.floor(self:float() * (max - min + 1))
	return math.min(value, max)
end

function Rng:split()
	return Rng.new(self:nextUint32())
end

return Rng
