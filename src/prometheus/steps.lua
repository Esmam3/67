-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- steps.lua
--
-- This Script provides a collection of obfuscation steps.

local Cff = require("prometheus.steps.Cff");
local BogusControlFlow = require("prometheus.steps.BogusControlFlow");
local EnvironmentChecks = require("prometheus.steps.EnvironmentChecks");
local SelfChecksum = require("prometheus.steps.SelfChecksum");
local CallIndirection = require("prometheus.steps.CallIndirection");
local ConstantUnfolding = require("prometheus.steps.ConstantUnfolding");
local MultiLayerEncryption = require("prometheus.steps.MultiLayerEncryption");
local OpcodeSubstitution = require("prometheus.steps.OpcodeSubstitution");
local DummyCode = require("prometheus.steps.DummyCode");
local MBAObfuscation = require("prometheus.steps.MBAObfuscation");
local DynamicCodeGeneration = require("prometheus.steps.DynamicCodeGeneration");
local TableIndirection = require("prometheus.steps.TableIndirection");
local BytecodeEncryption = require("prometheus.steps.BytecodeEncryption");
local StringMorph = require("prometheus.steps.StringMorph");

return {
	-- Original steps
	WrapInFunction = require("prometheus.steps.WrapInFunction"),
	SplitStrings = require("prometheus.steps.SplitStrings"),
	Cff = Cff,
	ControlFlowFlattening = Cff,
	Vmify = require("prometheus.steps.Vmify"),
	ConstantArray = require("prometheus.steps.ConstantArray"),
	ProxifyLocals = require("prometheus.steps.ProxifyLocals"),
	AntiTamper = require("prometheus.steps.AntiTamper"),
	EncryptStrings = require("prometheus.steps.EncryptStrings"),
	NumbersToExpressions = require("prometheus.steps.NumbersToExpressions"),
	AddVararg = require("prometheus.steps.AddVararg"),
	WatermarkCheck = require("prometheus.steps.WatermarkCheck"),
	Watermark = require("prometheus.steps.Watermark"),
	OpaquePredicates = require("prometheus.steps.OpaquePredicates"),
	DeadCodeInjection = require("prometheus.steps.DeadCodeInjection"),
	StringToBytes = require("prometheus.steps.StringToBytes"),

	-- Advanced protection steps
	MultiLayerEncryption = MultiLayerEncryption,
	["Multi Layer Encryption"] = MultiLayerEncryption,
	ConstantUnfolding = ConstantUnfolding,
	["Constant Unfolding"] = ConstantUnfolding,
	CallIndirection = CallIndirection,
	["Call Indirection"] = CallIndirection,
	BogusControlFlow = BogusControlFlow,
	["Bogus Control Flow"] = BogusControlFlow,
	EnvironmentChecks = EnvironmentChecks,
	["Environment Checks"] = EnvironmentChecks,
	SelfChecksum = SelfChecksum,
	["Self Checksum"] = SelfChecksum,
	BytecodeEncryption = BytecodeEncryption,
	["Bytecode Encryption"] = BytecodeEncryption,
	DummyCode = DummyCode,
	["Dummy Code"] = DummyCode,
	OpcodeSubstitution = OpcodeSubstitution,
	["Opcode Substitution"] = OpcodeSubstitution,
	StringMorph = StringMorph,
	["String Morph"] = StringMorph,
	MBAObfuscation = MBAObfuscation,
	["MBA Obfuscation"] = MBAObfuscation,
	DynamicCodeGeneration = DynamicCodeGeneration,
	["Dynamic Code Generation"] = DynamicCodeGeneration,
	TableIndirection = TableIndirection,
	["Table Indirection"] = TableIndirection,
}
