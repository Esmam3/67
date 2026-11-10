-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- StringMorph.lua
--
-- Advanced string concealment that splits strings into scattered pieces
-- reconstructed through multiple indirection layers at runtime.
-- Much harder to statically extract than simple XOR encryption.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local Source = require("prometheus.source")
local AstKind = Ast.AstKind

local StringMorph = Step:extend()
StringMorph.Description = "Scatters string fragments across multiple tables with layered reconstruction at runtime."
StringMorph.Name = "String Morph"

StringMorph.SettingsDescriptor = {
    Threshold = { type = "number", default = 0.7, min = 0, max = 1 },
    FragmentSize = { type = "number", default = 3, min = 1, max = 8 },
    TableCount = { type = "number", default = 4, min = 2, max = 8 },
    ObfuscateIndices = { type = "boolean", default = true },
}

function StringMorph:init(_) end

function StringMorph:apply(ast, pipeline)
    local generatedSpan = Source.generated("StringMorph")

    -- Collect all strings we'll transform
    local stringEntries = {}
    local tableCount = self.TableCount
    local fragmentSize = self.FragmentSize

    -- Scatter tables that hold string fragments
    local scatterTables = {}
    for i = 1, tableCount do
        scatterTables[i] = { var = Ast.LocalSymbol("_sm_t" .. i), entries = {} }
    end
    local reassembleVar = Ast.LocalSymbol("_sm_r")
    local indexKeyBase = math.random(1000, 9999)

    -- First pass: collect strings and assign fragments to tables
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression then
            if math.random() > self.Threshold then return end
            if #node.value == 0 then return end

            local entry = { fragments = {}, id = #stringEntries + 1 }

            -- Split the string into fragments
            local pos = 1
            local fragIndex = 1
            while pos <= #node.value do
                local chunkSize = math.random(1, fragmentSize)
                if pos + chunkSize - 1 > #node.value then
                    chunkSize = #node.value - pos + 1
                end
                local fragment = node.value:sub(pos, pos + chunkSize - 1)

                -- Assign to a random scatter table
                local tableIdx = math.random(1, tableCount)
                local scTable = scatterTables[tableIdx]
                local storageKey = indexKeyBase + #scTable.entries + 1

                scTable.entries[#scTable.entries + 1] = {
                    key = storageKey,
                    value = fragment,
                }

                entry.fragments[fragIndex] = {
                    tableIdx = tableIdx,
                    storageKey = storageKey,
                }

                fragIndex = fragIndex + 1
                pos = pos + chunkSize
            end

            stringEntries[#stringEntries + 1] = entry
        end
    end)

    if #stringEntries == 0 then return ast end

    -- Build a reassembly map: maps entry.id -> ordered list of {tableIdx, key}
    local reassemblyVar = Ast.LocalSymbol("_sm_map")

    -- Second pass: replace string nodes
    local entryIndex = 0
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression then
            if #node.value == 0 then return end

            entryIndex = entryIndex + 1
            if entryIndex > #stringEntries then return end

            local entry = stringEntries[entryIndex]
            if not entry then return end

            -- Replace with: _sm_r(ENTRY_ID)
            return Source.fill(
                Ast.FunctionCallExpression(
                    Ast.VariableExpression(reassembleVar),
                    { Ast.NumberExpression(entry.id) }
                ),
                generatedSpan
            )
        end
    end)

    -- Generate the scatter table declarations
    local allVars = {}
    for i = 1, tableCount do
        allVars[#allVars + 1] = scatterTables[i].var
    end
    allVars[#allVars + 1] = reassembleVar
    allVars[#allVars + 1] = reassemblyVar

    -- Build the infrastructure code
    local codeParts = {}
    codeParts[#codeParts + 1] = "do\n"

    -- Scatter tables
    for i = 1, tableCount do
        local st = scatterTables[i]
        codeParts[#codeParts + 1] = string.format("local _t%d = {", i)
        local entryParts = {}
        for _, entry in ipairs(st.entries) do
            -- Escape the string value for Lua source
            local escaped = ""
            for ci = 1, #entry.value do
                escaped = escaped .. string.format("\\%d", string.byte(entry.value, ci))
            end
            entryParts[#entryParts + 1] = string.format("[%d]=\"%s\"", entry.key, escaped)
        end
        -- Shuffle entries to prevent order-based analysis
        util.shuffle(entryParts)
        codeParts[#codeParts + 1] = table.concat(entryParts, ",")
        codeParts[#codeParts + 1] = "}\n"
    end

    -- Reassembly map
    codeParts[#codeParts + 1] = "local _map = {"
    local mapParts = {}
    for _, entry in ipairs(stringEntries) do
        local fragParts = {}
        for _, frag in ipairs(entry.fragments) do
            fragParts[#fragParts + 1] = string.format("{%d,%d}", frag.tableIdx, frag.storageKey)
        end
        mapParts[#mapParts + 1] = string.format("[%d]={%s}", entry.id, table.concat(fragParts, ","))
    end
    codeParts[#codeParts + 1] = table.concat(mapParts, ",")
    codeParts[#codeParts + 1] = "}\n"

    -- Table references array
    codeParts[#codeParts + 1] = "local _tables = {"
    for i = 1, tableCount do
        if i > 1 then codeParts[#codeParts + 1] = "," end
        codeParts[#codeParts + 1] = string.format("_t%d", i)
    end
    codeParts[#codeParts + 1] = "}\n"

    -- Reassembly function with caching
    codeParts[#codeParts + 1] = [[
local _cache = {}
REASSEMBLE = function(id)
    if _cache[id] then return _cache[id] end
    local frags = _map[id]
    local parts = {}
    for i = 1, #frags do
        local f = frags[i]
        parts[i] = _tables[f[1]][f[2]]
    end
    local result = table.concat(parts)
    _cache[id] = result
    return result
end
]]

    -- Assign to outer vars
    for i = 1, tableCount do
        codeParts[#codeParts + 1] = string.format("SM_T%d = _t%d\n", i, i)
    end
    codeParts[#codeParts + 1] = "SM_MAP = _map\n"

    codeParts[#codeParts + 1] = "end\n"

    local code = table.concat(codeParts)
    local parsedAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(
        code, Source.internal("StringMorph.Infrastructure", code))
    local doStat = parsedAst.body.statements[1]

    -- Rename generated globals to our local symbols
    visitast(parsedAst, nil, function(node)
        if node.kind == AstKind.FunctionDeclaration or node.kind == AstKind.AssignmentVariable
            or node.kind == AstKind.AssignmentGlobalVariable then
            if node.name == "REASSEMBLE" then
                if node.kind == AstKind.FunctionDeclaration then
                    node.symbol = reassembleVar
                    node.name = nil
                else
                    return Source.fill(Ast.AssignmentVariable(reassembleVar), generatedSpan)
                end
            end
        end
        if node.kind == AstKind.VariableExpression or node.kind == AstKind.GlobalVariableExpression then
            if node.name == "REASSEMBLE" then
                return Source.fill(Ast.VariableExpression(reassembleVar), generatedSpan)
            end
        end
    end)

    -- Insert locals declaration and infrastructure
    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1, Source.fill(
        Ast.LocalVariableDeclaration(util.shuffle(allVars), {}),
        generatedSpan
    ))

    return ast
end

return StringMorph
