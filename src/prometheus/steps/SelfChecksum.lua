-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- SelfChecksum.lua
--
-- This Step injects runtime self-integrity verification that detects
-- modifications to function structure, sentinel values, and code layout.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Source = require("prometheus.source")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")

local SelfChecksum = Step:extend()
SelfChecksum.Description = "This Step injects runtime self-integrity verification using function structure and sentinel checks."
SelfChecksum.Name = "Self Checksum"

SelfChecksum.SettingsDescriptor = {
	CheckCount = {
		name = "CheckCount",
		description = "Number of integrity checks to scatter through the code",
		type = "number",
		default = 3,
		min = 1,
		max = 10,
	},
	FailMode = {
		name = "FailMode",
		description = "What to do when integrity check fails: crash, corrupt, or silent",
		type = "enum",
		values = {"crash", "corrupt", "silent"},
		default = "crash",
	},
}

function SelfChecksum:init(_) end

local function makeFailAction(mode)
	if mode == "corrupt" then
		return [[
			local _sv = rawget(_G, "string")
			if type(_sv) == "table" then
				rawset(_sv, "sub", function() return "" end)
				rawset(_sv, "byte", function() return 0 end)
				rawset(_sv, "format", function() return "" end)
			end
			local _sm = rawget(_G, "math")
			if type(_sm) == "table" then
				rawset(_sm, "random", function() return 0 end)
			end
		]]
	elseif mode == "silent" then
		return [[
			rawset(_G, "_INTEGRITY_FAIL", true)
		]]
	else
		return [[
			rawset(_G, "error", nil)
			rawset(_G, "pcall", nil)
			rawset(_G, "xpcall", nil);
			(nil)()
		]]
	end
end

local function makeSentinelCheck(failMode, idx)
	local failAction = makeFailAction(failMode)
	local sentinel = string.format("_SC%d_%d", idx, math.random(100000, 999999))
	local sentinelVal = math.random(100000, 999999)

	return string.format([[do
	local %s = %d
	local _scv%d = function()
		return %s
	end
	local _scr%d = _scv%d()
	if type(_scr%d) ~= "number" or _scr%d ~= %d then
		%s
	end
	local _sct%d = tostring(_scr%d)
	if #_sct%d ~= %d then
		%s
	end
end]], sentinel, sentinelVal,
	idx, sentinel,
	idx, idx,
	idx, idx, sentinelVal,
	failAction,
	idx, idx,
	idx, #tostring(sentinelVal),
	failAction)
end

local function makeFunctionStructureCheck(failMode, idx)
	local failAction = makeFailAction(failMode)

	return string.format([[do
	local _sfs%d = function(_a, _b, _c) return _a, _b, _c end
	local _sfdb = rawget(_G, "debug")
	if type(_sfdb) == "table" then
		local _sfgi = rawget(_sfdb, "getinfo")
		if type(_sfgi) == "function" then
			local _sfok, _sfinfo = pcall(_sfgi, _sfs%d, "u")
			if _sfok and type(_sfinfo) == "table" then
				local _sfnp = rawget(_sfinfo, "nparams")
				if _sfnp ~= nil and _sfnp ~= 3 then
					%s
				end
			end
		end
	end
	local _sfr1, _sfr2, _sfr3 = _sfs%d(1, 2, 3)
	if _sfr1 ~= 1 or _sfr2 ~= 2 or _sfr3 ~= 3 then
		%s
	end
end]], idx, idx, failAction, idx, failAction)
end

local function makeCallDepthCheck(failMode, idx)
	local failAction = makeFailAction(failMode)
	local depth = math.random(3, 6)
	local expectedSum = 0
	for i = 1, depth do expectedSum = expectedSum + i end

	return string.format([[do
	local _scd%d = 0
	local _scdf%d
	_scdf%d = function(_n)
		_scd%d = _scd%d + _n
		if _n > 1 then _scdf%d(_n - 1) end
	end
	_scdf%d(%d)
	if _scd%d ~= %d then
		%s
	end
	_scd%d = nil
end]], idx, idx, idx, idx, idx, idx, idx, depth, idx, expectedSum, failAction, idx)
end

local function makeStringIntegrityCheck(failMode, idx)
	local failAction = makeFailAction(failMode)
	local testStr = "_sch" .. tostring(math.random(10000, 99999))
	local testLen = #testStr

	return string.format([[do
	local _ssi%d = "%s"
	local _ssl%d = rawget(rawget(_G, "string") or {}, "len")
	if type(_ssl%d) == "function" then
		local _ssok, _sslen = pcall(_ssl%d, _ssi%d)
		if not _ssok or _sslen ~= %d then
			%s
		end
	end
	local _ssb%d = rawget(rawget(_G, "string") or {}, "byte")
	if type(_ssb%d) == "function" then
		local _sbok, _sbval = pcall(_ssb%d, _ssi%d, 1)
		if not _sbok or _sbval ~= %d then
			%s
		end
	end
end]], idx, testStr,
	idx,
	idx,
	idx, idx,
	testLen,
	failAction,
	idx,
	idx,
	idx, idx,
	string.byte(testStr, 1),
	failAction)
end

function SelfChecksum:apply(ast, pipeline)
	local span = Source.generated("SelfChecksum")
	local checkCount = self.CheckCount
	local failMode = self.FailMode

	local checkGenerators = {
		makeSentinelCheck,
		makeFunctionStructureCheck,
		makeCallDepthCheck,
		makeStringIntegrityCheck,
	}

	local checks = {}
	for i = 1, checkCount do
		local gen = checkGenerators[((i - 1) % #checkGenerators) + 1]
		checks[#checks + 1] = gen(failMode, i)
	end

	for _, code in ipairs(checks) do
		local parsed = Parser:new({LuaVersion = Enums.LuaVersion.Lua51}):parse(
			code, Source.internal("SelfChecksum", code))
		local doStat = parsed.body.statements[1]
		Source.fill(doStat, span)

		local totalStatements = #ast.body.statements
		local pos
		if totalStatements <= 1 then
			pos = 1
		else
			pos = math.random(1, totalStatements)
		end
		table.insert(ast.body.statements, pos, doStat)
	end

	return ast
end

return SelfChecksum
