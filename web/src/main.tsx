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
