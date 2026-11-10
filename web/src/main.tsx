import { StrictMode, useEffect, useState } from "react"
import { createRoot } from "react-dom/client"

import App from "./App"
import ScriptUploadPage from "./ScriptUploadPage"
import "./index.css"

function Router() {
  const [hash, setHash] = useState(() => window.location.hash)
  useEffect(() => {
    const onHashChange = () => setHash(window.location.hash)
    window.addEventListener("hashchange", onHashChange)
    return () => window.removeEventListener("hashchange", onHashChange)
  }, [])

  if (hash === "#/upload") {
    return <ScriptUploadPage />
  }
  return <App />
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Router />
  </StrictMode>,
)

// Register the service worker so the app is installable and works offline.
// Only in production builds served over http(s) (not during `file://` or dev).
if ("serviceWorker" in navigator && import.meta.env.PROD && location.protocol.startsWith("http")) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {
      // Offline support is a progressive enhancement; ignore registration errors.
    })
  })
}
