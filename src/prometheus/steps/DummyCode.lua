-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- DummyCode.lua
--
-- This Step generates realistic-looking interconnected dummy functions and
-- scatters calls to them inside opaque-predicate-guarded dead branches,
-- dramatically increasing the amount of code an analyst must examine.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")

local AstKind = Ast.AstKind

local DummyCode = Step:extend()
DummyCode.Description = "This Step injects interconnected dummy functions with realistic bodies into dead code paths."
DummyCode.Name = "Dummy Code"

DummyCode.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that a given block will receive dummy code injections",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	DummyFunctionCount = {
		name = "DummyFunctionCount",
		description = "Number of dummy functions to generate",
		type = "number",
		default = 5,
		min = 1,
		max = 20,
	},
	InterconnectionLevel = {
		name = "InterconnectionLevel",
		description = "How many cross-calls each dummy function makes to other dummy functions",
		type = "number",
		default = 3,
		min = 1,
		max = 5,
	},
}

function DummyCode:init(_) end

-- Build the body of a single dummy function that looks realistic.
-- It does arithmetic, string ops, table manipulation, and calls other dummies.
local function buildDummyFunctionBody(funcSymbols, selfIndex, interconnectionLevel, generatedSpan)
	local stmts = {}
	local paramSym = Ast.LocalSymbol("x")

	-- Local variable with arithmetic
	local accSym = Ast.LocalSymbol("_acc")
	stmts[#stmts + 1] = Source.fill(
		Ast.LocalVariableDeclaration(
			{accSym},
			{Ast.AddExpression(
				Ast.VariableExpression(paramSym),
				Ast.NumberExpression(math.random(1, 1000)),
				false
			)}
		), generatedSpan)

	-- A conditional with some math
	local condSym = Ast.LocalSymbol("_cond")
	stmts[#stmts + 1] = Source.fill(
		Ast.LocalVariableDeclaration(
			{condSym},
			{Ast.ModExpression(
				Ast.VariableExpression(accSym),
				Ast.NumberExpression(math.random(2, 7)),
				false
			)}
		), generatedSpan)

	-- If block with cross-calls to other dummy functions
	local ifBodyStmts = {}
	local callsMade = 0
	for i = 1, #funcSymbols do
		if i ~= selfIndex and callsMade < interconnectionLevel then
			local callExpr = Ast.FunctionCallExpression(
				Ast.VariableExpression(funcSymbols[i]),
				{Ast.AddExpression(
					Ast.VariableExpression(accSym),
					Ast.NumberExpression(math.random(1, 100)),
					false
				)}
			)
			local resultSym = Ast.LocalSymbol("_r" .. tostring(i))
			ifBodyStmts[#ifBodyStmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration({resultSym}, {callExpr}),
				generatedSpan)
			-- Accumulate the result
			ifBodyStmts[#ifBodyStmts + 1] = Source.fill(
				Ast.AssignmentStatement(
					{Ast.AssignmentVariable(accSym)},
					{Ast.AddExpression(
						Ast.VariableExpression(accSym),
						Ast.VariableExpression(resultSym),
						false
					)}
				), generatedSpan)
			callsMade = callsMade + 1
		end
	end

	if #ifBodyStmts == 0 then
		ifBodyStmts[#ifBodyStmts + 1] = Source.fill(
			Ast.AssignmentStatement(
				{Ast.AssignmentVariable(accSym)},
				{Ast.MulExpression(
					Ast.VariableExpression(accSym),
					Ast.NumberExpression(math.random(2, 5)),
					false
				)}
			), generatedSpan)
	end

	-- Else branch does different arithmetic
	local elseStmts = {}
	elseStmts[#elseStmts + 1] = Source.fill(
		Ast.AssignmentStatement(
			{Ast.AssignmentVariable(accSym)},
			{Ast.SubExpression(
				Ast.VariableExpression(accSym),
				Ast.NumberExpression(math.random(1, 500)),
				false
			)}
		), generatedSpan)

	-- A loop doing some work
	local loopVar = Ast.LocalSymbol("_i")
	local loopBody = Ast.Block({
		Source.fill(
			Ast.AssignmentStatement(
				{Ast.AssignmentVariable(accSym)},
				{Ast.AddExpression(
					Ast.VariableExpression(accSym),
					Ast.VariableExpression(loopVar),
					false
				)}
			), generatedSpan)
	})
	elseStmts[#elseStmts + 1] = Source.fill(
		Ast.ForStatement(
			loopVar,
			Ast.NumberExpression(1),
			Ast.NumberExpression(math.random(2, 5)),
			Ast.NumberExpression(1),
			loopBody
		), generatedSpan)

	local ifStmt = Source.fill(
		Ast.IfStatement(
			Ast.EqualsExpression(
				Ast.VariableExpression(condSym),
				Ast.NumberExpression(0),
				false
			),
			Ast.Block(ifBodyStmts),
			{},
			Ast.Block(elseStmts)
		), generatedSpan)
	stmts[#stmts + 1] = ifStmt

	-- Return the accumulated value
	stmts[#stmts + 1] = Source.fill(
		Ast.ReturnStatement({Ast.VariableExpression(accSym)}),
		generatedSpan)

	return {paramSym}, Ast.Block(stmts)
end

-- Create an always-false condition using an opaque predicate.
local function makeAlwaysFalseCondition(guardSym, generatedSpan)
	local generators = {
		-- x * x < 0  (always false for real numbers)
		function()
			return Source.fill(
				Ast.LessThanExpression(
					Ast.MulExpression(
						Ast.VariableExpression(guardSym),
						Ast.VariableExpression(guardSym),
						false
					),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,
		-- x - x ~= 0  (always false)
		function()
			return Source.fill(
				Ast.NotEqualsExpression(
					Ast.SubExpression(
						Ast.VariableExpression(guardSym),
						Ast.VariableExpression(guardSym),
						false
					),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,
		-- x + 1 == x  (always false for finite numbers)
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.AddExpression(
						Ast.VariableExpression(guardSym),
						Ast.NumberExpression(1),
						false
					),
					Ast.VariableExpression(guardSym),
					false
				), generatedSpan)
		end,
	}
	return generators[math.random(1, #generators)]()
end

function DummyCode:apply(ast, pipeline)
	local generatedSpan = Source.generated("DummyCode")
	local threshold = self.Threshold
	local funcCount = self.DummyFunctionCount
	local interconnection = self.InterconnectionLevel

	-- Create symbols for all dummy functions
	local funcSymbols = {}
	for i = 1, funcCount do
		funcSymbols[i] = Ast.LocalSymbol("_dummy" .. tostring(i))
	end

	-- Build function declarations
	local funcDecls = {}
	-- Declare all symbols first (forward-declare) so they can reference each other
	local nilExprs = {}
	for _ = 1, funcCount do
		nilExprs[#nilExprs + 1] = Ast.NilExpression()
	end
	funcDecls[#funcDecls + 1] = Source.fill(
		Ast.LocalVariableDeclaration(funcSymbols, nilExprs),
		generatedSpan)

	-- Assign function bodies
	for i = 1, funcCount do
		local params, body = buildDummyFunctionBody(funcSymbols, i, interconnection, generatedSpan)
		local funcExpr = Source.fill(
			Ast.FunctionLiteralExpression(params, body),
			generatedSpan)
		funcDecls[#funcDecls + 1] = Source.fill(
			Ast.AssignmentStatement(
				{Ast.AssignmentVariable(funcSymbols[i])},
				{funcExpr}
			), generatedSpan)
	end

	-- Guard variable for opaque predicates
	local guardSym = Ast.LocalSymbol("_dg")
	local guardValue = math.random(1, 100000)
	local guardDecl = Source.fill(
		Ast.LocalVariableDeclaration(
			{guardSym},
			{Ast.NumberExpression(guardValue)}
		), generatedSpan)

	-- Walk blocks and inject dead calls guarded by always-false conditions
	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.Block then
			local newStatements = {}
			for _, stmt in ipairs(node.statements) do
				newStatements[#newStatements + 1] = stmt
				-- Inject dead call after some statements, but never after a
				-- terminator: `return`/`break` must be the last statement in a
				-- Lua block, so anything following them is a syntax error.
				local isTerminator = stmt.kind == AstKind.ReturnStatement
					or stmt.kind == AstKind.BreakStatement
					or stmt.kind == AstKind.ContinueStatement
				if not isTerminator and math.random() < threshold then
					local targetIdx = math.random(1, funcCount)
					local callExpr = Ast.FunctionCallExpression(
						Ast.VariableExpression(funcSymbols[targetIdx]),
						{Ast.NumberExpression(math.random(1, 10000))}
					)
					local deadSym = Ast.LocalSymbol("_dd" .. tostring(math.random(1, 99999)))
					local deadBody = Ast.Block({
						Source.fill(
							Ast.LocalVariableDeclaration({deadSym}, {callExpr}),
							generatedSpan)
					})
					local falseCondition = makeAlwaysFalseCondition(guardSym, generatedSpan)
					local deadIf = Source.fill(
						Ast.IfStatement(falseCondition, deadBody, {}, nil),
						generatedSpan)
					newStatements[#newStatements + 1] = deadIf
				end
			end
			node.statements = newStatements
		end
	end)

	-- Insert guard + function declarations at the top
	table.insert(ast.body.statements, 1, guardDecl)
	for i = #funcDecls, 1, -1 do
		table.insert(ast.body.statements, 2, funcDecls[i])
	end

	return ast
end

return DummyCode
