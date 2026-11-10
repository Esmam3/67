-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- BogusControlFlow.lua
--
-- This Step inserts fake control-flow paths with complex interconnected logic,
-- creating a web of unreachable but realistic-looking code branches that
-- confuse decompilers and static analysis tools.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local BogusControlFlow = Step:extend()
BogusControlFlow.Description = "This Step inserts fake control-flow paths with interconnected opaque predicates to confuse decompilers."
BogusControlFlow.Name = "Bogus Control Flow"

BogusControlFlow.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that a given block will be transformed",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	Complexity = {
		name = "Complexity",
		description = "Complexity level of bogus branches (1=simple, 5=deeply nested)",
		type = "number",
		default = 3,
		min = 1,
		max = 5,
	},
}

function BogusControlFlow:init(_) end

-- Statements that must NOT be folded into a wrapped bogus branch.
-- Return/Break/Continue are block terminators. Local declarations must stay at
-- the parent scope: moving them into a nested if-block would hide the declared
-- locals from later sibling statements ("Local binding is not accessible").
local skipKinds = {
	[AstKind.ReturnStatement] = true,
	[AstKind.BreakStatement] = true,
	[AstKind.ContinueStatement] = true,
	[AstKind.LocalVariableDeclaration] = true,
	[AstKind.LocalFunctionDeclaration] = true,
}

local function makeOpaqueTrue(sym, span)
	local v = Ast.VariableExpression(sym)
	local generators = {
		function()
			return Source.fill(
				Ast.GreaterThanOrEqualsExpression(
					Ast.MulExpression(v, v, false),
					Ast.NumberExpression(0),
					false
				), span)
		end,
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.ModExpression(
						Ast.MulExpression(
							v,
							Ast.AddExpression(v, Ast.NumberExpression(1), false),
							false
						),
						Ast.NumberExpression(2),
						false
					),
					Ast.NumberExpression(0),
					false
				), span)
		end,
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.SubExpression(v, v, false),
					Ast.NumberExpression(0),
					false
				), span)
		end,
		function()
			return Source.fill(
				Ast.GreaterThanOrEqualsExpression(
					Ast.AddExpression(
						Ast.MulExpression(v, v, false),
						Ast.NumberExpression(1),
						false
					),
					Ast.NumberExpression(1),
					false
				), span)
		end,
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.ModExpression(
						Ast.AddExpression(
							Ast.MulExpression(v, v, false),
							v,
							false
						),
						Ast.NumberExpression(2),
						false
					),
					Ast.NumberExpression(0),
					false
				), span)
		end,
	}
	return generators[math.random(1, #generators)]()
end

local function makeOpaqueFalse(sym, span)
	local v = Ast.VariableExpression(sym)
	local generators = {
		function()
			return Source.fill(
				Ast.LessThanExpression(
					Ast.MulExpression(v, v, false),
					Ast.NumberExpression(0),
					false
				), span)
		end,
		function()
			return Source.fill(
				Ast.NotEqualsExpression(
					Ast.SubExpression(v, v, false),
					Ast.NumberExpression(0),
					false
				), span)
		end,
		function()
			return Source.fill(
				Ast.GreaterThanExpression(
					Ast.NumberExpression(0),
					Ast.AddExpression(
						Ast.MulExpression(v, v, false),
						Ast.NumberExpression(1),
						false
					),
					false
				), span)
		end,
	}
	return generators[math.random(1, #generators)]()
end

local function makeFakeStatements(span, depth)
	local stmts = {}
	local count = math.random(2, 4)
	for _ = 1, count do
		local pick = math.random(1, 5)
		if pick == 1 then
			local sym = Ast.LocalSymbol("_bcf" .. tostring(math.random(1, 99999)))
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration(
					{sym},
					{Ast.AddExpression(
						Ast.NumberExpression(math.random(-999, 999)),
						Ast.NumberExpression(math.random(1, 999)),
						false
					)}
				), span)
		elseif pick == 2 then
			local sym = Ast.LocalSymbol("_bx" .. tostring(math.random(1, 99999)))
			local sym2 = Ast.LocalSymbol("_by" .. tostring(math.random(1, 99999)))
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration(
					{sym, sym2},
					{Ast.NumberExpression(math.random(1, 9999)),
					 Ast.StringExpression("_" .. tostring(math.random(1, 99999)))}
				), span)
		elseif pick == 3 then
			local sym = Ast.LocalSymbol("_bt" .. tostring(math.random(1, 99999)))
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration(
					{sym},
					{Ast.FunctionCallExpression(
						Ast.GlobalVariableExpression("type"),
						{Ast.StringExpression("")}
					)}
				), span)
		elseif pick == 4 and depth > 0 then
			local innerStmts = makeFakeStatements(span, depth - 1)
			stmts[#stmts + 1] = Source.fill(
				Ast.DoStatement(Ast.Block(innerStmts)), span)
		else
			local sym = Ast.LocalSymbol("_bm" .. tostring(math.random(1, 99999)))
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration(
					{sym},
					{Ast.MulExpression(
						Ast.NumberExpression(math.random(1, 100)),
						Ast.AddExpression(
							Ast.NumberExpression(math.random(1, 100)),
							Ast.NumberExpression(math.random(1, 100)),
							false
						),
						false
					)}
				), span)
		end
	end
	return stmts
