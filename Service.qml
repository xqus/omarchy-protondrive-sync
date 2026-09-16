import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME")

  function urlToPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    return decodeURIComponent(s)
  }

  // Qt.resolvedUrl resolves relative to *this* QML file's own location, so
  // this plugin finds its bundled daemon regardless of where
  // `omarchy plugin add` actually cloned it on disk.
  readonly property string pluginDir: urlToPath(Qt.resolvedUrl("."))
  readonly property string daemonPath: pluginDir + "bin/protondrive-sync"
  readonly property string stateFile: home + "/.local/state/omarchy/protondrive-sync/state.json"

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

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value === "") return ""
    if (value === "~") return home
    if (value.indexOf("~/") === 0) return home + value.substring(1)
    if (value.indexOf("$HOME/") === 0) return home + value.substring(5)
    if (value.charAt(0) !== "/") return home + "/" + value
    return value
  }

  readonly property string localFolderRaw: String(setting("localFolder", ""))
  readonly property string localFolder: expandPath(localFolderRaw)
  readonly property string remoteFolder: String(setting("remoteFolder", "/my-files/Sync"))
  readonly property int pollIntervalSec: intSetting("pollIntervalSec", 120, 30, 3600)
  readonly property string conflictStrategyLabel: String(setting("conflictStrategy", "Keep both (rename)"))
  readonly property string conflictStrategyArg:
    conflictStrategyLabel.indexOf("local") >= 0 ? "local" :
    (conflictStrategyLabel.indexOf("remote") >= 0 ? "remote" : "rename")

  readonly property bool configured: localFolder !== "" && remoteFolder !== ""

  property bool cliInstalled: false
  property bool inotifyInstalled: false
  property bool authenticated: false
  property bool checked: false
  readonly property bool ready: cliInstalled && authenticated && configured

  property bool running: false
  property bool paused: false
  property real lastSyncTs: 0
  property int trackedFiles: 0
  property string lastError: ""
  property var activity: []

  readonly property bool active: running && !paused
  readonly property bool busy: loginProcess.running
  readonly property int activityLimit: 50

  function pushActivity(entry) {
    var next = activity.slice()
    next.unshift(entry)
    if (next.length > activityLimit) next.length = activityLimit
    activity = next
  }

  function handleEvent(line) {
    var text = String(line || "").trim()
    if (text === "") return
    var obj
    try {
      obj = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!obj || typeof obj !== "object") return

    if (obj.type === "ready") {
      lastError = ""
    } else if (obj.type === "state") {
      if (obj.paused !== undefined) paused = !!obj.paused
      if (obj.trackedFiles !== undefined) trackedFiles = obj.trackedFiles
      lastSyncTs = obj.ts || (Date.now() / 1000)
    } else if (obj.type === "activity") {
      pushActivity(obj)
      if (obj.action === "error") lastError = obj.detail || obj.path || "sync error"
      else if (obj.action === "conflict") lastError = ""
    } else if (obj.type === "error") {
      lastError = obj.message || "sync error"
    }
  }

  function start() {
    if (!ready || daemonProcess.running) return
    daemonProcess.command = [
      "python3", daemonPath,
      "--local", localFolder,
      "--remote", remoteFolder,
      "--poll-interval", String(pollIntervalSec),
      "--conflict-strategy", conflictStrategyArg,
      "--state-file", stateFile
    ]
    daemonProcess.running = true
  }

  function stop() {
    if (daemonProcess.running) daemonProcess.running = false
  }

  function restart() {
    stop()
    Qt.callLater(start)
  }

  function toggleRunning() {
    if (!daemonProcess.running) {
      start()
      return
    }
    if (paused) daemonProcess.write("resume\n")
    else daemonProcess.write("pause\n")
  }

  function syncNow() {
    if (daemonProcess.running) daemonProcess.write("sync-now\n")
  }

  function refresh() {
    if (!checkProcess.running) checkProcess.running = true
  }

  function login() {
    if (loginProcess.running) return
    loginProcess.running = true
  }

  onLocalFolderChanged: if (running) restart()
  onRemoteFolderChanged: if (running) restart()
  onPollIntervalSecChanged: if (running) restart()
  onConflictStrategyArgChanged: if (running) restart()

  Component.onCompleted: refresh()

  Process {
    id: checkProcess
    running: false
    command: ["bash", "-c",
      "command -v proton-drive >/dev/null 2>&1 && echo yes || echo no; " +
      "command -v inotifywait >/dev/null 2>&1 && echo yes || echo no; " +
      "proton-drive filesystem info /my-files >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.cliInstalled = lines[0] === "yes"
        root.inotifyInstalled = lines[1] === "yes"
        root.authenticated = lines[2] === "yes"
        root.checked = true
        if (root.ready && !daemonProcess.running) root.start()
      }
    }
  }

  Process {
    id: loginProcess
    running: false
    command: ["proton-drive", "auth", "login"]
    onExited: function() { root.refresh() }
  }

  Process {
    id: daemonProcess
    running: false
    stdinEnabled: true
    command: []
    stdout: SplitParser { onRead: function(line) { root.handleEvent(line) } }
    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text !== "") console.warn("protondrive-sync: " + text)
      }
    }
    onRunningChanged: root.running = daemonProcess.running
    onExited: function(exitCode) {
      root.running = false
      if (exitCode !== 0) root.lastError = "protondrive-sync exited unexpectedly (code " + exitCode + ")"
    }
  }
}
