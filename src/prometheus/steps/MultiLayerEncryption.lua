-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- MultiLayerEncryption.lua
--
-- Multi-layer string encryption: each string is encrypted through N layers,
-- each using a different algorithm (XOR-rolling, Caesar, byte-reversal+XOR,
-- substitution table, CBC-XOR). The runtime decryptor unwraps in reverse.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Source = require("prometheus.source")
local AstKind = Ast.AstKind

local MultiLayerEncryption = Step:extend()
MultiLayerEncryption.Name = "Multi Layer Encryption"
MultiLayerEncryption.Description =
    "Applies multiple layers of encryption to strings with different algorithms per layer."

MultiLayerEncryption.SettingsDescriptor = {
    Layers = {
        type = "number", default = 3, min = 1, max = 5,
        description = "Number of encryption passes applied to each string.",
    },
    Threshold = {
        type = "number", default = 1, min = 0, max = 1,
        description = "Fraction of strings that will be encrypted.",
    },
}

function MultiLayerEncryption:init(_) end

-- ---------------------------------------------------------------------------
-- Encryption primitives (obfuscation-time, pure Lua 5.1 compatible)
-- ---------------------------------------------------------------------------

-- Bitwise XOR via arithmetic (Lua 5.1 has no bit ops)
local function bxor8(a, b)
    local result = 0
    local bit = 1
    for _ = 1, 8 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit ~= b_bit then result = result + bit end
        a = (a - a_bit) / 2
        b = (b - b_bit) / 2
        bit = bit * 2
    end
    return result
end

-- Layer 1: XOR with rolling key derived from seed
local function encrypt_xor_rolling(bytes, seed)
    local key = seed % 256
    local out = {}
    for i = 1, #bytes do
        out[i] = bxor8(bytes[i], key)
        key = (key * 7 + 13 + bytes[i]) % 256
    end
    return out
end

-- Layer 2: Caesar cipher with position+seed-derived shift
local function encrypt_caesar(bytes, seed)
    local out = {}
    for i = 1, #bytes do
        local shift = (seed + i * 31 + i * i * 7) % 256
        out[i] = (bytes[i] + shift) % 256
    end
    return out
end

-- Layer 3: Byte reversal then XOR with constant
local function encrypt_reverse_xor(bytes, seed)
    local constant = seed % 256
    local out = {}
    local n = #bytes
    for i = 1, n do
        out[i] = bxor8(bytes[n - i + 1], constant)
    end
    return out
end

-- Layer 4: Substitution table (deterministic permutation from seed)
local function make_sbox(seed)
    local tbl = {}
    for i = 0, 255 do tbl[i] = i end
    local s = seed
    for i = 255, 1, -1 do
        s = (s * 1103515245 + 12345) % 2147483648
        local j = s % (i + 1)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

local function encrypt_substitution(bytes, seed)
    local sbox = make_sbox(seed)
    local out = {}
    for i = 1, #bytes do
        out[i] = sbox[bytes[i]]
    end
    return out
end

-- Layer 5: CBC-style XOR with previous ciphertext byte
local function encrypt_cbc(bytes, seed)
    local iv = seed % 256
    local out = {}
    local prev = iv
    for i = 1, #bytes do
        out[i] = bxor8(bytes[i], prev)
        prev = out[i]
    end
    return out
end

local LAYER_FUNCS = {
    encrypt_xor_rolling,
    encrypt_caesar,
    encrypt_reverse_xor,
    encrypt_substitution,
    encrypt_cbc,
}
local NUM_LAYER_TYPES = #LAYER_FUNCS

-- ---------------------------------------------------------------------------
-- Apply: encrypt every string, inject runtime decryptor
-- ---------------------------------------------------------------------------

