-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- namegenerators/hex.lua
--
-- This Script provides a function for generation of hex-like variable names
-- that look like memory addresses or hash values, making the code look like
-- decompiled output.

local util = require("prometheus.util")

local HEX_CHARS = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
local PREFIXES = {"_0x", "_x", "h_", "addr_", "loc_", "sub_", "var_", "fn_", "off_"}
local prefix_pool = {}

local function generateName(id, _)
	-- Generate a hex string from the id
	local hex = ""
	local n = id
	repeat
		local d = n % 16
		n = (n - d) / 16
		hex = HEX_CHARS[d + 1] .. hex
	until n == 0

	-- Pad to at least 4 hex digits
	while #hex < 4 do
		hex = HEX_CHARS[math.random(1, 16)] .. hex
	end

	-- Pick a prefix based on the id
	local pfx = prefix_pool[(id % #prefix_pool) + 1]
	return pfx .. hex
end

local function prepare(_)
	-- Shuffle prefixes and hex chars for variety
	for i = 1, #PREFIXES do
		prefix_pool[i] = PREFIXES[i]
	end
	util.shuffle(prefix_pool)
	util.shuffle(HEX_CHARS)
end

return {
	generateName = generateName,
	prepare = prepare
}
