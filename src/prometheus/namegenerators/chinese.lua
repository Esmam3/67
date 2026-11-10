-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- namegenerators/chinese.lua
--
-- This Script provides a function for generation of variable names using
-- CJK Unicode characters. These are valid Lua identifiers in LuaU and make
-- the code extremely difficult to read for most reverse engineers.
-- Falls back to mangled names on Lua 5.1 where Unicode identifiers are invalid.

local util = require("prometheus.util")

-- Common CJK Unified Ideographs (U+4E00 to U+9FFF)
-- We pick a set of visually similar / confusing characters
local codepoints = {
	0x4E00, 0x4E01, 0x4E03, 0x4E07, 0x4E08, 0x4E09, 0x4E0A, 0x4E0B,
	0x4E0D, 0x4E0E, 0x4E16, 0x4E1A, 0x4E1C, 0x4E24, 0x4E2A, 0x4E2D,
	0x4E3A, 0x4E3B, 0x4E48, 0x4E4B, 0x4E5F, 0x4E86, 0x4E8B, 0x4E8C,
	0x4E8E, 0x4E94, 0x4EA7, 0x4EAB, 0x4EAC, 0x4EBA, 0x4EC0, 0x4ECE,
	0x4ED6, 0x4EE3, 0x4EE5, 0x4EEC, 0x4EF6, 0x4EFB, 0x4F1A, 0x4F46,
	0x4F4D, 0x4F53, 0x4F55, 0x4F5C, 0x4F60, 0x4F7F, 0x4F9B, 0x4FDD,
	0x5165, 0x5168, 0x516C, 0x5171, 0x5173, 0x5176, 0x5185, 0x518D,
	0x51FA, 0x5206, 0x5230, 0x5236, 0x524D, 0x529B, 0x52A0, 0x52A8,
}

-- Convert a Unicode codepoint to its UTF-8 encoded string
local function utf8char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(
			0xC0 + math.floor(cp / 0x40),
			0x80 + cp % 0x40
		)
	elseif cp < 0x10000 then
		return string.char(
			0xE0 + math.floor(cp / 0x1000),
			0x80 + math.floor(cp / 0x40) % 0x40,
			0x80 + cp % 0x40
		)
	end
	return string.char(
		0xF0 + math.floor(cp / 0x40000),
		0x80 + math.floor(cp / 0x1000) % 0x40,
		0x80 + math.floor(cp / 0x40) % 0x40,
		0x80 + cp % 0x40
	)
end

-- Pre-encode characters
local chars = {}
for i, cp in ipairs(codepoints) do
	chars[i] = utf8char(cp)
end

local function generateName(id, _)
	local name = ""
	local n = id
	local d = n % #chars
	n = (n - d) / #chars
	name = chars[d + 1]
	while n > 0 do
		local e = n % #chars
		n = (n - e) / #chars
		name = name .. chars[e + 1]
	end
	return name
end

local function prepare(_)
	util.shuffle(chars)
end

return {
	generateName = generateName,
	prepare = prepare
}
