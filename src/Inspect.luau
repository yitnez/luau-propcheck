--!nonstrict
-- Compact pretty-printer for counterexamples.

local MAX_DEPTH = 6

local function isIdentifier(s)
	return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil
end

local function show(v, depth, seen)
	local ty = typeof(v)
	if ty == "string" then
		return string.format("%q", v)
	elseif ty == "number" or ty == "boolean" or ty == "nil" then
		return tostring(v)
	elseif ty == "function" then
		return "<function>"
	elseif ty == "table" then
		if seen[v] then
			return "<cycle>"
		end
		if depth > MAX_DEPTH then
			return "{...}"
		end
		seen[v] = true
		local parts = {}
		local arrayLen = #v
		local count = 0
		for _ in pairs(v) do
			count += 1
		end
		if count == arrayLen then
			for i = 1, arrayLen do
				parts[i] = show(v[i], depth + 1, seen)
			end
		else
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = k
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in ipairs(keys) do
				local label = isIdentifier(k) and k or ("[" .. show(k, depth + 1, seen) .. "]")
				parts[#parts + 1] = label .. " = " .. show(v[k], depth + 1, seen)
			end
		end
		seen[v] = nil
		if #parts == 0 then
			return "{}"
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	-- Roblox datatypes (Vector3, Color3, Instance, ...)
	local ok, str = pcall(tostring, v)
	return ty .. "(" .. (ok and str or "?") .. ")"
end

return function(value)
	return show(value, 0, {})
end
