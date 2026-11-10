// Only presets verified to reliably produce runnable output across varied inputs
// are exposed in the UI. Heavier presets (High/Strong/Maximum) exist in the Lua
// `presets.lua` for CLI/experimentation but stack enough transforms that they can
// fail on some scripts, so they are intentionally not offered here.
export const PRESETS = ["Minify", "Weak", "Medium"] as const
export const LUA_VERSIONS = ["Lua51", "LuaU"] as const

export type PresetName = (typeof PRESETS)[number]
export type LuaVersion = (typeof LUA_VERSIONS)[number]
export type LogLevel = "info" | "warn" | "error" | "debug"

export interface PrometheusOptions {
  source: string
  filename: string
  preset: PresetName
  luaVersion: LuaVersion
  prettyPrint: boolean
  seed: number
}

export interface PrometheusLog {
  level: LogLevel
  message: string
}

export interface PrometheusSuccess {
  ok: true
  output: string
  logs: PrometheusLog[]
}

export interface PrometheusFailure {
  ok: false
  error: string
  logs: PrometheusLog[]
}

export type PrometheusResult = PrometheusSuccess | PrometheusFailure

export type WorkerRequest =
  | {
      id: number
      action: "obfuscate"
      options: PrometheusOptions
    }
  | {
      id: number
      action: "runScript"
      source: string
      filename: string
    }

export type WorkerResponse =
  | {
      id: number
      type: "result"
      result: PrometheusResult
    }
  | {
      id: number
      type: "log"
      log: PrometheusLog
    }
