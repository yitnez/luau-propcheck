--!nonstrict
-- lune run examples/basic
local PropCheck = require("../src/PropCheck")
local Gen = PropCheck.Gen

-- Passes
PropCheck.run("reversing twice is the identity", Gen.array(Gen.int()), function(xs)
	local reversed = {}
	for i = #xs, 1, -1 do
		table.insert(reversed, xs[i])
	end
	local back = {}
	for i = #reversed, 1, -1 do
		table.insert(back, reversed[i])
	end
	return table.concat(xs, ",") == table.concat(back, ",")
end)

-- Fails on purpose: watch it shrink to a minimal counterexample, e.g. {0, 0, 0, 0, 0, 0}... or smaller
PropCheck.run("every array is shorter than 4 (false!)", Gen.array(Gen.natural()), function(xs)
	return #xs < 4
end)

-- Records and strings
PropCheck.run(
	"names are never empty",
	Gen.record({ name = Gen.string(1, 8), age = Gen.integer(0, 120) }),
	function(person)
		return #person.name > 0
	end
)
