-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- OpcodeSubstitution.lua
--
-- This Step replaces standard binary and unary operations with calls to
-- locally-defined wrapper functions, hiding the true operator from static
-- analysis and making pattern-matching deobfuscation much harder.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")

local AstKind = Ast.AstKind

local OpcodeSubstitution = Step:extend()
OpcodeSubstitution.Description = "This Step replaces arithmetic and comparison operators with wrapper function calls."
OpcodeSubstitution.Name = "Opcode Substitution"

OpcodeSubstitution.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "The probability that a given operation will be substituted",
		type = "number",
		default = 0.6,
		min = 0,
		max = 1,
	},
	MaxExpansion = {
		name = "MaxExpansion",
		description = "Maximum number of indirection layers per wrapper",
		type = "number",
		default = 3,
		min = 1,
		max = 5,
	},
}

function OpcodeSubstitution:init(_) end

local binaryOps = {
	[AstKind.AddExpression]       = "+",
	[AstKind.SubExpression]       = "-",
	[AstKind.MulExpression]       = "*",
	[AstKind.DivExpression]       = "/",
	[AstKind.ModExpression]       = "%%",
	[AstKind.PowExpression]       = "^",
	[AstKind.StrCatExpression]    = "..",
	[AstKind.LessThanExpression]  = "<",
	[AstKind.GreaterThanExpression] = ">",
	[AstKind.LessThanOrEqualsExpression] = "<=",
	[AstKind.GreaterThanOrEqualsExpression] = ">=",
	[AstKind.EqualsExpression]    = "==",
	[AstKind.NotEqualsExpression] = "~=",
}

local unaryOps = {
	[AstKind.NegateExpression] = "neg",
	[AstKind.NotExpression]    = "not",
	[AstKind.LenExpression]    = "len",
}

-- Build wrapper function bodies. Each expansion level wraps the previous one
-- with a trampoline-style indirection.
local function buildBinaryWrapper(op, expansionLevel)
	local paramA = Ast.LocalSymbol("a")
	local paramB = Ast.LocalSymbol("b")

	local function makeOp(a, b)
		if op == "+" then return Ast.AddExpression(a, b, false)
		elseif op == "-" then return Ast.SubExpression(a, b, false)
		elseif op == "*" then return Ast.MulExpression(a, b, false)
		elseif op == "/" then return Ast.DivExpression(a, b, false)
		elseif op == "%%" then return Ast.ModExpression(a, b, false)
		elseif op == "^" then return Ast.PowExpression(a, b, false)
		elseif op == ".." then return Ast.StrCatExpression(a, b, false)
		elseif op == "<" then return Ast.LessThanExpression(a, b, false)
		elseif op == ">" then return Ast.GreaterThanExpression(a, b, false)
		elseif op == "<=" then return Ast.LessThanOrEqualsExpression(a, b, false)
		elseif op == ">=" then return Ast.GreaterThanOrEqualsExpression(a, b, false)
		elseif op == "==" then return Ast.EqualsExpression(a, b, false)
		elseif op == "~=" then return Ast.NotEqualsExpression(a, b, false)
		end
	end

	if expansionLevel <= 1 then
		local body = Ast.Block({
			Ast.ReturnStatement({makeOp(Ast.VariableExpression(paramA), Ast.VariableExpression(paramB))})
		})
		return Ast.FunctionLiteralExpression({paramA, paramB}, body)
	end

	-- Build inner wrapper first, then wrap it in another layer
	local innerSym = Ast.LocalSymbol("_inner")
	local innerFunc = buildBinaryWrapper(op, expansionLevel - 1)

	local body = Ast.Block({
		Ast.LocalVariableDeclaration({innerSym}, {innerFunc}),
		Ast.ReturnStatement({
			Ast.FunctionCallExpression(Ast.VariableExpression(innerSym), {
				Ast.VariableExpression(paramA),
				Ast.VariableExpression(paramB),
			})
		})
	})
	return Ast.FunctionLiteralExpression({paramA, paramB}, body)
