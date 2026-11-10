-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- namegenerators/unicode_homoglyph.lua
--
-- This Script provides a name generator that uses Cyrillic and Greek Unicode
-- characters that are visually identical or near-identical to Latin letters.
-- The resulting identifiers look like normal English variable names but use
-- entirely different codepoints, confusing both humans and automated tools.
-- Only works with LuaU; falls back to mangled names on Lua 5.1.

local util = require("prometheus.util")

-- Mapping of Latin letters to their Cyrillic/Greek homoglyphs.
-- Each entry: { latin_char, homoglyph_codepoint }
-- These are carefully chosen to be visually indistinguishable in most fonts.
local homoglyphs = {
	{ "a", 0x0430 }, -- Cyrillic Small Letter A
	{ "c", 0x0441 }, -- Cyrillic Small Letter ES
	{ "e", 0x0435 }, -- Cyrillic Small Letter IE
	{ "o", 0x043E }, -- Cyrillic Small Letter O
	{ "p", 0x0440 }, -- Cyrillic Small Letter ER
	{ "s", 0x0455 }, -- Cyrillic Small Letter DZE
	{ "x", 0x0445 }, -- Cyrillic Small Letter HA
	{ "y", 0x0443 }, -- Cyrillic Small Letter U
	{ "A", 0x0410 }, -- Cyrillic Capital Letter A
	{ "B", 0x0412 }, -- Cyrillic Capital Letter VE
	{ "C", 0x0421 }, -- Cyrillic Capital Letter ES
	{ "E", 0x0415 }, -- Cyrillic Capital Letter IE
	{ "H", 0x041D }, -- Cyrillic Capital Letter EN
	{ "K", 0x041A }, -- Cyrillic Capital Letter KA
	{ "M", 0x041C }, -- Cyrillic Capital Letter EM
	{ "O", 0x041E }, -- Cyrillic Capital Letter O
	{ "P", 0x0420 }, -- Cyrillic Capital Letter ER
	{ "T", 0x0422 }, -- Cyrillic Capital Letter TE
	{ "X", 0x0425 }, -- Cyrillic Capital Letter HA
	{ "i", 0x0456 }, -- Cyrillic Small Letter Byelorussian-Ukrainian I
	{ "j", 0x0458 }, -- Cyrillic Small Letter JE
	{ "h", 0x04BB }, -- Cyrillic Small Letter Shha
	{ "d", 0x0501 }, -- Cyrillic Small Letter Komi De
	{ "q", 0x051B }, -- Cyrillic Small Letter Qa
	{ "w", 0x051D }, -- Cyrillic Small Letter We
}

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

-- Build the encoded homoglyph characters
local chars = {}
for i, entry in ipairs(homoglyphs) do
	chars[i] = utf8char(entry[2])
end

-- Word fragments that look like real variable names when composed
local prefixes = {
	"data", "config", "state", "cache", "scope", "ctx", "obj", "key",
	"idx", "pos", "opt", "spec", "doc", "src", "desc", "exec",
}
local suffixes = {
	"Map", "Set", "Ops", "Mix", "Ctx", "Pos", "Top", "Idx",
	"Res", "Src", "Key", "Api", "Acc", "Max", "Hex", "Tcp",
}

-- Apply homoglyph substitutions to a string
local homoglyphMap = {}
for _, entry in ipairs(homoglyphs) do
	homoglyphMap[entry[1]] = utf8char(entry[2])
end

local function applyHomoglyphs(str)
	local out = {}
	for i = 1, #str do
		local ch = str:sub(i, i)
		if homoglyphMap[ch] and math.random() > 0.3 then
			out[i] = homoglyphMap[ch]
		else
			out[i] = ch
		end
	end
	local result = table.concat(out)
	if result == str then
		for i = 1, #str do
			local ch = str:sub(i, i)
			if homoglyphMap[ch] then
				out[i] = homoglyphMap[ch]
				return table.concat(out)
			end
		end
	end
	return result
end

local function generateName(id, _)
	local pIdx = id % #prefixes
	local sIdx = math.floor(id / #prefixes) % #suffixes
	local gen = math.floor(id / (#prefixes * #suffixes))

	local base
	if gen == 0 then
		base = prefixes[pIdx + 1]
	else
		base = prefixes[pIdx + 1] .. suffixes[sIdx + 1]
		if gen > 1 then
			base = base .. tostring(gen)
		end
	end

	return applyHomoglyphs(base)
end

local function prepare(_)
	util.shuffle(prefixes)
	util.shuffle(suffixes)
	util.shuffle(chars)
end

return {
	generateName = generateName,
	prepare = prepare,
}
