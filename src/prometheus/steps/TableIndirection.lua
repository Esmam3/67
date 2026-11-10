-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- TableIndirection.lua
--
-- This Step wraps global library accesses (string, math, table, os, io, etc.)
-- through proxy tables with metatable chains, hiding the real library references
-- behind layers of indirection.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local util = require("prometheus.util")

local AstKind = Ast.AstKind

local TableIndirection = Step:extend()
TableIndirection.Description = "This Step wraps library accesses through proxy tables with metatable chains."
TableIndirection.Name = "Table Indirection"

TableIndirection.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "Probability that a library access is redirected",
		type = "number",
		default = 0.8,
		min = 0,
		max = 1,
	},
	Depth = {
		name = "Depth",
		description = "Number of metatable chain layers per proxy",
		type = "number",
		default = 2,
		min = 1,
		max = 5,
	},
	Libraries = {
		name = "Libraries",
		description = "Which global libraries to proxy",
		type = "table",
		default = {"string", "math", "table", "os", "io", "coroutine", "debug", "bit32"},
	},
}

function TableIndirection:init(_) end

function TableIndirection:apply(ast, pipeline)
	local generatedSpan = Source.generated("TableIndirection")
	local threshold = self.Threshold
	local depth = self.Depth
	local libraries = self.Libraries

	local proxySymbols = {}
	local initStatements = {}
	local decls = {}

	for _, libName in ipairs(libraries) do
		local proxySym = Ast.LocalSymbol("_tip_" .. libName .. "_" .. math.random(1000, 9999))
		proxySymbols[libName] = proxySym
		decls[#decls + 1] = proxySym
	end

	if #decls > 0 then
		initStatements[#initStatements + 1] = Source.fill(
			Ast.LocalVariableDeclaration(decls, {}),
			generatedSpan
		)
	end

	for _, libName in ipairs(libraries) do
		local proxySym = proxySymbols[libName]

		local chainExpr = Ast.GlobalVariableExpression(libName)

		for layer = 1, depth do
			local mtSym = Ast.LocalSymbol("_mt_" .. libName .. "_" .. layer)
			local innerSym = Ast.LocalSymbol("_in_" .. libName .. "_" .. layer)

			local mtDecl = Source.fill(
				Ast.LocalVariableDeclaration(
					{mtSym},
					{
						Ast.TableConstructorExpression({
							{
								kind = AstKind.KeyedTableEntry,
								key = Ast.StringExpression("__index"),
								value = chainExpr,
							},
							{
								kind = AstKind.KeyedTableEntry,
								key = Ast.StringExpression("__metatable"),
								value = Ast.BooleanExpression(false),
							},
						})
					}
				),
				generatedSpan
			)

			local innerDecl = Source.fill(
				Ast.LocalVariableDeclaration(
					{innerSym},
					{
						Ast.FunctionCallExpression(
							Ast.GlobalVariableExpression("setmetatable"),
							{
								Ast.TableConstructorExpression({}),
								Ast.VariableExpression(mtSym),
							}
						)
					}
				),
				generatedSpan
			)

			initStatements[#initStatements + 1] = mtDecl
			initStatements[#initStatements + 1] = innerDecl

			chainExpr = Ast.VariableExpression(innerSym)
		end

		initStatements[#initStatements + 1] = Source.fill(
			Ast.AssignmentStatement(
				{ Ast.AssignmentVariable(proxySym) },
				{ chainExpr }
			),
			generatedSpan
		)
	end

	local libLookup = {}
	for _, name in ipairs(libraries) do
		libLookup[name] = true
	end

	visitast(ast, nil, function(node, data)
		if node.kind == AstKind.IndexExpression and node.base
			and (node.base.kind == AstKind.GlobalVariableExpression or node.base.kind == AstKind.VariableExpression) then

			local baseName = node.base.name
			if baseName and libLookup[baseName] and proxySymbols[baseName] then
				if math.random() <= threshold then
					local newBase = Ast.VariableExpression(proxySymbols[baseName])
					return Source.fill(
						Ast.IndexExpression(newBase, node.index),
						generatedSpan
					)
				end
			end
		end

		if node.kind == AstKind.GlobalVariableExpression and libLookup[node.name] and proxySymbols[node.name] then
			if data.functionData and data.functionData.depth >= 0 then
				if math.random() <= threshold then
					return Source.fill(
						Ast.VariableExpression(proxySymbols[node.name]),
						generatedSpan
					)
				end
			end
		end
	end)

	-- The proxy locals (_tip_*) are referenced throughout the program, so they
	-- must live at the top-level scope. Wrapping them in a `do ... end` block
	-- would scope them to that block and make them invisible elsewhere
	-- ("Local binding is not accessible"). Insert the init statements directly.
	for i = #initStatements, 1, -1 do
		table.insert(ast.body.statements, 1, initStatements[i])
	end

	return ast
end

return TableIndirection
