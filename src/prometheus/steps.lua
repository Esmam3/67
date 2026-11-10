-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- steps.lua
--
-- This Script provides a collection of obfuscation steps.

local Cff = require("prometheus.steps.Cff");

return {
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
	OpaquePredicates = require("prometheus.steps.OpaquePredicates"),
	DeadCodeInjection = require("prometheus.steps.DeadCodeInjection"),
	StringToBytes = require("prometheus.steps.StringToBytes"),
	MultiLayerEncryption = require("prometheus.steps.MultiLayerEncryption"),
	ConstantUnfolding = require("prometheus.steps.ConstantUnfolding"),
	CallIndirection = require("prometheus.steps.CallIndirection"),
	BogusControlFlow = require("prometheus.steps.BogusControlFlow"),
	EnvironmentChecks = require("prometheus.steps.EnvironmentChecks"),
	SelfChecksum = require("prometheus.steps.SelfChecksum"),
	BytecodeEncryption = require("prometheus.steps.BytecodeEncryption"),
	DummyCode = require("prometheus.steps.DummyCode"),
	OpcodeSubstitution = require("prometheus.steps.OpcodeSubstitution"),
	StringMorph = require("prometheus.steps.StringMorph"),
	Watermark = require("prometheus.steps.Watermark"),
}
