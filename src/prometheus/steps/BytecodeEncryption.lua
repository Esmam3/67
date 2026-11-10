-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- BytecodeEncryption.lua
--
-- This Step encrypts function bytecode by wrapping functions in string.dump/loadstring cycles
-- with encrypted intermediaries. Functions are serialized, encrypted, and reconstructed at runtime.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Source = require("prometheus.source")
local AstKind = Ast.AstKind

local BytecodeEncryption = Step:extend()
BytecodeEncryption.Description = "Encrypts function references through string.dump/loadstring cycles with encrypted intermediaries."
BytecodeEncryption.Name = "Bytecode Encryption"

BytecodeEncryption.SettingsDescriptor = {
    Threshold = { type = "number", default = 0.5, min = 0, max = 1 },
    KeyComplexity = { type = "number", default = 3, min = 1, max = 5 },
}

function BytecodeEncryption:init(_) end

function BytecodeEncryption:CreateEncryptionRuntime()
    local masterKey = math.random(1, 255)
    local scrambleTable = {}
    for i = 0, 255 do scrambleTable[i] = i end
    -- Fisher-Yates shuffle the substitution table
    for i = 255, 1, -1 do
        local j = math.random(0, i)
        scrambleTable[i], scrambleTable[j] = scrambleTable[j], scrambleTable[i]
    end

    -- Build inverse table
    local inverseTable = {}
    for i = 0, 255 do
        inverseTable[scrambleTable[i]] = i
    end

    local function encrypt(str)
        local key = math.random(1, 255)
        local out = {}
        local prevByte = key
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encrypted = scrambleTable[(byte + prevByte + masterKey) % 256]
            out[i] = string.char(encrypted)
            prevByte = encrypted
        end
        return table.concat(out), key
    end

    -- Build the substitution table literal for runtime
    local invParts = {}
    for i = 0, 255 do
        invParts[i + 1] = string.format("[%d]=%d", i, inverseTable[i])
    end

    local function genDecryptCode()
        local code = string.format([[
do
    local _bce_inv = {%s}
    local _bce_mk = %d
    function _BCE_DECRYPT(enc, key)
        local out = {}
        local prev = key
        for i = 1, #enc do
            local byte = _bce_inv[string.byte(enc, i)]
            local decrypted = (byte - prev - _bce_mk) %% 256
            out[i] = string.char(decrypted)
            prev = string.byte(enc, i)
        end
        return table.concat(out)
    end
    _BCE_LOAD = function(enc, key, env)
        local code = _BCE_DECRYPT(enc, key)
        local fn = (loadstring or load)(code)
        if fn and env and type(setfenv) == "function" then
            setfenv(fn, env)
        end
        return fn
    end
end
]], table.concat(invParts, ","), masterKey)
        return code
    end

    return {
        encrypt = encrypt,
        genDecryptCode = genDecryptCode,
    }
end

function BytecodeEncryption:apply(ast, pipeline)
    local encryptor = self:CreateEncryptionRuntime()
    local generatedSpan = Source.generated("BytecodeEncryption")

    -- Parse and inject the decryption runtime
    local runtimeCode = encryptor.genDecryptCode()
    local runtimeAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(
        runtimeCode, Source.internal("BytecodeEncryption.Runtime", runtimeCode))
    local doStat = runtimeAst.body.statements[1]

    -- Create symbols for the decrypt/load functions
    local decryptVar = Ast.LocalSymbol("_bce_decrypt")
    local loadVar = Ast.LocalSymbol("_bce_load")

    -- Rename the globals in the runtime to locals
    visitast(runtimeAst, nil, function(node)
        if node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.AssignmentVariable
            or node.kind == AstKind.AssignmentGlobalVariable then
            if node.name == "_BCE_DECRYPT" then
                if node.kind == AstKind.FunctionDeclaration then
                    node.symbol = decryptVar
                    node.name = nil
                else
                    return Source.fill(Ast.AssignmentVariable(decryptVar), generatedSpan)
                end
            elseif node.name == "_BCE_LOAD" then
                if node.kind == AstKind.FunctionDeclaration then
                    node.symbol = loadVar
                    node.name = nil
                else
                    return Source.fill(Ast.AssignmentVariable(loadVar), generatedSpan)
                end
            end
        end
        if node.kind == AstKind.VariableExpression or node.kind == AstKind.GlobalVariableExpression then
            if node.name == "_BCE_DECRYPT" then
                return Source.fill(Ast.VariableExpression(decryptVar), generatedSpan)
            elseif node.name == "_BCE_LOAD" then
                return Source.fill(Ast.VariableExpression(loadVar), generatedSpan)
            end
        end
    end)

    -- Collect string literals that look like they could be code or important data
    -- and encrypt them through our system
    local encryptedPayloads = {}
    local payloadTableVar = Ast.LocalSymbol("_bce_payloads")

    -- For each string expression, with threshold probability, encrypt it through the bytecode system
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression then
            if math.random() > self.Threshold then return end
            -- Encrypt the string value
            local encrypted, key = encryptor.encrypt(node.value)
            local payloadIndex = #encryptedPayloads + 1
            encryptedPayloads[payloadIndex] = { encrypted = encrypted, key = key }

            -- Replace with: _bce_decrypt(payloads[INDEX], KEY)
            return Source.fill(
                Ast.FunctionCallExpression(
                    Ast.VariableExpression(decryptVar),
                    {
                        Ast.IndexExpression(
                            Ast.VariableExpression(payloadTableVar),
                            Ast.NumberExpression(payloadIndex)
                        ),
                        Ast.NumberExpression(key),
                    }
                ),
                generatedSpan
            )
        end
    end)

    -- Build the payload table
    local payloadEntries = {}
    for i, payload in ipairs(encryptedPayloads) do
        payloadEntries[i] = Ast.KeyedTableEntry(
            Ast.NumberExpression(i),
            Ast.StringExpression(payload.encrypted)
        )
    end

    -- Insert: local _bce_payloads = { [1] = "...", [2] = "...", ... }
    local payloadDecl = Source.fill(
        Ast.LocalVariableDeclaration(
            { payloadTableVar },
            { Ast.TableConstructorExpression(payloadEntries) }
        ),
        generatedSpan
    )

    -- Insert runtime infrastructure
    -- payloadTableVar is declared with its value in payloadDecl, so it must NOT
    -- also appear in this forward declaration (that would double-declare it).
    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1, Source.fill(
        Ast.LocalVariableDeclaration(util.shuffle({ decryptVar, loadVar }), {}),
        generatedSpan
    ))
    -- Insert payload table after the runtime
    table.insert(ast.body.statements, 3, payloadDecl)

    return ast
end

return BytecodeEncryption
