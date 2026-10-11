// Studio state — the JSON file is the source of truth for what the plugin
// manages, the helper CLI regenerates Hyprland config from it, and the GUI
// edits it through the CLI (`scratchpad-studio` never parses Lua in QML).
//
// Pure data functions only: no Quickshell imports, so the Node/bun-free test
// story stays simple and the same code runs in the demo mode and live.

.pragma library

var STATE_VERSION = 1

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function defaultState() {
  return { version: STATE_VERSION, scratchpads: [] }
}

// Accept anything shaped like a state file; missing fields get defaults so
// the GUI can render a card the moment the file gains a new field.
function normalizeState(raw) {
  var state = defaultState()
  if (raw && typeof raw === "object") {
    if (raw.version) state.version = raw.version
    if (Array.isArray(raw.scratchpads)) state.scratchpads = raw.scratchpads.map(normalizeScratchpad)
  }
  return state
}

function normalizeScratchpad(sp) {
  var out = {
    id: slug(String((sp && sp.id) || "")),
    name: String((sp && sp.name) || "Scratchpad"),
    icon: String((sp && sp.icon) || ""),
    keybind: String((sp && sp.keybind) || ""),
    anchor: oneOf(sp && sp.anchor, ["top", "bottom", "left", "right"], "top"),
    layout: oneOf(sp && sp.layout, ["single", "pair", "stacked", "three-up", "grid"], "single"),
    transition: oneOf(sp && sp.transition, ["down", "up", "right", "left"], "down"),
    sizePct: {
      w: clampPct(sp && sp.sizePct && sp.sizePct.w, 30, 95, 60),
      h: clampPct(sp && sp.sizePct && sp.sizePct.h, 25, 95, 50)
    },
    marginPx: clampInt(sp && sp.marginPx, 0, 128, 12),
    apps: Array.isArray(sp && sp.apps) ? sp.apps.map(normalizeApp) : []
  }
  return out
}

function normalizeApp(app) {
  return {
    name: String((app && app.name) || "App"),
    command: String((app && app.command) || ""),
    class: String((app && app.class) || ""),
    webapp: !!(app && app.webapp),
    singleInstance: app && app.singleInstance !== undefined ? !!app.singleInstance : false
  }
}

function slug(text) {
  var s = String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return s.length > 0 ? s.slice(0, 32) : "scratchpad"
}

function oneOf(value, allowed, fallback) {
  return allowed.indexOf(value) >= 0 ? value : fallback
}

function clampPct(value, lo, hi, fallback) {
  var n = Number(value)
  if (!isFinite(n)) n = fallback
  return Math.min(hi, Math.max(lo, Math.round(n)))
}

function clampInt(value, lo, hi, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) n = fallback
  return Math.min(hi, Math.max(lo, n))
}

// ---------------------------------------------------------------------------
// Demo data — fake scratchpads with plausible shapes and made-up window
// titles, so screenshots never contain anything real (captain's requirement).
// ---------------------------------------------------------------------------

function demoState() {
  return normalizeState({
    version: STATE_VERSION,
    scratchpads: [
      {
        id: "browsing",
        name: "Browsing",
        icon: "󰈹",
        keybind: "SUPER + B",
        anchor: "right",
        layout: "pair",
        transition: "left",
        sizePct: { w: 72, h: 80 },
        apps: [
          { name: "Atlas", command: "atlas", class: "atlas", webapp: false, singleInstance: false },
          { name: "Notes", command: "notes", class: "notes", webapp: false, singleInstance: true }
        ]
      },
      {
        id: "ai",
        name: "AI",
        icon: "󰚩",
        keybind: "SUPER + A",
        anchor: "bottom",
        layout: "single",
        transition: "up",
        sizePct: { w: 50, h: 55 },
        apps: [
          { name: "Sage", command: "sage --app=https://sage.example", class: "chrome-sage.example__-Default", webapp: true, singleInstance: true }
        ]
      },
      {
        id: "music",
        name: "Music",
        icon: "󰎈",
        keybind: "SUPER + M",
        anchor: "top",
        layout: "stacked",
        transition: "down",
        sizePct: { w: 60, h: 45 },
        apps: [
          { name: "Nebula Player", command: "nebula", class: "nebula", webapp: false, singleInstance: true }
        ]
      }
    ]
  })
}

// Fake live windows per demo scratchpad id. Titles are invented on purpose.
function demoWindows(scratchpadId) {
  var byId = {
    browsing: [
      { class: "atlas", title: "Field guide — Atlas", x: 40, y: 60, w: 520, h: 640 },
      { class: "notes", title: "Trail notes", x: 580, y: 60, w: 280, h: 640 }
    ],
    ai: [
      { class: "chrome-sage.example__-Default", title: "Sage — new thread", x: 120, y: 180, w: 760, h: 480 }
    ],
    music: [
      { class: "nebula", title: "Nebula — Long Static", x: 200, y: 40, w: 560, h: 360 }
    ]
  }
  return byId[scratchpadId] || []
}
