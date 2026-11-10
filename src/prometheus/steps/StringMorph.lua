-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- StringMorph.lua
--
-- Advanced string concealment that splits strings into scattered fragments
-- distributed across multiple tables, reconstructed through an indirection
-- map at runtime. Harder to statically extract than a single encrypted blob.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Source = require("prometheus.source")
local AstKind = Ast.AstKind

local StringMorph = Step:extend()
StringMorph.Description = "Scatters string fragments across multiple tables with a runtime reconstruction map."
StringMorph.Name = "String Morph"

StringMorph.SettingsDescriptor = {
    Threshold = { type = "number", default = 0.7, min = 0, max = 1 },
    FragmentSize = { type = "number", default = 3, min = 1, max = 8 },
    TableCount = { type = "number", default = 4, min = 2, max = 8 },
}

function StringMorph:init(_) end

-- Encode a raw string as a Lua double-quoted literal using zero-padded numeric
-- escapes for every byte (safe for all bytes; never collides with delimiters).
local function encodeBytes(str)
    local out = {}
    for i = 1, #str do
        out[i] = string.format("\\%03d", string.byte(str, i))
    end
    return '"' .. table.concat(out) .. '"'
end

function StringMorph:apply(ast, pipeline)
    local generatedSpan = Source.generated("StringMorph")
    local tableCount = self.TableCount
    local fragmentSize = self.FragmentSize

    local scatterTables = {}
    for i = 1, tableCount do scatterTables[i] = {} end
    local keyBase = math.random(1000, 9999)

    -- Pass 1: tag eligible string nodes and scatter their fragments.
    local entries = {}
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and type(node.value) == "string" then
            if #node.value == 0 then return end
            if math.random() > self.Threshold then return end

            local id = #entries + 1
            local fragments = {}
            local pos = 1
            while pos <= #node.value do
                local chunk = math.random(1, fragmentSize)
                if pos + chunk - 1 > #node.value then chunk = #node.value - pos + 1 end
                local frag = node.value:sub(pos, pos + chunk - 1)

                local ti = math.random(1, tableCount)
                local tbl = scatterTables[ti]
                local key = keyBase + #tbl + 1
                tbl[#tbl + 1] = { key = key, value = frag }
                fragments[#fragments + 1] = { ti, key }
                pos = pos + chunk
            end

            entries[id] = fragments
            node._sm_index = id
        end
    end)

    if #entries == 0 then return ast end

    -- Build the infrastructure source (plain concatenated Lua, never a long
    -- string literal, so there is no delimiter-collision risk).
    local parts = { "do\n" }
    for i = 1, tableCount do
        parts[#parts + 1] = string.format("local _t%d={", i)
        local kv = {}
        for _, e in ipairs(scatterTables[i]) do
            kv[#kv + 1] = string.format("[%d]=%s", e.key, encodeBytes(e.value))
        end
        util.shuffle(kv)
        parts[#parts + 1] = table.concat(kv, ",")
        parts[#parts + 1] = "}\n"
    end

    parts[#parts + 1] = "local _map={"
    local mapParts = {}
    for id, frags in ipairs(entries) do
        local fp = {}
        for _, f in ipairs(frags) do
            fp[#fp + 1] = string.format("{%d,%d}", f[1], f[2])
        end
        mapParts[#mapParts + 1] = string.format("[%d]={%s}", id, table.concat(fp, ","))
    end
    parts[#parts + 1] = table.concat(mapParts, ",")
    parts[#parts + 1] = "}\n"

    parts[#parts + 1] = "local _tables={"
    for i = 1, tableCount do
        parts[#parts + 1] = (i > 1 and "," or "") .. string.format("_t%d", i)
    end
    parts[#parts + 1] = "}\n"

    parts[#parts + 1] = [==[
local _cache={}
function SM_REASSEMBLE(id)
  local c=_cache[id]
  if c then return c end
  local frags=_map[id]
  local out={}
  for i=1,#frags do
    local f=frags[i]
    out[i]=_tables[f[1]][f[2]]
  end
  local r=table.concat(out)
  _cache[id]=r
  return r
end
end
]==]

    local code = table.concat(parts)
    local parsed = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(
        code, Source.internal("StringMorph.Infrastructure", code))
    local doStat = parsed.body.statements[1]

    -- Rename the global function declaration to an outer local (MLE pattern).
    local reassembleVar = Ast.LocalSymbol("_sm_r")
    visitast(parsed, nil, function(node)
        if node.kind == AstKind.FunctionDeclaration and node.name == "SM_REASSEMBLE" then
            node.symbol = reassembleVar
            node.name = nil
        end
    end)

    -- Pass 2: replace tagged string nodes with _sm_r(id).
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and node._sm_index then
            return Source.inherit(
                Ast.FunctionCallExpression(
                    Ast.VariableExpression(reassembleVar),
                    { Ast.NumberExpression(node._sm_index) }
                ), node)
        end
    end)

    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Source.fill(Ast.LocalVariableDeclaration({ reassembleVar }, {}), generatedSpan))

    return ast
end

return StringMorph
