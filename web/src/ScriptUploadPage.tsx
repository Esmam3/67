import { useCallback, useRef, useState } from "react"

import InstallButton from "@/InstallButton"
import { LUA_VERSIONS, PRESETS, type LuaVersion, type PresetName } from "@/lib/prometheusTypes"

type Status =
  | { kind: "idle" }
  | { kind: "uploading"; filename: string }
  | { kind: "done"; filename: string; output: string; originalSize: number; obfuscatedSize: number; preset: string }
  | { kind: "error"; message: string }

interface ObfuscateResponse {
  ok: boolean
  output?: string
  error?: string
  preset?: string
  originalSize?: number
  obfuscatedSize?: number
}

// Presets ordered weakest -> strongest. Default to Medium: it is reliable and
// keeps output size reasonable. Heavier presets are far larger.
const DEFAULT_PRESET: PresetName = "Medium"

export default function ScriptUploadPage() {
  const [preset, setPreset] = useState<PresetName>(DEFAULT_PRESET)
  const [luaVersion, setLuaVersion] = useState<LuaVersion>("Lua51")
  const [status, setStatus] = useState<Status>({ kind: "idle" })
  const [dragging, setDragging] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  const obfuscateFile = useCallback(
    async (file: File) => {
      setStatus({ kind: "uploading", filename: file.name })
      try {
        const source = await file.text()
        const res = await fetch("/api/obfuscate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ source, filename: file.name, preset, luaVersion }),
        })
        const data = (await res.json()) as ObfuscateResponse
        if (!res.ok || !data.ok || typeof data.output !== "string") {
          setStatus({ kind: "error", message: data.error || `Server returned ${res.status}` })
          return
        }
        setStatus({
          kind: "done",
          filename: file.name,
          output: data.output,
          originalSize: data.originalSize ?? source.length,
          obfuscatedSize: data.obfuscatedSize ?? data.output.length,
          preset: data.preset ?? preset,
        })
      } catch (err) {
        setStatus({ kind: "error", message: err instanceof Error ? err.message : String(err) })
      }
    },
    [preset, luaVersion],
  )

  const handleFiles = useCallback(
    (files: FileList | null) => {
      const file = files?.[0]
      if (!file) return
      // Auto-obfuscate immediately on upload.
      void obfuscateFile(file)
    },
    [obfuscateFile],
  )

  const download = useCallback((filename: string, output: string) => {
    const base = filename.replace(/\.lua$/i, "")
    const blob = new Blob([output], { type: "text/plain" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `${base}.obfuscated.lua`
    a.click()
    URL.revokeObjectURL(url)
  }, [])

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-3xl flex-col gap-6 px-4 py-10">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Upload &amp; Obfuscate</h1>
          <p className="text-sm text-muted-foreground">
            Drop a Lua script. It is sent to the server and obfuscated automatically.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <InstallButton />
          <a
            href="#/"
            className="rounded-md border bg-background px-3 py-1.5 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
          >
            Playground
          </a>
        </div>
      </header>

      <div className="grid gap-3 sm:grid-cols-2">
        <label className="space-y-1.5 text-sm">
          <span className="font-medium">Preset</span>
          <select
            value={preset}
            onChange={(e) => setPreset(e.target.value as PresetName)}
            className="w-full rounded-md border bg-background px-3 py-2 text-sm"
          >
            {PRESETS.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </label>
        <label className="space-y-1.5 text-sm">
          <span className="font-medium">Lua version</span>
          <select
            value={luaVersion}
            onChange={(e) => setLuaVersion(e.target.value as LuaVersion)}
            className="w-full rounded-md border bg-background px-3 py-2 text-sm"
          >
            {LUA_VERSIONS.map((v) => (
              <option key={v} value={v}>
                {v}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div
        role="button"
        tabIndex={0}
        onClick={() => inputRef.current?.click()}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") inputRef.current?.click()
        }}
        onDragOver={(e) => {
          e.preventDefault()
          setDragging(true)
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault()
          setDragging(false)
          handleFiles(e.dataTransfer.files)
        }}
        className={`flex cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed px-6 py-14 text-center transition-colors ${
          dragging ? "border-primary bg-primary/5" : "border-muted-foreground/30 hover:border-primary/60"
        }`}
      >
        <p className="text-sm font-medium">Drop a .lua file here, or click to choose</p>
        <p className="text-xs text-muted-foreground">Obfuscation starts automatically after upload</p>
        <input
          ref={inputRef}
          type="file"
          accept=".lua,text/plain"
          className="hidden"
          onChange={(e) => handleFiles(e.target.files)}
        />
      </div>

      {status.kind === "uploading" ? (
        <div className="rounded-md border bg-card px-4 py-3 text-sm">
          Obfuscating <span className="font-medium">{status.filename}</span> with preset{" "}
          <span className="font-medium">{preset}</span>…
        </div>
      ) : null}

      {status.kind === "error" ? (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {status.message}
        </div>
      ) : null}

      {status.kind === "done" ? (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border bg-card px-4 py-3 text-sm">
            <span>
              Obfuscated <span className="font-medium">{status.filename}</span> ({status.preset}) —{" "}
              {status.originalSize.toLocaleString()} → {status.obfuscatedSize.toLocaleString()} bytes
            </span>
            <div className="flex gap-2">
              <button
                onClick={() => void navigator.clipboard?.writeText(status.output)}
                className="rounded-md border bg-background px-3 py-1.5 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
              >
                Copy
              </button>
              <button
                onClick={() => download(status.filename, status.output)}
                className="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
              >
                Download
              </button>
            </div>
          </div>
          <pre className="max-h-[420px] overflow-auto rounded-md border bg-muted/40 p-3 text-xs leading-relaxed">
            <code>{status.output.slice(0, 20000)}{status.output.length > 20000 ? "\n… (truncated preview)" : ""}</code>
          </pre>
        </div>
      ) : null}
    </main>
  )
}
