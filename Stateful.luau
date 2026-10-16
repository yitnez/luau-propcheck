--!nonstrict
-- Model-based (stateful) testing. Generate a random sequence of commands from a pure model,
-- run them against the real system, and shrink failing sequences to the shortest repro.
--
-- spec = {
--   initialState = () -> modelState,
--   setup        = (() -> sut)?,              -- fresh system under test per sequence
--   teardown     = ((sut) -> ())?,
--   maxCommands  = number?,                   -- default 30
--   commands = {
--     {
--       name  = "push",
--       args  = ((modelState) -> Gen)?,       -- generator for this command's arguments
--       requires = ((modelState) -> boolean)?,-- is the command available in this state?
--       valid = ((modelState, args) -> boolean)?, -- re-checked at run time (shrinking can invalidate args)
--       run   = (sut, args, modelState) -> result,
--       post  = ((modelStateBefore, args, result, sut) -> boolean)?,
--       next  = ((modelState, args) -> modelState)?, -- must return a NEW state, not mutate
--     },
--   },
-- }

local function req(name)
	if script then
		return require(script.Parent[name]) -- Roblox
	end
	return require("./" .. name) -- Lune
end

local Gen = req("Gen")
local Tree = req("Tree")
local Runner = req("Runner")
local Inspect = req("Inspect")

local Stateful = {}

function Stateful.gen(spec)
	local maxCommands = spec.maxCommands or 30
	return Gen.new(function(rng, size)
		local n = rng:int(0, math.min(maxCommands, math.max(size, 1)))
		local state = spec.initialState()
		local trees = {}
		for _ = 1, n do
			local available = {}
			for _, command in ipairs(spec.commands) do
				if not command.requires or command.requires(state) then
					available[#available + 1] = command
				end
			end
			if #available == 0 then
				break
			end
			local command = available[rng:int(1, #available)]
			local argTree
			if command.args then
				argTree = command.args(state).sample(rng, size)
			else
				argTree = Tree.singleton(nil)
			end
			trees[#trees + 1] = Tree.map(argTree, function(args)
				return { command = command, args = args }
			end)
			if command.next then
				state = command.next(state, argTree.value)
			end
		end
		return Tree.sequence(trees, 0)
	end)
end

-- Execute a command sequence. Throws on failure; commands whose preconditions no longer
-- hold (after shrinking removed earlier steps) are skipped.
function Stateful.run(spec, steps)
	local sut = spec.setup and spec.setup() or nil
	local state = spec.initialState()
	local ok, err = pcall(function()
		for i, step in ipairs(steps) do
			local command, args = step.command, step.args
			local runnable = (not command.requires or command.requires(state))
				and (not command.valid or command.valid(state, args))
			if runnable then
				local result = command.run(sut, args, state)
				if command.post and command.post(state, args, result, sut) == false then
					error(("postcondition failed at step %d (%s)"):format(i, command.name), 0)
				end
				if command.next then
					state = command.next(state, args)
				end
			end
		end
	end)
	if spec.teardown then
		pcall(spec.teardown, sut)
	end
	if not ok then
		error(err, 0)
	end
	return true
end

function Stateful.describe(steps)
	if #steps == 0 then
		return "(no commands)"
	end
	local lines = {}
	for i, step in ipairs(steps) do
		local args = step.args == nil and "" or Inspect(step.args)
		lines[i] = ("    %d. %s(%s)"):format(i, step.command.name, args)
	end
	return "\n" .. table.concat(lines, "\n")
end

function Stateful.check(spec, opts)
	local options = table.clone(opts or {})
	options.show = options.show or Stateful.describe
	return Runner.check(Stateful.gen(spec), function(steps)
		return Stateful.run(spec, steps)
	end, options)
end

function Stateful.assert(spec, opts)
	local result = Stateful.check(spec, opts)
	if not result.ok then
		error(Runner.format(result), 0)
	end
	return result
end

return Stateful
