import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool recording: false
  property bool loggedIn: false
  property bool hasWindow: false
  property int pid: 0
  property string version: ""
  property string launcher: ""
  property string statusText: "Checking…"
  property string kind: "missing"
  property string lastError: ""
  property string actionStatus: ""
  property bool refreshing: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 60)
  readonly property int pollMs: (kind === "recording" ? 2 : refreshIntervalSec) * 1000
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property string helperPath: String(Qt.resolvedUrl("scripts/status.py")).replace("file://", "")

  property string _statusOutput: ""
  property string _statusError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (parsed.ok === false) {
      lastError = parsed.lastError || "Failed to read Granola status"
      return
    }
    installed = parsed.installed === true
    running = parsed.running === true
    recording = parsed.recording === true
    loggedIn = parsed.loggedIn === true
    hasWindow = parsed.hasWindow === true
    pid = Number(parsed.pid || 0)
    version = String(parsed.version || "")
    launcher = String(parsed.launcher || "")
    statusText = String(parsed.statusText || (installed ? "Installed" : "Not installed"))
    kind = String(parsed.kind || "missing")
    lastError = String(parsed.lastError || "")
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function runAction(action) {
    if (actionProcess.running || helperPath === "") return
    actionProcess.command = ["python3", helperPath, action]
    actionProcess.running = true
  }

  function openApp() {
    runAction("open")
  }

  function installApp() {
    runAction("install")
  }

  function quitApp() {
    runAction("quit")
  }

  function toggleRunning() {
    if (!installed) installApp()
    else if (running) quitApp()
    else openApp()
  }

  Timer {
    id: refreshTimer
    interval: Math.max(2000, root.pollMs)
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (stdout !== "") root.applyStatus(stdout)
      else root.lastError = root.elideStatus(stderr || "Could not read Granola status")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || "")
      var stderr = String(actionStderr.text || "")
      var parsed = Model.parseStatus(stdout)
      if (exitCode !== 0 || parsed.ok === false) {
        root.lastError = root.elideStatus(parsed.lastError || stderr || stdout || "Granola command failed")
        root.actionStatus = root.lastError
      } else {
        root.lastError = ""
        root.actionStatus = parsed.statusText || ""
        if (root.actionStatus !== "") actionStatusTimer.restart()
        root.applyStatus(stdout)
      }
      delayedRefresh.restart()
    }
  }
}
