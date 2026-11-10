-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- namegenerators.lua
--
-- This Script provides a collection of name generators for Prometheus.

return {
	Mangled = require("prometheus.namegenerators.mangled");
	MangledShuffled = require("prometheus.namegenerators.mangled_shuffled");
	Il = require("prometheus.namegenerators.Il");
	Number = require("prometheus.namegenerators.number");
	Confuse = require("prometheus.namegenerators.confuse");
	Hex = require("prometheus.namegenerators.hex");
	Chinese = require("prometheus.namegenerators.chinese");
	Homoglyph = require("prometheus.namegenerators.unicode_homoglyph");
}