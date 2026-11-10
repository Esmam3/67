-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- DeadCodeInjection.lua
--
-- This Step injects realistic-looking dead code blocks that never execute,
-- increasing the complexity of reverse engineering.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local DeadCodeInjection = Step:extend()
DeadCodeInjection.Description = "This Step injects realistic dead code blocks that never execute."
DeadCodeInjection.Name = "Dead Code Injection"

DeadCodeInjection.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that dead code is injected at each eligible point",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	Intensity = {
		name = "Intensity",
		description = "Number of dead code fragments injected per insertion point",
		type = "number",
		default = 2,
		min = 1,
		max = 5,
	},
}

function DeadCodeInjection:init(_) end

-- Helpers to generate random identifiers.
local function randomIdent(prefix)
	return (prefix or "_dc") .. tostring(math.random(10000, 99999))
end

-- Build a chain of arithmetic that looks complex but is meaningless.
local function randomArithExpr(depth, span)
	if depth <= 0 or math.random() < 0.3 then
		return Source.fill(Ast.NumberExpression(math.random(-9999, 9999)), span)
	end
	local ops = {
		function(a, b) return Ast.AddExpression(a, b, false) end,
		function(a, b) return Ast.SubExpression(a, b, false) end,
		function(a, b) return Ast.MulExpression(a, b, false) end,
		function(a, b) return Ast.ModExpression(a, b, false) end,
	}
	local op = ops[math.random(1, #ops)]
	return Source.fill(
		op(randomArithExpr(depth - 1, span), randomArithExpr(depth - 1, span)),
		span
	)
end

-- Build a realistic-looking string expression.
local function randomStringExpr(span)
	local strs = {"init", "data", "state", "cache", "buffer", "index", "value",
		"result", "temp", "config", "meta", "key", "flag", "token", "node"}
	return Source.fill(
		Ast.StringExpression(strs[math.random(1, #strs)] .. tostring(math.random(1, 999))),
		span
	)
end

-- Dead code pattern generators. Each returns a list of statements.
local function makeDeadLocalDecl(span)
	-- local _dcXXXXX = <complex arithmetic>
	local sym = Ast.LocalSymbol(randomIdent("_v"))
	return Source.fill(
		Ast.LocalVariableDeclaration({sym}, {randomArithExpr(2, span)}),
		span
	)
end

local function makeDeadIfBlock(span)
	-- if (false) then <body> end  -- disguised as arithmetic check
	-- Uses an always-false condition: random ~= random (same constant)
	local val = math.random(10000, 99999)
	local condition = Source.fill(
		Ast.EqualsExpression(
			Ast.NumberExpression(val),
			Ast.NumberExpression(val + 1),
			false
		), span)

	local innerStmts = {}
	for _ = 1, math.random(1, 3) do
		local sym = Ast.LocalSymbol(randomIdent("_w"))
		innerStmts[#innerStmts + 1] = Source.fill(
			Ast.LocalVariableDeclaration({sym}, {randomArithExpr(1, span)}),
			span
		)
	end

	return Source.fill(
		Ast.IfStatement(condition, Ast.Block(innerStmts), {}, nil),
		span
	)
end

local function makeDeadWhileBlock(span)
	-- while (N == N+1) do <body> end  (never iterates)
	local val = math.random(1, 99999)
	local condition = Source.fill(
		Ast.EqualsExpression(
			Ast.NumberExpression(val),
			Ast.AddExpression(
				Ast.NumberExpression(val),
				Ast.NumberExpression(1),
				false
			),
			false
		), span)

	local sym = Ast.LocalSymbol(randomIdent("_q"))
	local body = Ast.Block({
		Source.fill(
			Ast.LocalVariableDeclaration({sym}, {randomArithExpr(1, span)}),
			span
		),
	})

	return Source.fill(Ast.WhileStatement(body, condition), span)
end

local function makeDeadFunction(span)
	-- local function _dcXXXXX(a, b) local c = a + b; return c end
	local funcSym = Ast.LocalSymbol(randomIdent("_fn"))
	local argA = Ast.LocalSymbol("a")
	local argB = Ast.LocalSymbol("b")
	local localSym = Ast.LocalSymbol("c")

	local bodyStmts = {
		Source.fill(
			Ast.LocalVariableDeclaration(
				{localSym},
				{Ast.AddExpression(
					Ast.VariableExpression(argA),
					Ast.VariableExpression(argB),
					false
				)}
			), span),
		Source.fill(
			Ast.ReturnStatement({Ast.VariableExpression(localSym)}),
			span
		),
	}

	local body = Ast.Block(bodyStmts)
	body.isFunctionBlock = true

	return Source.fill(
		Ast.LocalFunctionDeclaration(funcSym, {argA, argB}, body),
		span
	)
end

local function makeDeadDoBlock(span)
	-- do local _x = "str"; local _y = 123 + 456 end
	local stmts = {}
	for _ = 1, math.random(2, 4) do
		local sym = Ast.LocalSymbol(randomIdent("_z"))
		if math.random() < 0.5 then
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration({sym}, {randomStringExpr(span)}),
				span
			)
		else
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration({sym}, {randomArithExpr(2, span)}),
				span
			)
		end
	end
	return Source.fill(Ast.DoStatement(Ast.Block(stmts)), span)
end

local function makeDeadMultiLocal(span)
	-- local _a, _b, _c = <expr>, <expr>, <expr>
	local count = math.random(2, 4)
	local syms = {}
	local exprs = {}
	for i = 1, count do
		syms[i] = Ast.LocalSymbol(randomIdent("_m"))
		if math.random() < 0.5 then
			exprs[i] = randomArithExpr(1, span)
		else
			exprs[i] = randomStringExpr(span)
		end
	end
	return Source.fill(Ast.LocalVariableDeclaration(syms, exprs), span)
end

-- All dead code generators.
local generators = {
	makeDeadLocalDecl,
	makeDeadIfBlock,
	makeDeadWhileBlock,
	makeDeadFunction,
	makeDeadDoBlock,
	makeDeadMultiLocal,
}

function DeadCodeInjection:apply(ast, pipeline)
	local generatedSpan = Source.generated("DeadCodeInjection")
	local threshold = self.Threshold
	local intensity = self.Intensity

	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.Block then
			local newStatements = {}
			for _, stmt in ipairs(node.statements) do
				-- Possibly inject dead code before this statement.
				if math.random() < threshold then
					local count = math.random(1, intensity)
					local shuffled = util.shuffle({1, 2, 3, 4, 5, 6})
					for i = 1, count do
						local gen = generators[shuffled[i] or shuffled[1]]
						newStatements[#newStatements + 1] = gen(generatedSpan)
					end
				end
				newStatements[#newStatements + 1] = stmt
			end
			node.statements = newStatements
		end
	end)

	return ast
end

return DeadCodeInjection