end

local function buildUnaryWrapper(op, expansionLevel)
	local paramA = Ast.LocalSymbol("a")

	local function makeOp(a)
		if op == "neg" then return Ast.NegateExpression(a)
		elseif op == "not" then return Ast.NotExpression(a)
		elseif op == "len" then return Ast.LenExpression(a)
		end
	end

	if expansionLevel <= 1 then
		local body = Ast.Block({
			Ast.ReturnStatement({makeOp(Ast.VariableExpression(paramA))})
		})
		return Ast.FunctionLiteralExpression({paramA}, body)
	end

	local innerSym = Ast.LocalSymbol("_inner")
	local innerFunc = buildUnaryWrapper(op, expansionLevel - 1)

	local body = Ast.Block({
		Ast.LocalVariableDeclaration({innerSym}, {innerFunc}),
		Ast.ReturnStatement({
			Ast.FunctionCallExpression(Ast.VariableExpression(innerSym), {
				Ast.VariableExpression(paramA),
			})
		})
	})
	return Ast.FunctionLiteralExpression({paramA}, body)
end

function OpcodeSubstitution:apply(ast, pipeline)
	local generatedSpan = Source.generated("OpcodeSubstitution")
	local threshold = self.Threshold
	local maxExpansion = self.MaxExpansion

	-- Track which ops we've created wrappers for
	local wrapperSymbols = {}
	local wrapperDecls = {}

	local function getOrCreateBinaryWrapper(kind)
		local op = binaryOps[kind]
		if not op then return nil end
		if wrapperSymbols[kind] then return wrapperSymbols[kind] end

		local sym = Ast.LocalSymbol("_op" .. tostring(#wrapperDecls + 1))
		local expansion = math.random(1, maxExpansion)
		local funcExpr = buildBinaryWrapper(op, expansion)
		Source.fill(funcExpr, generatedSpan)

		local decl = Source.fill(
			Ast.LocalVariableDeclaration({sym}, {funcExpr}),
			generatedSpan)

		wrapperSymbols[kind] = sym
		wrapperDecls[#wrapperDecls + 1] = decl
		return sym
	end

	local function getOrCreateUnaryWrapper(kind)
		local op = unaryOps[kind]
		if not op then return nil end
		if wrapperSymbols[kind] then return wrapperSymbols[kind] end

		local sym = Ast.LocalSymbol("_op" .. tostring(#wrapperDecls + 1))
		local expansion = math.random(1, maxExpansion)
		local funcExpr = buildUnaryWrapper(op, expansion)
		Source.fill(funcExpr, generatedSpan)

		local decl = Source.fill(
			Ast.LocalVariableDeclaration({sym}, {funcExpr}),
			generatedSpan)

		wrapperSymbols[kind] = sym
		wrapperDecls[#wrapperDecls + 1] = decl
		return sym
	end

	-- Replace binary/unary expressions with wrapper calls
	visitast(ast, nil, function(node, data)
		if binaryOps[node.kind] then
			if math.random() <= threshold then
				local sym = getOrCreateBinaryWrapper(node.kind)
				if sym then
					return Source.fill(
						Ast.FunctionCallExpression(
							Ast.VariableExpression(sym),
							{node.lhs, node.rhs}
						), generatedSpan)
				end
			end
		elseif unaryOps[node.kind] then
			if math.random() <= threshold then
				local sym = getOrCreateUnaryWrapper(node.kind)
				if sym then
					return Source.fill(
						Ast.FunctionCallExpression(
							Ast.VariableExpression(sym),
							{node.rhs}
						), generatedSpan)
				end
			end
		end
	end)

	-- Insert all wrapper declarations at the top of the program
	for i = #wrapperDecls, 1, -1 do
		table.insert(ast.body.statements, 1, wrapperDecls[i])
	end

	return ast
end

return OpcodeSubstitution
