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
    location: Array.isArray(data.displayLocations) && data.displayLocations[0]
      ? String(data.displayLocations[0])
      : (data.location ? String(data.location) : ""),
    data: row.data
  })
}
const cutoff = new Date(Date.now() - 3 * 60 * 1000).toISOString()
const recent = db.prepare(
  "SELECT COUNT(*) AS c FROM documents WHERE created_at >= ?"
).get(cutoff)
db.close()
process.stdout.write(JSON.stringify({ events, recordingHint: Number(recent && recent.c) > 0 }))
