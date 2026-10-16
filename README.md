# luau-propcheck

Property-based testing for Luau & Roblox: random generators, integrated shrinking, seed replay, and stateful testing. Runs in Lune, Jest-Lua, and TestEZ.

Instead of hand-writing examples, you state a **property** that should hold for *all* inputs. `luau-propcheck` throws hundreds of random inputs at it, and when one fails it **shrinks** the input to the smallest failing case and prints a **seed** so you can replay it.

```
Property failed after 12 test(s) (seed = 1830291204)
  Counterexample (after 9 shrinks): { 0, 0, 0, 0 }
  Original: { 31, 58, 7, 90, 12, 4 }
  Error: property returned false
  Replay: pass { seed = 1830291204 } in the options
```

> Status: early (v0.1). The core works; the API may still change.

## Install

**Wally**
```toml
[dependencies]
PropCheck = "yitnez/luau-propcheck@0.1.0"
```

**Lune / git:** clone or vendor the `src/` folder and `require("./src/PropCheck")`.

## Quick start

```lua
local PropCheck = require("./src/PropCheck")
local Gen = PropCheck.Gen

-- Pass an array of generators and the property gets one argument per generator.
PropCheck.run("addition commutes", { Gen.int(), Gen.int() }, function(a, b)
	return a + b == b + a
end)
```

A property **passes** unless it returns `false` or throws, so you can use plain `assert`/`expect` inside it.

### Lune
`PropCheck.run(name, gens, prop, opts)` prints PASS/FAIL. Or use `PropCheck.assertProperty(...)` to throw on failure.

### Jest-Lua / TestEZ
```lua
local PropCheck = require(Packages.PropCheck)
local Gen = PropCheck.Gen
local property = PropCheck.property(it) -- bind to your framework's `it`

describe("sorting", function()
	property("is idempotent", Gen.array(Gen.int()), function(xs)
		local once = table.clone(xs); table.sort(once)
		local twice = table.clone(once); table.sort(twice)
		return table.concat(once, ",") == table.concat(twice, ",")
	end)
end)
```
Or call `PropCheck.assertProperty(gen, prop, opts)` inside any `it` block.

## Generators

| Generator | Notes |
|---|---|
| `Gen.integer(min, max)` | shrinks toward 0 (or nearest bound) |
| `Gen.int()` / `Gen.natural()` | magnitude grows with test size |
| `Gen.float(min, max)` / `Gen.number()` | |
| `Gen.boolean()` | shrinks to `false` |
| `Gen.constant(v)` / `Gen.elements(list)` | |
| `Gen.string(minLen, maxLen, charset?)` | |
| `Gen.array(elem, minLen?, maxLen?)` | shrinks by removing elements, then shrinking them |
| `Gen.tuple({ g1, g2 })` / `Gen.record({ k = g })` | |
| `Gen.oneOf(gens)` / `Gen.frequency({ {3, g1}, {1, g2} })` | |
| `g:map(f)` / `g:filter(pred)` / `g:bind(f)` | shrinking works through all of them |
| `Gen.sized(fn)` | build a generator from the current size |
| `Gen.vector3()` / `Gen.color3()` / `Gen.cframe()` | Roblox only |

Because shrinking is **integrated** (each generated value carries its own shrink tree), custom generators built with `map`/`bind`/`record` shrink for free. No separate shrinker to write.

## Options

```lua
PropCheck.check(gen, prop, {
	numRuns = 100,      -- passing tests required
	seed = 12345,       -- replay a failure
	maxSize = 100,      -- upper bound for sized generators
	maxShrinks = 500,   -- shrink budget
	maxDiscards = 1000, -- give up after this many assume() rejections
	show = tostring,    -- custom counterexample printer
})
```

`PropCheck.assume(cond)` discards inputs that don't meet a precondition.

## Seed replay

Every failure prints its `seed`. Pass it back as `{ seed = ... }` and the exact same inputs are generated, in Lune, Roblox, or Jest-Lua (the PRNG is implemented in pure Luau, not tied to `Random`).

## Stateful testing

Describe a pure model plus commands; `luau-propcheck` generates random command sequences, runs them against your real system, and shrinks failures to the shortest sequence.

```lua
PropCheck.stateful.assert({
	initialState = function() return {} end,       -- model: list of items
	setup = function() return Stack.new() end,     -- real system, fresh per sequence
	commands = {
		{
			name = "push",
			args = function() return Gen.int() end,
			run = function(sut, x) sut:push(x) return sut:size() end,
			post = function(model, _, size) return size == #model + 1 end,
			next = function(model, x)
				local new = table.clone(model); table.insert(new, x); return new
			end,
		},
		{
			name = "pop",
			requires = function(model) return #model > 0 end,
			run = function(sut) return sut:pop() end,
			post = function(model, _, result) return result == model[#model] end,
			next = function(model)
				local new = table.clone(model); table.remove(new); return new
			end,
		},
	},
})
```

`next` must return a new state rather than mutate, since sequences are replayed while shrinking.

## Development

```
lune run tests/selftest
lune run examples/basic
```

## Roadmap

- Roblox-side test runner example (Jest-Lua + TestEZ projects)
- Parallel/concurrency stateful testing
- More generators (UDim2, Instances, Enums), recursive generators
- Typed (`--!strict`) API

## License

MIT
