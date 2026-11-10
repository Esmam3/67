-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- DynamicCodeGeneration.lua
--
-- This Step wraps function bodies in loadstring/load calls with XOR-encrypted
-- payloads, forcing reverse engineers to trace runtime decryption to recover
-- the original logic.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local Unparser = require("prometheus.unparser")

local AstKind = Ast.AstKind

local DynamicCodeGeneration = Step:extend()
DynamicCodeGeneration.Description = "This Step wraps function bodies in loadstring-based runtime decryption to hide logic."
DynamicCodeGeneration.Name = "Dynamic Code Generation"

DynamicCodeGeneration.SettingsDescriptor = {
	Threshold = {
		name = "Threshold",
		description = "Probability that a function body is wrapped",
		type = "number",
		default = 0.5,
		min = 0,
		max = 1,
	},
	MaxDepth = {
		name = "MaxDepth",
		description = "Maximum function nesting depth to apply to (0 = top-level only)",
		type = "number",
		default = 3,
		min = 0,
		max = 10,
	},
}

function DynamicCodeGeneration:init(_) end

local function xorEncrypt(str, key)
	local out = {}
	local keyLen = #key
	for i = 1, #str do
		local b = string.byte(str, i)
		local k = string.byte(key, ((i - 1) % keyLen) + 1)
		out[i] = string.char(b ~ k)
	end
	return table.concat(out)
end

local function generateKey(length)
	local chars = {}
	for i = 1, length do
		chars[i] = string.char(math.random(1, 255))
	end
	return table.concat(chars)
end

local function escapeString(s)
	local out = {}
	for i = 1, #s do
		out[i] = "\\" .. string.byte(s, i)
	end
	return table.concat(out)
end

function DynamicCodeGeneration:apply(ast, pipeline)
	local generatedSpan = Source.generated("DynamicCodeGeneration")
	local threshold = self.Threshold
	local maxDepth = self.MaxDepth

	local luaVersion = pipeline:getLuaVersion()
	local unparser = Unparser:new({ LuaVersion = luaVersion, PrettyPrint = false })
	local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })

	local decryptSym = Ast.LocalSymbol("_dcg_dec")
	local loadSym = Ast.LocalSymbol("_dcg_load")

	local keyLength = math.random(8, 24)
	local masterKey = generateKey(keyLength)
	local escapedKey = escapeString(masterKey)

	local bootstrapCode = string.format([[
do
	local _k = "%s"
	local _byte = string.byte
	local _char = string.char
	local _len = #_k
	_DCG_DECRYPT = function(_s)
		local _o = {}
		for _i = 1, #_s do
			_o[_i] = _char(_byte(_s, _i) ~ _byte(_k, ((_i - 1) %% _len) + 1))
		end
		return table.concat(_o)
	end
	_DCG_LOAD = load or loadstring
end]], escapedKey)

	local bootstrapAst = parser:parse(bootstrapCode, Source.internal("DynamicCodeGeneration.Bootstrap", bootstrapCode))
	local doStat = bootstrapAst.body.statements[1]

	visitast(bootstrapAst, nil, function(node, data)
		if node.kind == AstKind.FunctionDeclaration then
			if node.name == "_DCG_DECRYPT" then
				node.symbol = decryptSym
				node.name = nil
			end
		end
		if node.kind == AstKind.AssignmentVariable or node.kind == AstKind.VariableExpression
			or node.kind == AstKind.AssignmentGlobalVariable or node.kind == AstKind.GlobalVariableExpression then
			if node.name == "_DCG_DECRYPT" then
				if node.kind == AstKind.AssignmentVariable or node.kind == AstKind.AssignmentGlobalVariable then
					return Source.inherit(Ast.AssignmentVariable(decryptSym), node)
				end
				return Source.inherit(Ast.VariableExpression(decryptSym), node)
			end
			if node.name == "_DCG_LOAD" then
				if node.kind == AstKind.AssignmentVariable or node.kind == AstKind.AssignmentGlobalVariable then
					return Source.inherit(Ast.AssignmentVariable(loadSym), node)
				end
				return Source.inherit(Ast.VariableExpression(loadSym), node)
			end
		end
	end)

	Source.fill(doStat, generatedSpan)

	local wrapped = false

	visitast(ast, function(node, data)
		if node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration
			or node.kind == AstKind.FunctionLiteralExpression then
			if data.functionData.depth > maxDepth then
				return node, true
			end
		end
	end, function(node, data)
		if node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.LocalFunctionDeclaration
			or node.kind == AstKind.FunctionLiteralExpression then

			if math.random() > threshold then return end
			if not node.body or not node.body.statements or #node.body.statements == 0 then return end

			local hasReturn = false
			for _, stmt in ipairs(node.body.statements) do
				if stmt.kind == AstKind.ReturnStatement then
					hasReturn = true
					break
				end
			end

			local bodyAst = {
				kind = AstKind.TopNode,
				body = node.body,
				globalScope = ast.globalScope,
			}

			local ok, bodyCode = pcall(function() return unparser:unparse(bodyAst) end)
			if not ok or not bodyCode or #bodyCode == 0 then return end

			local encrypted = xorEncrypt(bodyCode, masterKey)
			local escapedPayload = escapeString(encrypted)

			local argNames = {}
			if node.args then
				for i, arg in ipairs(node.args) do
					argNames[i] = arg.name or ("_a" .. i)
				end
			end
			local isVararg = node.hasVararg

			local callArgs = {}
			for _, name in ipairs(argNames) do
				callArgs[#callArgs + 1] = Ast.GlobalVariableExpression(name)
			end
			if isVararg then
				callArgs[#callArgs + 1] = Ast.VarargExpression()
			end

			local loadCall = Ast.FunctionCallExpression(
				Ast.VariableExpression(loadSym),
				{
					Ast.FunctionCallExpression(
						Ast.VariableExpression(decryptSym),
						{ Ast.StringExpression(encrypted) }
					)
				}
			)

			local executeCall = Ast.FunctionCallExpression(loadCall, callArgs)

			local newBody
			if hasReturn then
				newBody = Ast.Block({
					Source.fill(Ast.ReturnStatement({ executeCall }), generatedSpan)
				})
			else
				newBody = Ast.Block({
					Source.fill(Ast.FunctionCallStatement(loadCall, callArgs), generatedSpan)
				})
			end

			node.body = newBody
			Source.fill(node.body, generatedSpan)
			wrapped = true
		end
	end)

	if wrapped then
		table.insert(ast.body.statements, 1, doStat)
		table.insert(ast.body.statements, 1, Source.fill(
			Ast.LocalVariableDeclaration({ decryptSym, loadSym }, {}),
			generatedSpan
		))
	end

	return ast
end

return DynamicCodeGeneration
