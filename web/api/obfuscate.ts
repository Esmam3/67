// Vercel serverless function: server-side Lua obfuscation.
//
// Accepts POST { source, preset?, luaVersion?, prettyPrint?, seed? } and returns
// { ok: true, output } or { ok: false, error }. The Prometheus obfuscator is pure
// Lua; it runs here via wasmoon (Lua compiled to WebAssembly) on the Node runtime.
//
// Optional persistence: if DATABASE_URL is set (Neon / Supabase / any Postgres),
// each obfuscation is stored. The feature is best-effort and never blocks the
// response, so no database is required for the endpoint to work.

import { LuaFactory } from "wasmoon"
import luaSources from "./_generated/luaSources.json"

export const config = { runtime: "nodejs", maxDuration: 60 }

// Only presets verified reliable across varied inputs are accepted; any other
// request falls back to Medium so the endpoint never runs a flaky pipeline.
const ALLOWED_PRESETS = ["Minify", "Weak", "Medium"]
const ALLOWED_LUA = ["Lua51", "LuaU"]
const MAX_SOURCE_BYTES = 2 * 1024 * 1024 // 2 MB upload cap

const sources = luaSources as Record<string, string>

function luaLong(s: string): string {
  let eq = ""
  while (s.includes(`]${eq}]`) || s.includes(`[${eq}[`)) eq += "="
  return `[${eq}[\n${s}]${eq}]`
}

async function obfuscate(opts: {
  source: string
  filename: string
  preset: string
  luaVersion: string
  prettyPrint: boolean
  seed: number
}): Promise<{ ok: true; output: string } | { ok: false; error: string }> {
  const factory = new LuaFactory()
  // Mount every Prometheus Lua module into the in-memory FS at /lua/<path>.lua
  // so `require("prometheus.steps.Cff")` resolves via package.path.
  for (const [name, src] of Object.entries(sources)) {
    await factory.mountFile(`/lua/${name.split(".").join("/")}.lua`, src)
  }
  await factory.mountFile("/lua/__input.lua", opts.source)

  const lua = await factory.createEngine({ openStandardLibs: true })
  try {
    const program = `
package.path = "/lua/?.lua;/lua/?/init.lua"
_G.arg = _G.arg or {}
-- Cross-version shims: the engine is Lua 5.4 but the obfuscator targets 5.1.
if not unpack then unpack = table.unpack end
if not table.unpack then table.unpack = unpack end
if not math.log10 then math.log10 = function(v) return math.log(v, 10) end end

local Prometheus = require("prometheus")
Prometheus.Logger.logLevel = Prometheus.Logger.LogLevel.Error
Prometheus.colors.enabled = false

local fh = io.open("/lua/__input.lua", "r")
local source = fh:read("*a")
fh:close()

local config = {}
for k, v in pairs(Prometheus.Presets[ ${luaLong(opts.preset)} ]) do config[k] = v end
config.LuaVersion = ${luaLong(opts.luaVersion)}
config.PrettyPrint = ${opts.prettyPrint ? "true" : "false"}
config.Seed = ${Math.max(1, Math.floor(opts.seed))}

local ok, out = xpcall(function()
  return Prometheus.Pipeline:fromConfig(config):apply(source, ${luaLong(opts.filename)})
end, function(e) return tostring(e) end)

return { ok = ok, output = ok and out or "", error = ok and "" or out }
`
    const result = (await lua.doString(program)) as {
      ok?: unknown
      output?: unknown
      error?: unknown
    }
    if (result.ok === false) {
      return { ok: false, error: String(result.error ?? "Obfuscation failed") }
    }
    return { ok: true, output: String(result.output ?? "") }
  } finally {
    lua.global.close()
  }
}

async function persist(record: {
  filename: string
  preset: string
  luaVersion: string
  original: string
  obfuscated: string
}): Promise<void> {
  if (!process.env.DATABASE_URL) return
  try {
    // Dynamically import so the endpoint works with or without `pg` installed.
    const pg = await import("pg").catch(() => null)
    if (!pg) return
    const { Client } = pg as typeof import("pg")
    const client = new Client({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false },
    })
    await client.connect()
    try {
      await client.query(
        `CREATE TABLE IF NOT EXISTS obfuscations (
          id BIGSERIAL PRIMARY KEY,
          filename TEXT,
          preset TEXT,
          lua_version TEXT,
          original_size INT,
          obfuscated_size INT,
          original TEXT,
          obfuscated TEXT,
          created_at TIMESTAMPTZ DEFAULT now()
        )`,
      )
      await client.query(
        `INSERT INTO obfuscations
          (filename, preset, lua_version, original_size, obfuscated_size, original, obfuscated)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [
          record.filename,
          record.preset,
          record.luaVersion,
          record.original.length,
          record.obfuscated.length,
          record.original,
          record.obfuscated,
        ],
      )
    } finally {
      await client.end()
    }
  } catch (err) {
    // Persistence is best-effort; never fail the request because of it.
    console.error("obfuscation persist failed:", err)
  }
}

export default async function handler(req: any, res: any) {
  res.setHeader("Access-Control-Allow-Origin", "*")
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS")
  res.setHeader("Access-Control-Allow-Headers", "Content-Type")

  if (req.method === "OPTIONS") {
    res.status(204).end()
    return
  }
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "Method not allowed. Use POST." })
    return
  }

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body ?? {}
    const source = typeof body.source === "string" ? body.source : ""
    if (!source) {
      res.status(400).json({ ok: false, error: "Missing 'source' (the Lua script to obfuscate)." })
      return
    }
    if (Buffer.byteLength(source, "utf8") > MAX_SOURCE_BYTES) {
      res.status(413).json({ ok: false, error: "Script too large (max 2 MB)." })
      return
    }

    const preset = ALLOWED_PRESETS.includes(body.preset) ? body.preset : "Medium"
    const luaVersion = ALLOWED_LUA.includes(body.luaVersion) ? body.luaVersion : "Lua51"
    const prettyPrint = body.prettyPrint === true
    const seed = Number.isFinite(body.seed) ? Number(body.seed) : Math.floor(Math.random() * 1e9) + 1
    const filename = typeof body.filename === "string" && body.filename ? body.filename : "upload.lua"

    const result = await obfuscate({ source, filename, preset, luaVersion, prettyPrint, seed })
    if (!result.ok) {
      res.status(422).json({ ok: false, error: result.error, preset })
      return
    }

    await persist({ filename, preset, luaVersion, original: source, obfuscated: result.output })

    res.status(200).json({
      ok: true,
      preset,
      luaVersion,
      filename,
      originalSize: source.length,
      obfuscatedSize: result.output.length,
      output: result.output,
    })
  } catch (err) {
    res.status(500).json({ ok: false, error: err instanceof Error ? err.message : String(err) })
  }
}
