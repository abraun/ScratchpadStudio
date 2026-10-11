// Live model — merges the managed state with what Hyprland actually has:
// toplevels, workspaces (named specials), and which special is currently
// shown on its monitor. Pure functions over inputs, so QML stays reactive
// (Hyprland.toplevels/workspaces are ObjectModel values that trigger
// re-evaluation) and tests can call the same functions with fixtures.
//
// Card vocabulary:
//   origin "managed"  — created by Scratchpad Studio (state file entry)
//   origin "builtin"  — Omarchy's own special:scratchpad (SUPER+S)
//   origin "foreign"  — any other live special:* workspace (adoptable)

.pragma library

function specialName(workspaceName) {
  var name = String(workspaceName || "")
  return name.indexOf("special:") === 0 ? name.slice("special:".length) : ""
}

// windowsOn(specialName, toplevels) — live windows living on that special.
function windowsOn(spName, toplevels) {
  var out = []
  var items = toplevels || []
  for (var i = 0; i < items.length; i++) {
    var w = items[i]
    var ws = w.workspace
    if (!ws || specialName(ws.name) !== spName) continue
    var ipc = w.lastIpcObject || {}
    if (ipc.mapped === false) continue
    var at = Array.isArray(ipc.at) ? ipc.at : [0, 0]
    var size = Array.isArray(ipc.size) ? ipc.size : [0, 0]
    out.push({
      address: String(w.address || ""),
      class: String(ipc.class || (w.wayland ? w.wayland.appId : "") || "?"),
      title: String(w.title || ""),
      x: at[0], y: at[1], w: size[0], h: size[1],
      focused: !!w.active
    })
  }
  return out
}

function findSpecial(workspaces, spName) {
  var items = workspaces || []
  for (var i = 0; i < items.length; i++) {
    var ws = items[i]
    if (specialName(ws.name) === spName && spName !== "") return ws
  }
  return null
}

// buildCards — the overview grid model. Order: managed scratchpads first
// (state order), then Omarchy's builtin, then other foreign specials
// alphabetically.
function buildCards(state, toplevels, workspaces) {
  var cards = []
  var seen = {}
  var sps = (state && state.scratchpads) || []

  for (var i = 0; i < sps.length; i++) {
    var sp = sps[i]
    seen[sp.id] = true
    cards.push(cardFor(sp, "managed", toplevels, workspaces))
  }

  var builtin = findSpecial(workspaces, "scratchpad")
  if (builtin && !seen["scratchpad"]) {
    seen["scratchpad"] = true
    cards.push(cardFor({
      id: "scratchpad", name: "Omarchy scratchpad", icon: "󰆍",
      keybind: "SUPER + S", anchor: "top", layout: "single", transition: "down",
      sizePct: { w: 60, h: 50 }, marginPx: 12, apps: []
    }, "builtin", toplevels, workspaces))
  }

  var foreign = []
  for (var j = 0; j < (workspaces || []).length; j++) {
    var name = specialName(workspaces[j].name)
    if (name === "" || seen[name]) continue
    seen[name] = true
    foreign.push(cardFor({
      id: name, name: name, icon: "", keybind: "", anchor: "top", layout: "single",
      transition: "down", sizePct: { w: 60, h: 50 }, marginPx: 12, apps: []
    }, "foreign", toplevels, workspaces))
  }
  foreign.sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0 })
  return cards.concat(foreign)
}

function cardFor(sp, origin, toplevels, workspaces) {
  var windows = windowsOn(sp.id, toplevels)
  var ws = findSpecial(workspaces, sp.id)
  var shown = !!(ws && ws.active)
  return {
    id: sp.id,
    name: sp.name,
    icon: sp.icon,
    keybind: sp.keybind,
    anchor: sp.anchor,
    layout: sp.layout,
    transition: sp.transition,
    origin: origin,               // managed | builtin | foreign
    editable: origin === "managed",
    adoptable: origin === "foreign",
    // status: "shown" (special visible), "running" (has windows, hidden),
    // "idle" (no windows yet — first toggle will launch its apps)
    status: shown ? "shown" : (windows.length > 0 ? "running" : "idle"),
    apps: (sp.apps || []).map(function (a) { return a.name }),
    windows: windows
  }
}

// demoCards — same shape, fake live data. `demoWindows(id)` is passed in
// (library scripts have separate scopes; StudioState.demoWindows is the one).
function demoCards(state, demoWindows) {
  var sps = (state && state.scratchpads) || []
  var cards = []
  for (var i = 0; i < sps.length; i++) {
    var sp = sps[i]
    var windows = []
    var raw = demoWindows(sp.id) || []
    for (var j = 0; j < raw.length; j++) {
      windows.push(Object.assign({ address: "demo-" + j, focused: false }, raw[j]))
    }
    // Demo flavor: first card shown, second running, third idle.
    var status = i === 0 ? "shown" : (i === 1 ? "running" : "idle")
    if (windows.length === 0) status = "idle"
    cards.push({
      id: sp.id, name: sp.name, icon: sp.icon, keybind: sp.keybind,
      anchor: sp.anchor, layout: sp.layout, transition: sp.transition,
      origin: "managed", editable: true, adoptable: false,
      status: status, apps: sp.apps.map(function (a) { return a.name }),
      windows: windows
    })
  }
  return cards
}

// statusDot(card) → { color: string, label: string } using palette roles the
// caller maps to theme colors (kept out of the model so themes stay in QML).
function statusLabel(card) {
  if (card.status === "shown") return "shown"
  if (card.status === "running") return "hidden"
  return "empty"
}
