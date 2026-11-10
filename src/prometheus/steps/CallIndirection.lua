-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- CallIndirection.lua
--
-- Redirects function calls through an encrypted dispatch table.
-- Global function references (print, tostring, etc.) are collected,
-- stored in a shuffled table with XOR-encrypted keys, and all call
-- sites are replaced with lookups through that table.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local AstKind = Ast.AstKind

local CallIndirection = Step:extend()
CallIndirection.Name = "Call Indirection"
CallIndirection.Description =
    "Redirects global function calls through an encrypted dispatch table."

CallIndirection.SettingsDescriptor = {
    Threshold = {
        type = "number", default = 1, min = 0, max = 1,
        description = "Fraction of eligible call sites that will be redirected.",
    },
}

function CallIndirection:init(_) end

-- Arithmetic XOR for Lua 5.1
local function bxor32(a, b)
    local result = 0
    local bit = 1
    for _ = 1, 32 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit ~= b_bit then result = result + bit end
        a = (a - a_bit) / 2
        b = (b - b_bit) / 2
        bit = bit * 2
    end
    return result
end

function CallIndirection:apply(ast, _)
    local threshold = self.Threshold

    -- Phase 1: Collect all global function names used in FunctionCallExpression
    local globalNames = {} -- set: name -> true
    local callSites = {}   -- list of {node, name}

    visitast(ast, nil, function(node, _)
        if node.kind == AstKind.FunctionCallExpression then
            local base = node.base
            if base and base.kind == AstKind.GlobalVariableExpression then
                local name = base.name
                if name and type(name) == "string" then
                    if threshold < 1 and math.random() > threshold then return end
                    globalNames[name] = true
                    callSites[#callSites + 1] = { node = node, name = name }
                end
            end
        end
    end)

    if #callSites == 0 then return ast end

    -- Phase 2: Build the encrypted dispatch table
    local xorKey = math.random(1, 2^30)

    -- Assign each global name an encrypted slot ID
    local nameToSlot = {} -- name -> { encryptedKey, rawKey }
    local slots = {}      -- ordered list of { name, rawKey, encryptedKey }
    local nextKey = math.random(1000, 9999)

    for name, _ in pairs(globalNames) do
        local rawKey = nextKey
        nextKey = nextKey + math.random(1, 100)
        local encKey = bxor32(rawKey, xorKey)
        nameToSlot[name] = { encrypted = encKey, raw = rawKey }
        slots[#slots + 1] = { name = name, raw = rawKey, encrypted = encKey }
    end

    -- Shuffle the slots for the table constructor
    for i = #slots, 2, -1 do
        local j = math.random(1, i)
        slots[i], slots[j] = slots[j], slots[i]
    end

    -- Build table constructor entries as source
    local entryParts = {}
    for _, slot in ipairs(slots) do
        entryParts[#entryParts + 1] = string.format("[%d] = %s", slot.raw, slot.name)
    end

    -- Runtime XOR function and lookup
    local runtimeCode = string.format([[
do
    local _tbl = {%s}
    local _xk = %d
    function CALL_DISPATCH(ek)
        local r, b, a2, b2 = 0, 1, ek, _xk
        for _ = 1, 32 do
            a2, b2 = a2 %% 2, b2 %% 2
            -- Lua 5.1 modular XOR
            if a2 ~= b2 then r = r + b end
            ek = (ek - a2) / 2
            a2 = ek
            _xk = (_xk - b2) / 2
            b2 = _xk
            b = b * 2
        end
        _xk = %d
        return _tbl[r]
    end
end]], table.concat(entryParts, ", "), xorKey, xorKey)

    local generatedSpan = Source.generated("CallIndirection")
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
        :parse(runtimeCode, Source.internal("CallIndirection.Dispatch", runtimeCode))
    local doStat = newAst.body.statements[1]

    local dispatchVar = Ast.LocalSymbol("_ci_dispatch")

    -- Replace the global function declaration placeholder
    visitast(newAst, nil, function(node, _)
        if node.kind == AstKind.FunctionDeclaration and node.name == "CALL_DISPATCH" then
            node.symbol = dispatchVar
            node.name = nil
        end
    end)

    -- Phase 3: Replace call sites
    -- Each call: originalFunc(args...) → _ci_dispatch(encKey)(args...)
    visitast(ast, nil, function(node, _)
        if node.kind == AstKind.FunctionCallExpression then
            local base = node.base
            if base and base.kind == AstKind.GlobalVariableExpression then
                local name = base.name
                local slot = nameToSlot[name]
                if slot then
                    -- Replace the base with a dispatch call
                    node.base = Source.inherit(
                        Ast.FunctionCallExpression(
                            Ast.VariableExpression(dispatchVar),
                            { Ast.NumberExpression(slot.encrypted) }
                        ), base)
                end
            end
        end
    end)

    -- Inject dispatch table at the top
    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Source.fill(Ast.LocalVariableDeclaration({ dispatchVar }, {}), generatedSpan))

    return ast
end

return CallIndirection
