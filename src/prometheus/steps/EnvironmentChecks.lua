-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- EnvironmentChecks.lua
--
-- This Step injects runtime anti-debugging and environment validation checks
-- that detect debuggers, timing anomalies, and tampered standard libraries.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Source = require("prometheus.source")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")

local EnvironmentChecks = Step:extend()
EnvironmentChecks.Description = "This Step injects runtime anti-debugging and environment validation checks."
EnvironmentChecks.Name = "Environment Checks"

EnvironmentChecks.SettingsDescriptor = {
	CheckDebugLibrary = {
		name = "CheckDebugLibrary",
		description = "Check for debug library hooks and instrumentation",
		type = "boolean",
		default = true,
	},
	CheckTiming = {
		name = "CheckTiming",
		description = "Check for timing anomalies that indicate stepping debuggers",
		type = "boolean",
		default = true,
	},
	CheckEnvironment = {
		name = "CheckEnvironment",
		description = "Check standard library integrity",
		type = "boolean",
		default = true,
	},
	FailMode = {
		name = "FailMode",
		description = "What to do when a check fails: crash, corrupt, or infinite_loop",
		type = "enum",
		values = {"crash", "corrupt", "infinite_loop"},
		default = "crash",
	},
}

function EnvironmentChecks:init(_) end

local function makeFailAction(mode)
	if mode == "corrupt" then
		return [[
			local _ev = rawget(_G, "string")
			if type(_ev) == "table" then
				rawset(_ev, "sub", function() return "" end)
				rawset(_ev, "byte", function() return 0 end)
				rawset(_ev, "char", function() return "" end)
				rawset(_ev, "len", function() return 0 end)
				rawset(_ev, "format", function() return "" end)
			end
			local _et = rawget(_G, "table")
			if type(_et) == "table" then
				rawset(_et, "insert", function() end)
				rawset(_et, "remove", function() end)
				rawset(_et, "concat", function() return "" end)
			end
			local _em = rawget(_G, "math")
			if type(_em) == "table" then
				rawset(_em, "random", function() return 0 end)
				rawset(_em, "floor", function() return 0 end)
			end
		]]
	elseif mode == "infinite_loop" then
		return [[
			while true do
				local _el = {}
				for _ei = 1, 1000 do _el[_ei] = _ei end
				_el = nil
			end
		]]
	else
		return [[
			local _ek = tostring(nil)
			rawset(_G, "error", nil)
			rawset(_G, "pcall", nil)
			rawset(_G, "xpcall", nil)
			rawset(_G, "print", nil)
			rawset(_G, "io", nil)
			(nil)()
		]]
	end
end

local function makeDebugCheck(failMode)
	local failAction = makeFailAction(failMode)
	return string.format([[do
	local _ed1 = rawget(_G, "debug")
	if type(_ed1) == "table" then
		local _egh = rawget(_ed1, "gethook")
		if type(_egh) == "function" then
			local _ehf, _ehm = _egh()
			if _ehf ~= nil or (_ehm ~= nil and _ehm ~= "" and _ehm ~= 0) then
				%s
			end
		end
		local _egi = rawget(_ed1, "getinfo")
		if type(_egi) == "function" then
			local _eok, _einf = pcall(_egi, 1)
			if _eok and type(_einf) == "table" then
				local _esrc = rawget(_einf, "source")
				if type(_esrc) == "string" and _esrc:find("@debug") then
					%s
				end
			end
		end
	end
end]], failAction, failAction)
end

local function makeTimingCheck(failMode)
	local failAction = makeFailAction(failMode)
	return string.format([[do
	local _etc = os and rawget(os, "clock")
	if type(_etc) == "function" then
		local _et1 = _etc()
		local _etv = 0
		for _eti = 1, 5000 do
			_etv = _etv + _eti
		end
		local _et2 = _etc()
		local _etd = _et2 - _et1
		if _etd > 0.5 then
			%s
		end
	end
end]], failAction)
end

local function makeEnvironmentCheck(failMode)
	local failAction = makeFailAction(failMode)
	return string.format([[do
	local _efc = {
		{rawget(_G, "type"), "function"},
		{rawget(_G, "tostring"), "function"},
		{rawget(_G, "tonumber"), "function"},
		{rawget(_G, "pcall"), "function"},
		{rawget(_G, "select"), "function"},
		{rawget(_G, "rawget"), "function"},
		{rawget(_G, "rawset"), "function"},
		{rawget(_G, "setmetatable"), "function"},
		{rawget(_G, "getmetatable"), "function"},
	}
	for _efi = 1, #_efc do
		local _efp = _efc[_efi]
		if type(_efp[1]) ~= _efp[2] then
			%s
			break
		end
	end
	local _efs = rawget(_G, "string")
	if type(_efs) ~= "table" then
		%s
	else
		local _efl = rawget(_efs, "len")
		if type(_efl) ~= "function" then
			%s
		else
			local _efok, _efr = pcall(_efl, "test")
			if not _efok or _efr ~= 4 then
				%s
			end
		end
	end
	local _eft = rawget(_G, "table")
	if type(_eft) ~= "table" then
		%s
	else
		local _efc2 = rawget(_eft, "concat")
		if type(_efc2) ~= "function" then
			%s
		else
			local _efok2, _efr2 = pcall(_efc2, {"a","b"}, ",")
			if not _efok2 or _efr2 ~= "a,b" then
				%s
			end
		end
	end
end]], failAction, failAction, failAction, failAction, failAction, failAction, failAction)
end

function EnvironmentChecks:apply(ast, pipeline)
	local span = Source.generated("EnvironmentChecks")
	local checks = {}

	if self.CheckDebugLibrary then
		checks[#checks + 1] = makeDebugCheck(self.FailMode)
	end

	if self.CheckTiming then
		checks[#checks + 1] = makeTimingCheck(self.FailMode)
	end

	if self.CheckEnvironment then
		checks[#checks + 1] = makeEnvironmentCheck(self.FailMode)
	end

	for _, code in ipairs(checks) do
		local parsed = Parser:new({LuaVersion = Enums.LuaVersion.Lua51}):parse(
			code, Source.internal("EnvironmentChecks", code))
		local doStat = parsed.body.statements[1]
		Source.fill(doStat, span)

		local totalStatements = #ast.body.statements
		local pos
		if totalStatements <= 2 then
			pos = 1
		else
			pos = math.random(1, math.max(1, math.floor(totalStatements / 2)))
		end
		table.insert(ast.body.statements, pos, doStat)
	end

	return ast
end

return EnvironmentChecks
