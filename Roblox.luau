--!nocheck
-- Roblox datatype generators. Installed onto Gen; calling them outside Roblox raises a clear error.

local function install(Gen)
	local function needRoblox(name)
		assert(Vector3 ~= nil, name .. " is only available inside Roblox")
	end

	function Gen.vector3(min, max)
		needRoblox("Gen.vector3")
		local axis = Gen.float(min or -100, max or 100)
		return Gen.tuple({ axis, axis, axis }):map(function(t)
			return Vector3.new(t[1], t[2], t[3])
		end)
	end

	function Gen.color3()
		needRoblox("Gen.color3")
		local channel = Gen.integer(0, 255)
		return Gen.tuple({ channel, channel, channel }):map(function(t)
			return Color3.fromRGB(t[1], t[2], t[3])
		end)
	end

	function Gen.cframe(range)
		needRoblox("Gen.cframe")
		local angle = Gen.float(-math.pi, math.pi)
		return Gen.tuple({ Gen.vector3(-(range or 100), range or 100), angle, angle, angle }):map(function(t)
			return CFrame.new(t[1]) * CFrame.Angles(t[2], t[3], t[4])
		end)
	end
end

return { install = install }
