-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- MBAObfuscation.lua
--
-- This Step applies Mixed Boolean-Arithmetic transformations to arithmetic
-- expressions, replacing simple operations with mathematically equivalent
-- but much more complex forms. All transforms are pure arithmetic (no
-- bitwise ops) for Lua 5.1 compatibility.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")

local AstKind = Ast.AstKind

local MBAObfuscation = Step:extend()
MBAObfuscation.Description = "This Step replaces arithmetic with mathematically equivalent complex expressions."
MBAObfuscation.Name = "MBA Obfuscation"

MBAObfuscation.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that a given arithmetic expression will be transformed",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	Depth = {
		name = "Depth",
		description = "Maximum recursion depth for nested MBA transforms",
		type = "number",
		default = 2,
		min = 1,
		max = 4,
	},
}

function MBAObfuscation:init(_) end

-- Generate random non-zero constants for MBA identities.
local function randK()
	local k = math.random(1, 9999)
	if math.random() > 0.5 then k = -k end
	return k
end

-- Transform: a + b → (a + K1) + (b + K2) - (K1 + K2)
-- Identity: always equals a + b regardless of K1, K2
local function transformAdd(lhs, rhs, generatedSpan)
	local k1 = randK()
	local k2 = randK()
	local sum_k = k1 + k2

	-- (a + K1)
	local left = Ast.AddExpression(lhs, Ast.NumberExpression(k1), false)
	-- (b + K2)
	local right = Ast.AddExpression(rhs, Ast.NumberExpression(k2), false)
	-- (a + K1) + (b + K2)
	local added = Ast.AddExpression(left, right, false)
	-- (a + K1) + (b + K2) - (K1 + K2)
	local result = Ast.SubExpression(added, Ast.NumberExpression(sum_k), false)

	return Source.fill(result, generatedSpan)
end

-- Transform: a - b → (a + K) - (b + K)
-- Identity: (a + K) - (b + K) = a - b
local function transformSub(lhs, rhs, generatedSpan)
	local k = randK()

	-- (a + K)
	local left = Ast.AddExpression(lhs, Ast.NumberExpression(k), false)
	-- (b + K)
	local right = Ast.AddExpression(rhs, Ast.NumberExpression(k), false)
	-- (a + K) - (b + K)
	local result = Ast.SubExpression(left, right, false)

	return Source.fill(result, generatedSpan)
end

-- Transform: a * b → ((a + b)^2 - (a - b)^2) / 4
-- Identity: (a+b)^2 - (a-b)^2 = 4ab
local function transformMul(lhs, rhs, generatedSpan)
	-- (a + b)
	local sum = Ast.AddExpression(lhs, rhs, false)
	-- (a - b)
	local diff = Ast.SubExpression(lhs, rhs, false)
	-- (a + b)^2
	local sumSq = Ast.PowExpression(sum, Ast.NumberExpression(2), false)
	-- (a - b)^2
	local diffSq = Ast.PowExpression(diff, Ast.NumberExpression(2), false)
	-- (a + b)^2 - (a - b)^2
	local subbed = Ast.SubExpression(sumSq, diffSq, false)
	-- ((a + b)^2 - (a - b)^2) / 4
	local result = Ast.DivExpression(subbed, Ast.NumberExpression(4), false)

	return Source.fill(result, generatedSpan)
end

-- Transform: a + b → a - (-b)  (simple form for variety)
local function transformAddAlt(lhs, rhs, generatedSpan)
	local negB = Ast.NegateExpression(rhs)
	local result = Ast.SubExpression(lhs, negB, false)
	return Source.fill(result, generatedSpan)
end

-- Transform: a - b → a + (-b)  (simple form for variety)
local function transformSubAlt(lhs, rhs, generatedSpan)
	local negB = Ast.NegateExpression(rhs)
	local result = Ast.AddExpression(lhs, negB, false)
	return Source.fill(result, generatedSpan)