end

local function makeBogusBranch(realStatements, guardSym, span, complexity)
	local fakeElse = makeFakeStatements(span, math.min(complexity, 3))

	local condition = makeOpaqueTrue(guardSym, span)
	local trueBlock = Ast.Block(realStatements)
	local elseBlock = Ast.Block(fakeElse)

	local wrapped = Source.fill(
		Ast.IfStatement(condition, trueBlock, {}, elseBlock),
		span)

	if complexity >= 3 then
		local falseCondition = makeOpaqueFalse(guardSym, span)
		local outerFake = makeFakeStatements(span, math.min(complexity - 2, 2))
		local outerTrueBlock = Ast.Block(outerFake)
		local outerElseBlock = Ast.Block({wrapped})

		wrapped = Source.fill(
			Ast.IfStatement(falseCondition, outerTrueBlock, {}, outerElseBlock),
			span)
	end

	if complexity >= 5 then
		local midCondition = makeOpaqueTrue(guardSym, span)
		local midFake = makeFakeStatements(span, 1)
		local midElseBlock = Ast.Block(midFake)
		local midTrueBlock = Ast.Block({wrapped})

		wrapped = Source.fill(
			Ast.IfStatement(midCondition, midTrueBlock, {}, midElseBlock),
			span)
	end

	return wrapped
end

local function makeInterconnectedBlock(stmts, guardSym, span, complexity)
	local result = {}
	local chunk = {}

	for _, stmt in ipairs(stmts) do
		if skipKinds[stmt.kind] then
			if #chunk > 0 then
				result[#result + 1] = makeBogusBranch(chunk, guardSym, span, complexity)
				chunk = {}
			end
			result[#result + 1] = stmt
		else
			chunk[#chunk + 1] = stmt
			if #chunk >= math.random(2, 4) then
				result[#result + 1] = makeBogusBranch(chunk, guardSym, span, complexity)
				chunk = {}
			end
		end
	end

	if #chunk > 0 then
		result[#result + 1] = makeBogusBranch(chunk, guardSym, span, complexity)
	end

	return result
end

function BogusControlFlow:apply(ast, pipeline)
	local span = Source.generated("BogusControlFlow")
	local threshold = self.Threshold
	local complexity = self.Complexity

	local guardSym = Ast.LocalSymbol("_bcfg")
	local guardDecl = Source.fill(
		Ast.LocalVariableDeclaration(
			{guardSym},
			{Ast.NumberExpression(math.random(2, 100000))}
		), span)

	local helperSyms = {}
	local helperDecls = {}

	if complexity >= 4 then
		for i = 1, math.min(complexity - 2, 3) do
			local hSym = Ast.LocalSymbol("_bcfh" .. tostring(i))
			helperSyms[i] = hSym
			helperDecls[i] = Source.fill(
				Ast.LocalVariableDeclaration(
					{hSym},
					{Ast.AddExpression(
						Ast.MulExpression(
							Ast.VariableExpression(guardSym),
							Ast.NumberExpression(math.random(1, 50)),
							false
						),
						Ast.NumberExpression(math.random(1, 100)),
						false
					)}
				), span)
		end
	end

	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.Block then
			if #node.statements < 2 then return end
			if math.random() > threshold then return end

			local newStmts = makeInterconnectedBlock(
				node.statements, guardSym, span, complexity)
			node.statements = newStmts
		end
	end)

	for i = #helperDecls, 1, -1 do
		table.insert(ast.body.statements, 1, helperDecls[i])
	end
	table.insert(ast.body.statements, 1, guardDecl)

	return ast
end

return BogusControlFlow
