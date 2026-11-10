-- This Script is Part of the Prometheus Obfuscator by levno-710
--
-- presets.lua
--
-- This Script provides the predefined obfuscation presets for Prometheus

return {
	-- Minifies your code. Does not obfuscate it. No performance loss.
	["Minify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {},
	},

	-- Weak obfuscation. Lightly obfuscated, low performance loss.
	-- Adds control-flow flattening, constant extraction, and light opaque predicates.
	["Weak"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Cff", Settings = {} },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 0.3,
				},
			},
		},
	},

	-- Standalone control-flow flattening for tests and custom pipelines.
	-- It is not recommended to use this preset for obfuscation.
	-- Use the Weak, Medium, High, or Strong presets for obfuscation instead.
	["Cff"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Cff", Settings = {} },
		},
	},

	-- Standalone register VM for tests and custom pipelines.
	["Vmify"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
		},
	},

	-- Medium obfuscation. Moderate obfuscation, moderate performance loss.
	-- Combines VM, string encryption, anti-tamper, CFF, and light dead code / opaque predicates.
	["Medium"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
			{ Name = "EncryptStrings", Settings = { HoistVmStrings = true } },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
			{
				Name = "DeadCodeInjection",
				Settings = {
					Threshold = 0.3,
				},
			},
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 0.5,
				},
			},
			{ Name = "Cff", Settings = { ExcludeVm = true } },
			{ Name = "NumbersToExpressions", Settings = {} },
		},
	},

	-- High obfuscation. Strong protection with manageable performance cost.
	-- Adds string-to-bytes conversion and deeper opaque predicates / dead code on top of Medium.
	["High"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
			{ Name = "EncryptStrings", Settings = { HoistVmStrings = true } },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 0.6,
					MaxDepth = 2,
				},
			},
			{
				Name = "DeadCodeInjection",
				Settings = {
					Threshold = 0.5,
					Intensity = 3,
				},
			},
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
			{ Name = "Cff", Settings = { ExcludeVm = true } },
			{
				Name = "NumbersToExpressions",
				Settings = {
					NumberRepresentationMutation = true,
				},
			},
			{
				Name = "StringToBytes",
				Settings = {
					Threshold = 0.3,
				},
			},
		},
	},

	-- Strong obfuscation, high performance loss.
	-- Full CFF (including VM), opaque predicates, dead code, and string-to-bytes.
	["Strong"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
			{ Name = "EncryptStrings", Settings = {} },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = false,
				},
			},
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 0.8,
					MaxDepth = 3,
				},
			},
			{
				Name = "DeadCodeInjection",
				Settings = {
					Threshold = 0.7,
					Intensity = 4,
				},
			},
			{ Name = "Cff", Settings = {} },
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					StringsOnly = true,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{
				Name = "NumbersToExpressions",
				Settings = {
					NumberRepresentationMutation = true,
				},
			},
			{ Name = "WrapInFunction", Settings = {} },
			{
				Name = "StringToBytes",
				Settings = {
					Threshold = 0.5,
				},
			},
		},
	},

	-- Maximum obfuscation. Every technique enabled at full strength.
	-- Extremely high performance loss and large output. Use only when maximum
	-- protection is required and runtime cost is acceptable.
	["Maximum"] = {
		LuaVersion = "Lua51",
		VarNamePrefix = "",
		NameGenerator = "MangledShuffled",
		PrettyPrint = false,
		Seed = 0,
		Steps = {
			{ Name = "Vmify", Settings = {} },
			{ Name = "EncryptStrings", Settings = { HoistVmStrings = true } },
			{
				Name = "AntiTamper",
				Settings = {
					UseDebug = true,
				},
			},
			{
				Name = "OpaquePredicates",
				Settings = {
					Threshold = 1.0,
					MaxDepth = 5,
				},
			},
			{
				Name = "DeadCodeInjection",
				Settings = {
					Threshold = 1.0,
					Intensity = 5,
				},
			},
			{ Name = "ProxifyLocals", Settings = {} },
			{
				Name = "SplitStrings",
				Settings = {
					ConcatNatively = true,
				},
			},
			{
				Name = "ConstantArray",
				Settings = {
					Threshold = 1,
					Shuffle = true,
					Rotate = true,
					LocalWrapperThreshold = 0,
				},
			},
			{
				Name = "WrapInFunction",
				Settings = {
					Iterations = 2,
				},
			},
			{ Name = "Cff", Settings = {} },
			{
				Name = "NumbersToExpressions",
				Settings = {
					NumberRepresentationMutation = true,
				},
			},
			{
				Name = "StringToBytes",
				Settings = {
					Threshold = 0.8,
				},
			},
			{ Name = "AddVararg", Settings = {} },
		},
	},
}