end

-- Transform: -a → (0 - a)  or  (K - (a + K))
local function transformNeg(rhs, generatedSpan)
	if math.random() > 0.5 then
		local result = Ast.SubExpression(Ast.NumberExpression(0), rhs, false)
		return Source.fill(result, generatedSpan)
	else
		local k = randK()
		-- K - (a + K) = -a
		local inner = Ast.AddExpression(rhs, Ast.NumberExpression(k), false)
		local result = Ast.SubExpression(Ast.NumberExpression(k), inner, false)
		return Source.fill(result, generatedSpan)
	end
end

-- Transform: a * b → a * (b + K) - a * K  (distributive property)
local function transformMulAlt(lhs, rhs, generatedSpan)
	local k = math.random(1, 99)
	-- b + K
	local bPlusK = Ast.AddExpression(rhs, Ast.NumberExpression(k), false)
	-- a * (b + K)
	local left = Ast.MulExpression(lhs, bPlusK, false)
	-- a * K
	local right = Ast.MulExpression(lhs, Ast.NumberExpression(k), false)
	-- a * (b + K) - a * K
	local result = Ast.SubExpression(left, right, false)
	return Source.fill(result, generatedSpan)
end

-- Wrap an expression in an immediately-invoked function to introduce
-- scope isolation and make dataflow analysis harder.
local function wrapInIIFE(expr, generatedSpan)
	local body = Ast.Block({
		Ast.ReturnStatement({expr})
	})
	local func = Ast.FunctionLiteralExpression({}, body)
	local result = Ast.FunctionCallExpression(func, {})
	return Source.fill(result, generatedSpan)
end

function MBAObfuscation:apply(ast, pipeline)
	local generatedSpan = Source.generated("MBAObfuscation")
	local threshold = self.Threshold
	local maxDepth = self.Depth

	-- Track recursion depth per-visit to avoid infinite expansion
	local currentDepth = 0

	visitast(ast, nil, function(node, data)
		if currentDepth >= maxDepth then return end

		if node.kind == AstKind.AddExpression then
			if math.random() <= threshold then
				currentDepth = currentDepth + 1
				local result
				if math.random() > 0.3 then
					result = transformAdd(node.lhs, node.rhs, generatedSpan)
				else
					result = transformAddAlt(node.lhs, node.rhs, generatedSpan)
				end
				if currentDepth >= 2 and math.random() > 0.6 then
					result = wrapInIIFE(result, generatedSpan)
				end
				currentDepth = currentDepth - 1
				return result
			end

		elseif node.kind == AstKind.SubExpression then
			if math.random() <= threshold then
				currentDepth = currentDepth + 1
				local result
				if math.random() > 0.3 then
					result = transformSub(node.lhs, node.rhs, generatedSpan)
				else
					result = transformSubAlt(node.lhs, node.rhs, generatedSpan)
				end
				if currentDepth >= 2 and math.random() > 0.6 then
					result = wrapInIIFE(result, generatedSpan)
				end
				currentDepth = currentDepth - 1
				return result
			end

		elseif node.kind == AstKind.MulExpression then
			if math.random() <= threshold then
				currentDepth = currentDepth + 1
				local result
				if math.random() > 0.5 then
					result = transformMul(node.lhs, node.rhs, generatedSpan)
				else
					result = transformMulAlt(node.lhs, node.rhs, generatedSpan)
				end
				if currentDepth >= 2 and math.random() > 0.6 then
					result = wrapInIIFE(result, generatedSpan)
				end
				currentDepth = currentDepth - 1
				return result
			end

		elseif node.kind == AstKind.NegateExpression then
			if math.random() <= threshold then
				currentDepth = currentDepth + 1
				local result = transformNeg(node.rhs, generatedSpan)
				currentDepth = currentDepth - 1
				return result
			end
		end
	end)

	return ast
end

return MBAObfuscation
