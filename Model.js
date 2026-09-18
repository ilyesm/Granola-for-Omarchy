.pragma library

function defaultStatus() {
  return {
    ok: true,
    installed: false,
    running: false,
    recording: false,
    loggedIn: false,
    hasWindow: false,
    pid: 0,
    pids: [],
    launcher: "",
    version: "",
    statusText: "Unavailable",
    kind: "missing",
    lastError: "",
    nextEvent: null
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    parsed.pids = Array.isArray(parsed.pids) ? parsed.pids : []
    if (!parsed.nextEvent || typeof parsed.nextEvent !== "object") parsed.nextEvent = null
    return parsed
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse Granola status"
    return failed
  }
}

function eventTitle(event) {
  if (!event) return ""
  return String(event.title || "")
}

function eventWhen(event) {
  if (!event) return ""
  return String(event.when || "")
}

function kindLabel(kind) {
  if (kind === "recording") return "Recording"
  if (kind === "upcoming") return "Coming up"
  if (kind === "running") return "Running"
  if (kind === "idle") return "Ready"
  return "Not installed"
}
