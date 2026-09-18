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
    nextEvent: null,
    nowEvent: null,
    upcoming: [],
    appVersion: "",
    latestVersion: "",
    updateAvailable: false
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    parsed.pids = Array.isArray(parsed.pids) ? parsed.pids : []
    parsed.upcoming = Array.isArray(parsed.upcoming) ? parsed.upcoming : []
    if (!parsed.nextEvent || typeof parsed.nextEvent !== "object") parsed.nextEvent = null
    if (!parsed.nowEvent || typeof parsed.nowEvent !== "object") parsed.nowEvent = null
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

function eventCaption(event) {
  if (!event) return ""
  var parts = []
  if (event.when) parts.push(event.when)
  if (event.location) parts.push(event.location)
  return parts.join(" · ")
}

function relativeLabel(event, nowMs) {
  if (!event) return ""
  var start = Date.parse(event.start)
  var end = Date.parse(event.end)
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  if (!isFinite(start) || !isFinite(end) || !isFinite(now)) return event.when || ""
  if (now >= start && now <= end) return "Now"
  if (now < start) {
    var minutes = Math.round((start - now) / 60000)
    if (minutes < 1) return "Starting"
    if (minutes < 60) return "In " + minutes + " min"
    var hours = Math.round(minutes / 60)
    if (hours < 24) return "In " + hours + "h"
  }
  return event.when || ""
}

function kindLabel(kind) {
  if (kind === "recording") return "Recording"
  if (kind === "upcoming") return "Coming up"
  if (kind === "running") return "Running"
  if (kind === "idle") return "Ready"
  return "Not installed"
}
