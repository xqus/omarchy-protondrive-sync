function parseEventLine(line) {
  var text = String(line || "").trim()
  if (text === "") return null
  try {
    return JSON.parse(text)
  } catch (e) {
    return null
  }
}

function activityGlyph(action) {
  if (action === "uploaded") return "󰤒"
  if (action === "downloaded") return "󰇚"
  if (action === "deleted-local" || action === "deleted-remote") return "󰩹"
  if (action === "created-local-dir" || action === "created-remote-dir") return "󰉖"
  if (action === "conflict") return "󰀦"
  if (action === "error") return "󰅚"
  return "󰈔"
}

function activityLabel(entry) {
  if (!entry) return ""
  var action = entry.action || ""
  var path = entry.path || ""
  if (action === "uploaded") return "Uploaded " + path
  if (action === "downloaded") return "Downloaded " + path
  if (action === "deleted-local") return "Removed locally: " + path
  if (action === "deleted-remote") return "Removed on Proton Drive: " + path
  if (action === "created-local-dir") return "Created local folder: " + path
  if (action === "created-remote-dir") return "Created Proton Drive folder: " + path
  if (action === "conflict") return "Conflict on " + path + (entry.detail ? " (" + entry.detail + ")" : "")
  if (action === "error") return "Error on " + (path || "sync") + (entry.detail ? ": " + entry.detail : "")
  return path || action
}

function relativeTime(epochSeconds, nowMs) {
  var ts = Number(epochSeconds || 0)
  if (!isFinite(ts) || ts <= 0) return "never"
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - ts * 1000) / 1000))
  if (diff < 5) return "just now"
  if (diff < 60) return diff + "s ago"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  return days + "d ago"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEventLine: parseEventLine,
    activityGlyph: activityGlyph,
    activityLabel: activityLabel,
    relativeTime: relativeTime
  }
}
