// Layout — the preview twin of the python geometry engine.
//
// bin/scratchpad-studio `layout_rects` is the source of truth (pinned by
// tests/); this mirrors it so the wizard's live preview and the generated
// rules can never disagree. Same inputs (anchor, sizePct, marginPx, layout,
// usable px), same outputs (x, y, w, h per app slot).

.pragma library

var GAP_MIN_PX = 6
var LAYOUTS = [
  { id: "single",    label: "Single",   hint: "One window" },
  { id: "pair",      label: "Pair",     hint: "Two side by side" },
  { id: "stacked",   label: "Stacked",  hint: "Overlaid, swap by focus" },
  { id: "three-up",  label: "Three-up", hint: "Three columns" },
  { id: "grid",      label: "Grid",     hint: "Two per row" }
]

function baseRect(sp, usableW, usableH) {
  var w = Math.max(200, Math.round(usableW * sp.sizePct.w / 100))
  var h = Math.max(140, Math.round(usableH * sp.sizePct.h / 100))
  var margin = sp.marginPx
  var x, y
  if (sp.anchor === "top") { x = Math.floor((usableW - w) / 2); y = margin }
  else if (sp.anchor === "bottom") { x = Math.floor((usableW - w) / 2); y = usableH - margin - h }
  else if (sp.anchor === "left") { x = margin; y = Math.floor((usableH - h) / 2) }
  else if (sp.anchor === "right") { x = usableW - margin - w; y = Math.floor((usableH - h) / 2) }
  else { x = Math.floor((usableW - w) / 2); y = Math.floor((usableH - h) / 2) } // center
  return { x: x, y: y, w: w, h: h }
}

function rects(sp, count, usableW, usableH) {
  var base = baseRect(sp, usableW, usableH)
  count = Math.max(1, count)
  var gap = Math.max(GAP_MIN_PX, Math.floor(sp.marginPx / 2))
  var layout = sp.layout

  if (layout === "stacked" || count === 1 || layout === "single") {
    var full = [base.x, base.y, base.w, base.h]
    var out = []
    for (var i = 0; i < count; i++) out.push(full)
    return out
  }

  if (layout === "wide-left" || layout === "wide-right") {
    // One window spans its half; the rest stack in the other half.
    if (count === 1) return [base]
    var tallLeft = layout === "wide-left"
    var half = Math.floor((base.w - gap) / 2)
    var stackCount = count - 1
    var stackW = base.w - half - gap
    var stackH = Math.floor((base.h - gap * (stackCount - 1)) / stackCount)
    var wideOut = []
    for (var wi = 0; wi < count; wi++) {
      var tall = tallLeft ? wi === 0 : wi === count - 1
      var pos = tallLeft ? wi - 1 : wi
      if (tall)
        wideOut.push([tallLeft ? base.x : base.x + base.w - half, base.y, half, base.h])
      else
        wideOut.push([tallLeft ? base.x + base.w - stackW : base.x,
                      base.y + pos * (stackH + gap), stackW, stackH])
    }
    return wideOut
  }

  var columns = layout === "pair" ? 2 : layout === "three-up" ? 3 : 2
  var rows = Math.ceil(count / columns)
  var cellW = Math.floor((base.w - gap * (columns - 1)) / columns)
  var cellH = Math.floor((base.h - gap * (rows - 1)) / rows)
  var rectsOut = []
  for (var index = 0; index < count; index++) {
    var col = index % columns
    var row = Math.floor(index / columns)
    rectsOut.push([
      base.x + col * (cellW + gap),
      base.y + row * (cellH + gap),
      cellW,
      cellH
    ])
  }
  return rectsOut
}

// Fractional layout of slot rectangles for thumbnails: normalized 0..1
// boxes inside the scratchpad frame, gap included.
function thumbBoxes(layout, count) {
  if (layout === "single") return [{ x: 0.04, y: 0.04, w: 0.92, h: 0.92 }]
  if (layout === "wide-left" || layout === "wide-right") {
    var n = Math.max(2, Math.min(count, 4))
    var tallLeft = layout === "wide-left"
    var out = []
    for (var i = 0; i < n; i++) {
      var tall = tallLeft ? i === 0 : i === n - 1
      if (tall)
        out.push(tallLeft ? { x: 0.04, y: 0.04, w: 0.42, h: 0.92 }
                          : { x: 0.54, y: 0.04, w: 0.42, h: 0.92 })
      else {
        var pos = tallLeft ? i - 1 : i
        var rows = n - 1
        var ch = (0.92 - 0.06 * (rows - 1)) / rows
        out.push({ x: tallLeft ? 0.54 : 0.04, y: 0.04 + pos * (ch + 0.06), w: 0.42, h: ch })
      }
    }
    return out
  }
  var columns = layout === "pair" ? 2 : layout === "three-up" ? 3 : 2
  if (layout === "stacked" || count <= 1) {
    return [{ x: 0.30, y: 0.16, w: 0.44, h: 0.56 },
            { x: 0.24, y: 0.24, w: 0.44, h: 0.56 },
            { x: 0.18, y: 0.32, w: 0.44, h: 0.56 }].slice(0, Math.max(1, count))
  }
  count = Math.max(1, count)
  var rows = Math.ceil(count / columns)
  var out = []
  for (var index = 0; index < count; index++) {
    var col = index % columns
    var row = Math.floor(index / columns)
    var cw = (1 - 0.08) / columns
    var ch = (1 - 0.08) / rows
    out.push({ x: 0.04 + col * cw, y: 0.04 + row * ch, w: cw - 0.04, h: ch - 0.04 })
  }
  return out
}

// Editor slot boxes: where each app's card sits in the layout editor
// canvas. For distinct-slot layouts (pair/three-up/grid) these are the true
// rects() geometry, so what you edit is what you get. For "single" and
// "stacked" — where every window really overlays the same rect — the cards
// cascade so each stays visible, grabbable and reorderable; the caption in
// the editor says so, and the honest overlap is still drawn in the small
// monitor preview on the card/summary. Returned in logical px like rects().
var CASCADE_STEP_PX = 44
var CASCADE_INSET_PX = 26

function editorSlotBoxes(sp, count, usableW, usableH) {
  count = Math.max(1, count)
  var trueRects = rects(sp, count, usableW, usableH)
  if (sp.layout !== "single" && sp.layout !== "stacked") return trueRects
  var out = []
  for (var i = 0; i < count; i++) {
    var r = trueRects[0]
    var inset = Math.min(CASCADE_INSET_PX * i, r[2] * 0.3)
    out.push([
      r[0] + CASCADE_STEP_PX * i,
      r[1] + CASCADE_STEP_PX * i,
      r[2] - inset * 2,
      r[3] - inset * 2
    ])
  }
  return out
}
