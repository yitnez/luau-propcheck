--!nonstrict
-- Rose trees of shrinks. Every generated value carries its own (lazy) shrink candidates,
-- which is what makes shrinking "integrated": any generator, however composed, shrinks.
--
-- Tree = { value = T, children = () -> { Tree } }   (children ordered most-aggressive first)

local Tree = {}

local function noChildren()
	return {}
end

function Tree.new(value, children)
	return { value = value, children = children or noChildren }
end

function Tree.singleton(value)
	return { value = value, children = noChildren }
end

function Tree.map(tree, f)
	return {
		value = f(tree.value),
		children = function()
			local out = {}
			for i, child in ipairs(tree.children()) do
				out[i] = Tree.map(child, f)
			end
			return out
		end,
	}
end

function Tree.filter(tree, pred)
	return {
		value = tree.value,
		children = function()
			local out = {}
			for _, child in ipairs(tree.children()) do
				if pred(child.value) then
					out[#out + 1] = Tree.filter(child, pred)
				end
			end
			return out
		end,
	}
end

-- Integer shrinking toward `origin`: origin first, then successively smaller jumps.
function Tree.integral(x, origin)
	return {
		value = x,
		children = function()
			local out = {}
			if x == origin then
				return out
			end
			out[1] = Tree.integral(origin, origin)
			local d = x - origin
			while true do
				d = d >= 0 and math.floor(d / 2) or math.ceil(d / 2)
				if d == 0 then
					break
				end
				out[#out + 1] = Tree.integral(x - d, origin)
			end
			return out
		end,
	}
end

-- Float shrinking toward `origin`: origin, the nearest whole number, then halving steps.
function Tree.fractional(x, origin)
	return {
		value = x,
		children = function()
			local out = {}
			local diff = x - origin
			if diff == 0 or diff ~= diff then
				return out
			end
			out[1] = Tree.fractional(origin, origin)
			local whole = x > origin and math.floor(x) or math.ceil(x)
			if whole ~= x and whole ~= origin and math.abs(whole - origin) < math.abs(diff) then
				out[#out + 1] = Tree.fractional(whole, origin)
			end
			local d = diff
			for _ = 1, 8 do
				d = d / 2
				if math.abs(d) < 1e-9 then
					break
				end
				out[#out + 1] = Tree.fractional(x - d, origin)
			end
			return out
		end,
	}
end

local function valuesOf(trees)
	local values = {}
	for i, t in ipairs(trees) do
		values[i] = t.value
	end
	return values
end

-- Combine trees into a tree of arrays. Shrinks by removing chunks (halves first, down to
-- single elements) and then by shrinking individual elements. `fixed` disables removal
-- (used for tuples/records, whose length can't change).
function Tree.sequence(trees, minLen, fixed)
	minLen = minLen or 0
	return {
		value = valuesOf(trees),
		children = function()
			local out = {}
			local n = #trees
			if not fixed then
				local k = n
				while k >= 1 do
					if n - k >= minLen then
						local offset = 1
						while offset + k - 1 <= n do
							local rest = {}
							for i, t in ipairs(trees) do
								if i < offset or i >= offset + k then
									rest[#rest + 1] = t
								end
							end
							out[#out + 1] = Tree.sequence(rest, minLen, fixed)
							offset += k
						end
					end
					k = math.floor(k / 2)
				end
			end
			for i, t in ipairs(trees) do
				for _, child in ipairs(t.children()) do
					local copy = table.clone(trees)
					copy[i] = child
					out[#out + 1] = Tree.sequence(copy, minLen, fixed)
				end
			end
			return out
		end,
	}
end

return Tree
