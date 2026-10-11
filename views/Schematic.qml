import QtQuick
import Quickshell
import qs.Commons

// Schematic — a live, to-scale map of the windows inside one scratchpad.
//
// Screencopy can't see windows on a hidden special workspace (they are not
// composited), so the honest preview is the real geometry: window rectangles
// from hyprctl clients, drawn to scale, each with its app icon. Overlaps are
// real (a "stacked" scratchpad really does stack) and z follows window order.
Item {
  id: root

  property var windows: []          // [{class,title,x,y,w,h}]
  property bool demo: false
  property color fill: Qt.alpha(Color.foreground, 0.05)
  property color fillActive: Qt.alpha(Color.accent, 0.16)
  property color stroke: Color.popups.border

  // Bounds of the drawn geometry, in window coordinates. Empty windows list
  // falls back to a soft placeholder the parent overlays text on.
  readonly property bool hasContent: windows.length > 0
  readonly property real geoX: {
    if (!hasContent) return 0
    var m = Number.POSITIVE_INFINITY
    for (var i = 0; i < windows.length; i++) m = Math.min(m, windows[i].x)
    return m
  }
  readonly property real geoY: {
    if (!hasContent) return 0
    var m = Number.POSITIVE_INFINITY
    for (var i = 0; i < windows.length; i++) m = Math.min(m, windows[i].y)
    return m
  }
  readonly property real geoW: {
    if (!hasContent) return 1
    var lo = Number.POSITIVE_INFINITY, hi = Number.NEGATIVE_INFINITY
    for (var i = 0; i < windows.length; i++) {
      lo = Math.min(lo, windows[i].x); hi = Math.max(hi, windows[i].x + windows[i].w)
    }
    return Math.max(1, hi - lo)
  }
  readonly property real geoH: {
    if (!hasContent) return 1
    var lo = Number.POSITIVE_INFINITY, hi = Number.NEGATIVE_INFINITY
    for (var i = 0; i < windows.length; i++) {
      lo = Math.min(lo, windows[i].y); hi = Math.max(hi, windows[i].y + windows[i].h)
    }
    return Math.max(1, hi - lo)
  }
  readonly property real pad: Style.space(2)
  readonly property real scale: hasContent
    ? Math.min((width - pad * 2) / geoW, (height - pad * 2) / geoH) : 1

  function sx(x) { return pad + (x - geoX) * scale }
  function sy(y) { return pad + (y - geoY) * scale }

  Repeater {
    model: root.windows

    Rectangle {
      required property var modelData
      required property int index
      readonly property var win: modelData

      x: root.sx(win.x)
      y: root.sy(win.y)
      width: Math.max(Style.space(6), win.w * root.scale)
      height: Math.max(Style.space(6), win.h * root.scale)
      radius: Math.min(Style.cornerRadius, height / 5)
      color: win.focused ? root.fillActive : root.fill
      border.width: 1
      border.color: root.stroke
      z: index

      // Icon when there is room; a dot when there is not.
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(2, parent.height * 0.06)
        width: Math.min(parent.width * 0.5, parent.height * 0.34, Style.space(34))
        height: width
        visible: width >= Style.space(12)

        Image {
          id: appIcon
          anchors.fill: parent
          anchors.margins: parent.width * 0.08
          source: {
            var entry = DesktopEntries.heuristicLookup(String(win.class || ""))
            return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
          }
          fillMode: Image.PreserveAspectFit
          smooth: true
          visible: status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          visible: !appIcon.visible
          text: initials(String(win.class || "?"))
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: parent.width * 0.5
          renderType: Text.NativeRendering
        }
      }
    }
  }

  function initials(text) {
    var parts = text.split(/[\s_\-:.]+/).filter(function (p) { return p.length > 0 })
    if (parts.length === 0) return "?"
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
    return (parts[0][0] + parts[1][0]).toUpperCase()
  }
}
