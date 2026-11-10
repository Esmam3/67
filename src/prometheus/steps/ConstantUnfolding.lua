-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- ConstantUnfolding.lua
--
-- Replaces numeric and boolean constants with runtime-computed equivalents
-- using polynomial evaluation, modular arithmetic, and mathematical identities.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local Source = require("prometheus.source")
local AstKind = Ast.AstKind

local ConstantUnfolding = Step:extend()
ConstantUnfolding.Name = "Constant Unfolding"
ConstantUnfolding.Description =
    "Replaces numeric and boolean constants with complex runtime-computed equivalents."

ConstantUnfolding.SettingsDescriptor = {
    Threshold = {
        type = "number", default = 0.8, min = 0, max = 1,
        description = "Fraction of constants that will be unfolded.",
    },
    MaxDepth = {
        type = "number", default = 2, min = 1, max = 4,
        description = "Maximum nesting depth for generated expressions.",
    },
}

function ConstantUnfolding:init(_)
end

-- Arithmetic-only XOR for Lua 5.1
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

-- Build an AST expression that evaluates to the given integer at runtime.
-- depth limits recursion to keep output manageable.
local function buildIntExpression(val, depth, maxDepth)
    -- Base case: return raw number
    if depth >= maxDepth then
        return Ast.NumberExpression(val)
    end

    local strategy = math.random(1, 7)

    if strategy == 1 then
        -- Addition split: val = a + b
        local a = math.random(-2^20, 2^20)
        local b = val - a
        if tonumber(tostring(a)) + tonumber(tostring(b)) ~= val then
            return Ast.NumberExpression(val)
        end
        return Ast.AddExpression(
            buildIntExpression(a, depth + 1, maxDepth),
            buildIntExpression(b, depth + 1, maxDepth),
            false
        )
    elseif strategy == 2 then
        -- Subtraction split: val = a - b
        local b = math.random(-2^20, 2^20)
        local a = val + b
        if tonumber(tostring(a)) - tonumber(tostring(b)) ~= val then
            return Ast.NumberExpression(val)
        end
        return Ast.SubExpression(
            buildIntExpression(a, depth + 1, maxDepth),
            buildIntExpression(b, depth + 1, maxDepth),
            false
        )
    elseif strategy == 3 then
        -- Multiplication split: val = a * b (only if val has factors)
        if val ~= 0 then
            local divisors = {}
            local absVal = math.abs(val)
            for d = 2, math.min(absVal, 100) do
                if val % d == 0 then
                    divisors[#divisors + 1] = d
                end
            end
            if #divisors > 0 then
                local d = divisors[math.random(1, #divisors)]
                local q = val / d
                if tonumber(tostring(d)) * tonumber(tostring(q)) == val then
                    return Ast.MulExpression(
                        buildIntExpression(d, depth + 1, maxDepth),
                        buildIntExpression(q, depth + 1, maxDepth),
                        false
                    )
                end
            end
        end
        -- Fallback to addition
        local a = math.random(1, 2^15)
        return Ast.AddExpression(
            buildIntExpression(val - a, depth + 1, maxDepth),
            buildIntExpression(a, depth + 1, maxDepth),
            false
        )
    elseif strategy == 4 then
        -- Modulo: val = (val + k*m) % m, where m > val
        if val >= 0 and val == math.floor(val) then
            local m = val + math.random(100, 10000)
            local k = math.random(1, 50)
            local lhs = val + k * m
            if tonumber(tostring(lhs)) % tonumber(tostring(m)) == val then
                return Ast.ModExpression(
                    buildIntExpression(lhs, depth + 1, maxDepth),
                    Ast.NumberExpression(m),
                    false
                )
            end
        end
        return Ast.AddExpression(
            buildIntExpression(val - 1, depth + 1, maxDepth),
            Ast.NumberExpression(1),
            false
        )
    elseif strategy == 5 then
        -- Negation: val = -(−val)
        return Ast.NegateExpression(
            buildIntExpression(-val, depth + 1, maxDepth),
            false
        )
    elseif strategy == 6 then
        -- Floor division reconstruction: val = (val * k) / k (integer only)
        local k = math.random(2, 20)
        local product = val * k
        if tonumber(tostring(product)) / tonumber(tostring(k)) == val then
            return Ast.DivExpression(
                buildIntExpression(product, depth + 1, maxDepth),
                Ast.NumberExpression(k),
                false
            )
        end
        return Ast.NumberExpression(val)
    else
        -- Double negation via subtraction from 0: val = 0 - (0 - val)
        return Ast.SubExpression(
            Ast.NumberExpression(0),
            Ast.SubExpression(
                Ast.NumberExpression(0),
                buildIntExpression(val, depth + 1, maxDepth),
                false
            ),
            false
        )
    end
end

-- Build an expression that evaluates to true or false
local function buildBoolExpression(val)
    local strategy = math.random(1, 4)

    if strategy == 1 then
        -- Comparison: true = (a < a+1), false = (a+1 < a)
        local n = math.random(1, 10000)
        if val then
            return Ast.LessThanExpression(
                Ast.NumberExpression(n),
                Ast.NumberExpression(n + 1)
            )
        else
            return Ast.LessThanExpression(
                Ast.NumberExpression(n + 1),
                Ast.NumberExpression(n)
            )
        end
    elseif strategy == 2 then
        -- Equality: true = (n == n), false = (n == n+1)
        local n = math.random(1, 10000)
        if val then
            return Ast.EqualsExpression(
                Ast.NumberExpression(n),
                Ast.NumberExpression(n)
            )
        else
            return Ast.EqualsExpression(
                Ast.NumberExpression(n),
                Ast.NumberExpression(n + 1)
            )
        end
    elseif strategy == 3 then
        -- not not val
        return Ast.NotExpression(
            Ast.NotExpression(Ast.BooleanExpression(val))
        )
    else
        -- Inequality: true = (a ~= a+1), false = (a ~= a)
        local n = math.random(1, 10000)
        if val then
            return Ast.NotEqualsExpression(
                Ast.NumberExpression(n),
                Ast.NumberExpression(n + 1)
            )
        else
            return Ast.NotEqualsExpression(
                Ast.NumberExpression(n),
                Ast.NumberExpression(n)
            )
        end
    end
end

function ConstantUnfolding:apply(ast, _)
    local threshold = self.Threshold
    local maxDepth = self.MaxDepth

    visitast(ast, nil, function(node, _)
        if math.random() > threshold then return end

        if node.kind == AstKind.NumberExpression then
            local val = node.value
            if type(val) ~= "number" then return end
            -- Skip non-finite values
            if val ~= val or val == math.huge or val == -math.huge then return end
            -- Only unfold integers in a safe range
            if val ~= math.floor(val) or math.abs(val) > 2^30 then return end

            return Source.inherit(buildIntExpression(val, 0, maxDepth), node)
        end

        if node.kind == AstKind.BooleanExpression then
            return Source.inherit(buildBoolExpression(node.value), node)
        end
    end)

    return ast
end

return ConstantUnfolding
