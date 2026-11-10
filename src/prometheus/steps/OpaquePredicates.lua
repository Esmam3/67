-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- OpaquePredicates.lua
--
-- This Step inserts always-true conditional guards around statements,
-- making static analysis significantly harder.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local OpaquePredicates = Step:extend()
OpaquePredicates.Description = "This Step wraps statements in opaque always-true conditionals to hinder static analysis."
OpaquePredicates.Name = "Opaque Predicates"

OpaquePredicates.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that a given statement will be wrapped",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	MaxDepth = {
		name = "MaxDepth",
		description = "Maximum nesting depth of opaque wrappers",
		type = "number",
		default = 2,
		min = 1,
		max = 5,
	},
}

function OpaquePredicates:init(_) end

-- Statements that are structural and should never be wrapped.
-- LocalVariableDeclaration must be skipped: wrapping it in an if-block would
-- re-scope the declared locals into that block, making them invisible to
-- subsequent sibling statements ("Local binding is not accessible").
local skipKinds = {
	[AstKind.ReturnStatement] = true,
	[AstKind.BreakStatement] = true,
	[AstKind.ContinueStatement] = true,
	[AstKind.LocalVariableDeclaration] = true,
	[AstKind.IfStatement] = true,
	[AstKind.WhileStatement] = true,
	[AstKind.RepeatStatement] = true,
	[AstKind.ForStatement] = true,
	[AstKind.ForInStatement] = true,
	[AstKind.DoStatement] = true,
	[AstKind.FunctionDeclaration] = true,
	[AstKind.LocalFunctionDeclaration] = true,
	[AstKind.NopStatement] = true,
}

-- Build an always-true condition that references `varExpr`.
-- Each generator returns an expression node that always evaluates to truthy.
local function makeAlwaysTrueCondition(varExpr, generatedSpan)
	local generators = {
		-- x * x >= 0  (always true for any finite number)
		function()
			return Source.fill(
				Ast.GreaterThanOrEqualsExpression(
					Ast.MulExpression(varExpr, varExpr, false),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,

		-- (x * x + x) % 2 == 0  (n^2 + n is always even)
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.ModExpression(
						Ast.AddExpression(
							Ast.MulExpression(varExpr, varExpr, false),
							varExpr,
							false
						),
						Ast.NumberExpression(2),
						false
					),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,

		-- (x * (x + 1)) % 2 == 0  (product of consecutive integers is even)
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.ModExpression(
						Ast.MulExpression(
							varExpr,
							Ast.AddExpression(varExpr, Ast.NumberExpression(1), false),
							false
						),
						Ast.NumberExpression(2),
						false
					),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,

		-- (x * (x + 1) * (x + 2)) % 6 == 0  (product of 3 consecutive ints divisible by 6)
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.ModExpression(
						Ast.MulExpression(
							Ast.MulExpression(
								varExpr,
								Ast.AddExpression(varExpr, Ast.NumberExpression(1), false),
								false
							),
							Ast.AddExpression(varExpr, Ast.NumberExpression(2), false),
							false
						),
						Ast.NumberExpression(6),
						false
					),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,

		-- x - x == 0  (always true)
		function()
			return Source.fill(
				Ast.EqualsExpression(
					Ast.SubExpression(varExpr, varExpr, false),
					Ast.NumberExpression(0),
					false
				), generatedSpan)
		end,
	}

	return generators[math.random(1, #generators)]()
end

-- Generate a dead-code else body with harmless but confusing statements.
local function makeDeadElseBody(generatedSpan)
	local stmts = {}
	local patterns = math.random(1, 3)
	for _ = 1, patterns do
		local pick = math.random(1, 3)
		if pick == 1 then
			-- Dead local declaration: local _dN = <random number>
			local sym = Ast.LocalSymbol("_d" .. tostring(math.random(1, 99999)))
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration(
					{sym},
					{Ast.NumberExpression(math.random(-9999, 9999))}
				), generatedSpan)
		elseif pick == 2 then
			-- Dead assignment to itself via arithmetic
			local sym = Ast.LocalSymbol("_e" .. tostring(math.random(1, 99999)))
			local expr = Ast.AddExpression(
				Ast.NumberExpression(math.random(1, 9999)),
				Ast.NumberExpression(math.random(1, 9999)),
				false
			)
			stmts[#stmts + 1] = Source.fill(
				Ast.LocalVariableDeclaration({sym}, {expr}), generatedSpan)
		else
			-- Dead do-end block with a local
			local sym = Ast.LocalSymbol("_f" .. tostring(math.random(1, 99999)))
			local inner = {
				Source.fill(
					Ast.LocalVariableDeclaration(
						{sym},
						{Ast.StringExpression("_" .. tostring(math.random(1, 99999)))}
					), generatedSpan),
			}
			stmts[#stmts + 1] = Source.fill(
				Ast.DoStatement(Ast.Block(inner)), generatedSpan)
		end
	end
	return Ast.Block(stmts)
end

function OpaquePredicates:apply(ast, pipeline)
	local generatedSpan = Source.generated("OpaquePredicates")
	local threshold = self.Threshold
	local maxDepth = self.MaxDepth

	-- Create a local variable to use in predicates.
	-- Initialized to a random integer so all arithmetic predicates hold.
	local guardSym = Ast.LocalSymbol("_opq")
	local guardValue = math.random(1, 100000)
	local guardDecl = Source.fill(
		Ast.LocalVariableDeclaration(
			{guardSym},
			{Ast.NumberExpression(guardValue)}
		), generatedSpan)

	-- Walk every block and wrap eligible statements.
	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.Block then
			local newStatements = {}
			for _, stmt in ipairs(node.statements) do
				if not skipKinds[stmt.kind] and math.random() < threshold then
					local wrapped = stmt
					local depth = math.random(1, maxDepth)
					for _ = 1, depth do
						local condition = makeAlwaysTrueCondition(
							Ast.VariableExpression(guardSym), generatedSpan)
						local elseBody = makeDeadElseBody(generatedSpan)
						local trueBlock = Ast.Block({wrapped})
						wrapped = Source.fill(
							Ast.IfStatement(condition, trueBlock, {}, elseBody),
							generatedSpan)
					end
					newStatements[#newStatements + 1] = wrapped
				else
					newStatements[#newStatements + 1] = stmt
				end
			end
			node.statements = newStatements
		end
	end)

	-- Insert guard variable declaration at the top.
	table.insert(ast.body.statements, 1, guardDecl)

	return ast
end

return OpaquePredicates