function MultiLayerEncryption:apply(ast, _)
    local numLayers = self.Layers
    local threshold = self.Threshold

    -- Per-string metadata: { encryptedStr, { {layerType, seed}, ... } }
    local encryptedData = {} -- list of {str=..., layers={{type,seed},...}}

    -- Choose layer types for this run (reproducible via math.random seeded in pipeline)
    local function chooseLayers()
        local layers = {}
        local available = {}
        for i = 1, NUM_LAYER_TYPES do available[i] = i end
        for i = 1, numLayers do
            local idx = math.random(1, #available)
            layers[i] = { type = available[idx], seed = math.random(0, 2147483647) }
            -- Allow reuse: don't remove, just shuffle
        end
        return layers
    end

    -- Encrypt a string through all layers
    local function encryptString(str)
        local layers = chooseLayers()
        local bytes = {}
        for i = 1, #str do bytes[i] = string.byte(str, i) end
        for _, layer in ipairs(layers) do
            bytes = LAYER_FUNCS[layer.type](bytes, layer.seed)
        end
        local chars = {}
        for i = 1, #bytes do chars[i] = string.char(bytes[i]) end
        local idx = #encryptedData + 1
        encryptedData[idx] = { str = table.concat(chars), layers = layers }
        return idx
    end

    -- First pass: encrypt all strings and record metadata
    visitast(ast, nil, function(node, _)
        if node.kind == AstKind.StringExpression then
            if threshold < 1 and math.random() > threshold then return end
            local idx = encryptString(node.value)
            -- Replace with placeholder; will be filled after code injection
            node._mle_index = idx
        end
    end)

    if #encryptedData == 0 then return ast end

    -- Build the metadata table as Lua source
    local metaParts = {}
    for i, entry in ipairs(encryptedData) do
        local layerParts = {}
        for _, l in ipairs(entry.layers) do
            layerParts[#layerParts + 1] = string.format("{%d,%d}", l.type, l.seed)
        end
        -- Escape the encrypted string for embedding
        local escaped = {}
        for j = 1, #entry.str do
            escaped[j] = "\\" .. string.byte(entry.str, j)
        end
        metaParts[#metaParts + 1] = string.format(
            '{"%s",{%s}}', table.concat(escaped), table.concat(layerParts, ","))
    end

    -- Runtime bxor (Lua 5.1 compatible)
    local runtimeCode = [[
do
    local floor = math.floor
    local byte = string.byte
    local char = string.char
    local sub = string.sub

    local function bxor8(a, b)
        local r, bit = 0, 1
        for _ = 1, 8 do
            local ab, bb = a % 2, b % 2
            if ab ~= bb then r = r + bit end
            a = (a - ab) / 2
            b = (b - bb) / 2
            bit = bit * 2
        end
        return r
    end

    local function make_sbox(seed)
        local t = {}
        for i = 0, 255 do t[i] = i end
        local s = seed
        for i = 255, 1, -1 do
            s = (s * 1103515245 + 12345) % 2147483648
            local j = s % (i + 1)
            t[i], t[j] = t[j], t[i]
        end
        return t
    end

    local function invert_sbox(sbox)
        local inv = {}
        for i = 0, 255 do inv[sbox[i]] = i end
        return inv
    end

    -- Decryption functions (inverses of the encryption layers)
    local function dec_xor_rolling(bytes, seed)
        local key = seed % 256
        local out = {}
        for i = 1, #bytes do
            out[i] = bxor8(bytes[i], key)
            key = (key * 7 + 13 + out[i]) % 256
        end
        return out
    end

    local function dec_caesar(bytes, seed)
        local out = {}
        for i = 1, #bytes do
            local shift = (seed + i * 31 + i * i * 7) % 256
            out[i] = (bytes[i] - shift) % 256
        end
        return out
    end

    local function dec_reverse_xor(bytes, seed)
        local constant = seed % 256
        local out = {}
        local n = #bytes
        for i = 1, n do
            out[i] = bxor8(bytes[n - i + 1], constant)
        end
        return out
    end

    local function dec_substitution(bytes, seed)
        local inv = invert_sbox(make_sbox(seed))
        local out = {}
        for i = 1, #bytes do out[i] = inv[bytes[i]] end
        return out
    end

    local function dec_cbc(bytes, seed)
        local iv = seed % 256
        local out = {}
        local prev = iv
        for i = 1, #bytes do
            out[i] = bxor8(bytes[i], prev)
            prev = bytes[i]
        end
        return out
    end

    local decoders = { dec_xor_rolling, dec_caesar, dec_reverse_xor, dec_substitution, dec_cbc }

    local META = {]] .. table.concat(metaParts, ",") .. [[}
    local cache = {}

    function MLE_DECRYPT(idx)
        if cache[idx] then return cache[idx] end
        local entry = META[idx]
        local str = entry[1]
        local layers = entry[2]
        local bytes = {}
        for i = 1, #str do bytes[i] = byte(str, i) end
        -- Unwrap layers in reverse order
        for li = #layers, 1, -1 do
            local layer = layers[li]
            bytes = decoders[layer[1]](bytes, layer[2])
        end
        local parts = {}
        for i = 1, #bytes do parts[i] = char(bytes[i]) end
        cache[idx] = table.concat(parts)
        return cache[idx]
    end
end]]

    local generatedSpan = Source.generated("MultiLayerEncryption")
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
        :parse(runtimeCode, Source.internal("MultiLayerEncryption.Decryptor", runtimeCode))
    local doStat = newAst.body.statements[1]

    local decryptVar = Ast.LocalSymbol("_mle_decrypt")

    -- Rename the placeholder global in the parsed code
    visitast(newAst, nil, function(node, _)
        if node.kind == AstKind.FunctionDeclaration and node.name == "MLE_DECRYPT" then
            node.symbol = decryptVar
            node.name = nil
        end
    end)

    -- Now replace string nodes in the user AST
    visitast(ast, nil, function(node, _)
        if node.kind == AstKind.StringExpression and node._mle_index then
            local idx = node._mle_index
            return Source.inherit(
                Ast.FunctionCallExpression(
                    Ast.VariableExpression(decryptVar),
                    { Ast.NumberExpression(idx) }
                ), node)
        end
    end)

    -- Inject decryptor at the top
    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Source.fill(Ast.LocalVariableDeclaration({ decryptVar }, {}), generatedSpan))

    return ast
end

return MultiLayerEncryption
