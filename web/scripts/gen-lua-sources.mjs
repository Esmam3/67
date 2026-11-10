// Generates web/api/_generated/luaSources.json: a { moduleName: source } map of
// every Lua file under the repo's src/, so the serverless obfuscation function
// can bundle the Prometheus sources without filesystem access at runtime.
// Keys match the Vite plugin's module naming (e.g. "prometheus.steps.Cff").
import { readdir, readFile, mkdir, writeFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(here, "../..")
const srcRoot = path.join(repoRoot, "src")
const outDir = path.join(here, "..", "api", "_generated")
const outFile = path.join(outDir, "luaSources.json")

async function findLua(dir) {
  const entries = await readdir(dir, { withFileTypes: true })
  const files = await Promise.all(
    entries.map(async (e) => {
      const abs = path.join(dir, e.name)
      if (e.isDirectory()) return findLua(abs)
      return e.isFile() && e.name.endsWith(".lua") ? [abs] : []
    }),
  )
  return files.flat()
}

function moduleName(abs) {
  const rel = path.relative(srcRoot, abs).split(path.sep).join("/")
  return rel.replace(/\.lua$/, "").split("/").join(".")
}

const modules = {}
for (const abs of await findLua(srcRoot)) {
  modules[moduleName(abs)] = await readFile(abs, "utf8")
}

await mkdir(outDir, { recursive: true })
await writeFile(outFile, JSON.stringify(modules))
console.log(`Wrote ${Object.keys(modules).length} Lua modules to ${path.relative(repoRoot, outFile)}`)
