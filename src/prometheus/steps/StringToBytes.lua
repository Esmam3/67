-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- StringToBytes.lua
--
-- This Step converts string literals into string.char(...) calls,
-- optionally splitting long strings into concatenated chunks.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")

local AstKind = Ast.AstKind

local StringToBytes = Step:extend()
StringToBytes.Description = "This Step converts string literals to string.char() byte sequences."
StringToBytes.Name = "String To Bytes"

StringToBytes.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that a string is converted",
		type = "number",
		default = 1,
		min = 0,
		max = 1,
	},
	MinLength = {
		name = "MinLength",
		description = "Minimum string length to be converted",
		type = "number",
		default = 1,
		min = 0,
	},
	MaxLength = {
		name = "MaxLength",
		description = "Maximum string length to be converted (longer strings are skipped)",
		type = "number",
		default = 1000,
		min = 1,
	},
}

function StringToBytes:init(_) end

-- Build a string.char(b1, b2, ...) call node from a list of byte values.
local function makeStringCharCall(bytes, stringCharExpr, span)
	local args = {}
	for i = 1, #bytes do
		args[i] = Source.fill(Ast.NumberExpression(bytes[i]), span)
	end
	return Source.fill(
		Ast.FunctionCallExpression(stringCharExpr, args),
		span
	)
end

function StringToBytes:apply(ast, pipeline)
	local generatedSpan = Source.generated("StringToBytes")
	local threshold = self.Threshold
	local minLen = self.MinLength
	local maxLen = self.MaxLength

	-- Create local reference: local _sc = string.char
	local stringCharSym = Ast.LocalSymbol("_string_char")
	local stringCharDecl = Source.fill(
		Ast.LocalVariableDeclaration(
			{stringCharSym},
			{Ast.IndexExpression(
				Ast.GlobalVariableExpression("string"),
				Ast.StringExpression("char")
			)}
		), generatedSpan)

	local used = false

	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.StringExpression then
			local str = node.value
			local len = #str

			-- Skip empty strings, too-short or too-long strings.
			if len < minLen or len > maxLen then
				return
			end

			if math.random() > threshold then
				return
			end

			used = true

			-- Collect all bytes.
			local allBytes = {}
			for i = 1, len do
				allBytes[i] = string.byte(str, i)
			end

			local stringCharExpr = Ast.VariableExpression(stringCharSym)

			-- For short strings (<=8 bytes), one string.char call.
			if len <= 8 then
				return Source.inherit(
					makeStringCharCall(allBytes, stringCharExpr, generatedSpan),
					node
				)
			end

			-- For longer strings, split into random-sized chunks and concatenate.
			local chunks = {}
			local pos = 1
			while pos <= len do
				local chunkSize = math.random(3, 8)
				if pos + chunkSize - 1 > len then
					chunkSize = len - pos + 1
				end
				local chunkBytes = {}
				for i = 1, chunkSize do
					chunkBytes[i] = allBytes[pos + i - 1]
				end
				chunks[#chunks + 1] = chunkBytes
				pos = pos + chunkSize
			end

			-- Build concatenation chain: chunk1 .. chunk2 .. chunk3 ...
			local result = makeStringCharCall(chunks[1], stringCharExpr, generatedSpan)
			for i = 2, #chunks do
				result = Source.fill(
					Ast.StrCatExpression(
						result,
						makeStringCharCall(chunks[i], stringCharExpr, generatedSpan),
						false
					), generatedSpan)
			end

			return Source.inherit(result, node)
		end
	end)

	-- Only insert the helper variable if we actually converted something.
	if used then
		table.insert(ast.body.statements, 1, stringCharDecl)
	end

	return ast
end

return StringToBytes
