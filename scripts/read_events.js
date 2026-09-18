"use strict"

const fs = require("fs")
const path = require("path")
const Database = require(process.env.GRANOLA_BS3)

const dbPath = process.argv[2]
const keyHex = fs.readFileSync(0, "utf8").trim()
if (!dbPath || !keyHex) {
  process.stderr.write("usage: read_events.js <granola.db> < keyhex\n")
  process.exit(2)
}

const db = new Database(dbPath, { readonly: true, fileMustExist: true })
db.pragma("cipher = 'sqlcipher'")
db.pragma("legacy = 4")
db.pragma(`key = "x'${keyHex}'"`)

const now = new Date().toISOString()
const rows = db.prepare(
  "SELECT start_time, end_time, data FROM calendar_events WHERE end_time >= ? ORDER BY start_time ASC LIMIT 8"
).all(now)

function shortenLocation(text) {
  const value = String(text || "").trim()
  if (!value) return ""
  const lower = value.toLowerCase()
  if (lower.includes("microsoft teams") || lower.includes("teams.microsoft")) return "Microsoft Teams"
  if (lower.includes("meet.google") || lower.includes("google meet")) return "Google Meet"
  if (lower.includes("zoom.us") || /\bzoom\b/i.test(value)) return "Zoom"
  return value
}

function locationOf(data) {
  if (typeof data.location === "string" && data.location.trim()) return shortenLocation(data.location)
  const display = data.displayLocations
  if (display && Array.isArray(display.entries) && display.entries[0] && display.entries[0].text)
    return shortenLocation(display.entries[0].text)
  if (Array.isArray(display) && display[0]) {
    if (typeof display[0] === "string") return shortenLocation(display[0])
    if (display[0].text) return shortenLocation(display[0].text)
  }
  const rooms = data.roomNames
  if (Array.isArray(rooms) && rooms[0]) return shortenLocation(rooms[0])
  const conference = data.conferenceData
  if (conference && (conference.conferenceId || conference.entryPoints)) return "Google Meet"
  return ""
}

function peopleOf(data) {
  const names = []
  const attendees = Array.isArray(data.attendees) ? data.attendees : []
  for (const person of attendees) {
    if (!person || person.self) continue
    const name = person.displayName || (person.email ? String(person.email).split("@")[0] : "")
    if (name) names.push(name)
  }
  const organizer = data.organizer
  if (organizer && !organizer.self) {
    const name = organizer.displayName || (organizer.email ? String(organizer.email).split("@")[0] : "")
    if (name && !names.includes(name)) names.unshift(name)
  }
  return names
}

const events = []
for (const row of rows) {
  let data = {}
  try {
    data = JSON.parse(row.data)
  } catch {
    data = {}
  }
  events.push({
    id: data.id || "",
    title: String(data.summary || data.title || "Untitled"),
    start: row.start_time,
    end: row.end_time,
    location: locationOf(data),
    people: peopleOf(data)
  })
}
db.close()
process.stdout.write(JSON.stringify({ events, recordingHint: false }))
