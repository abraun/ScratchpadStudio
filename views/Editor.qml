import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../lib/Layout.js" as LayoutMath

// Editor — the visual layout editor for an existing scratchpad.
//
// Everything edit mode should be, on one screen:
//   - the scratchpad's windows drawn in their saved arrangement on a
//     monitor-true canvas; drag a card onto another slot to rearrange
//     (or Ctrl+←/→), Del removes the app,
//   - apps can be added through the same picker the wizard uses,
//   - the keybind is re-captured right here (with conflict detection —
//     saving rewrites the generated o.bind line wholesale, no orphans),
//   - window placement (arranged in slots vs floating), anchor, size,
//     margin, slide-in and name/icon round out the saved state.
// Saving goes through the helper `upsert`, which merges state, regenerates
// config, reloads, relocates removed apps' windows (never kills them) and
// reflows already-open windows onto their new slots.
Item {
  id: root

  required property var editScratchpad     // the saved scratchpad object
  property bool demo: false
  property var monitor: null               // {width, height, scale}

  signal saved(var scratchpad)
  signal canceled()

  // The draft is this instance's working copy. The panel and the app
  // window each instantiate the editor and each keeps its own draft
  // (JS objects handed through another object's var property arrive as
  // fresh copies on every read — verified live — so a shared draft is
  // not possible). Whichever surface you edit in is self-consistent,
  // and saving writes that surface's copy.
  property var draft: null
  readonly property var original: editScratchpad ? JSON.parse(JSON.stringify(editScratchpad)) : null
  property int selectedSlot: 0
  property bool addingApp: false
  property bool tested: false
  readonly property bool slots: draft && draft.placement !== "floating"
  readonly property int appCount: draft ? draft.apps.length : 0

  Component.onCompleted: {
    draft = editScratchpad ? JSON.parse(JSON.stringify(editScratchpad)) : null
    canvas.forceActiveFocus()
  }
  onVisibleChanged: if (visible) canvas.forceActiveFocus()
  onEditScratchpadChanged: {
    draft = editScratchpad ? JSON.parse(JSON.stringify(editScratchpad)) : null
    selectedSlot = 0
    tested = false
    addingApp = false
    canvas.forceActiveFocus()
  }

  // Closing the add-app overlay (pick, Esc, Done) must hand focus back to
  // the canvas — otherwise later shortcuts (Ctrl+K, Ctrl+Enter, Del) die
  // on a stale focus item and the editor stops responding to keys.
  onAddingAppChanged: {
    if (!addingApp) Qt.callLater(function() { canvas.forceActiveFocus() })
  }

  // Re-assign the draft so var-property bindings (canvas, lists) re-evaluate
  // after a handler mutated it in place — same trick as the wizard.
  function touch() {
    draft = JSON.parse(JSON.stringify(draft))
  }

  function usable() {
    var scale = monitor && monitor.scale ? monitor.scale : 1
    return monitor
      ? [Math.round(monitor.width / scale), Math.round(monitor.height / scale)]
      : [1800, 1125]
  }

  // ---------------- draft mutations ----------------

  function swapSlots(a, b) {
    if (!draft || a === b) return
    if (a < 0 || b < 0 || a >= draft.apps.length || b >= draft.apps.length) return
    var apps = draft.apps
    var tmp = apps[a]
    apps[a] = apps[b]
    apps[b] = tmp
    selectedSlot = b
    touch()
  }

  function moveApp(from, delta) {
    if (!draft) return
    swapSlots(from, from + delta)
  }

  function removeApp(index) {
    if (!draft) return
    draft.apps.splice(index, 1)
    if (selectedSlot >= draft.apps.length)
      selectedSlot = Math.max(0, draft.apps.length - 1)
    touch()
  }

  function addApp(app) {
    if (!draft) return
    for (var i = 0; i < draft.apps.length; i++) {
      if (draft.apps[i].class === app.class) return
    }
    draft.apps.push(app)
    selectedSlot = draft.apps.length - 1
    addingApp = false
    touch()
  }

  function setPlacement(mode) {
    if (!draft) return
    draft.placement = mode
    touch()
  }

  function setLayout(id) {
    if (!draft) return
    draft.layout = id
    touch()
  }

  function setTransition(direction) {
    if (!draft) return
    draft.transition = direction.id
    draft.anchor = direction.anchor
    touch()
  }

  // ---------------- engine bridge ----------------

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("../bin/scratchpad-studio").toString().replace(/^file:\/\//, ""))
  }

  function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'"
  }

  function runHelper(args, stdinPayload) {
    var list = Array.isArray(args) ? args : [args]
    var parts = [JSON.stringify(helperPath())].concat(list.map(shellQuote))
    var command = parts.join(" ")
    if (stdinPayload !== undefined) command += " <<< " + shellQuote(stdinPayload)
    Quickshell.execDetached(["bash", "-c", command + " 2>&1"])
  }

  function save() {
    if (!demo) runHelper("upsert", JSON.stringify(draft))
    saved(draft)
  }

  function testNow() {
    if (demo) return
    // Serialized on purpose: upsert (regenerate → reload → relocate →
    // reflow) must finish BEFORE the toggle reveals the scratchpad —
    // the old fire-and-forget pair raced the reload and the captain saw
    // windows land scattered when testing.
    var upsert = JSON.stringify(helperPath()) + " upsert <<< " + shellQuote(JSON.stringify(draft))
    var toggle = JSON.stringify(helperPath()) + " toggle " + shellQuote(draft.id || "scratchpad")
    Quickshell.execDetached(["bash", "-c", upsert + " && " + toggle + " 2>&1"])
    tested = true
  }

  function cancel() {
    // "Test it now" wrote the draft for real; canceling restores the
    // scratchpad as it was when the editor opened.
    if (tested && original && !demo) runHelper("upsert", JSON.stringify(original))
    canceled()
  }

  // ---------------- chrome ----------------

  readonly property var directions: [
    { id: "down",  label: qsTr("From top"),    glyph: "󰁝", anchor: "top" },
    { id: "up",    label: qsTr("From bottom"), glyph: "󰁅", anchor: "bottom" },
    { id: "right", label: qsTr("From left"),   glyph: "󰁔", anchor: "left" },
    { id: "left",  label: qsTr("From right"),  glyph: "󰁠", anchor: "right" },
    { id: "popin", label: qsTr("Centered"),    glyph: "◎", anchor: "center" }
  ]

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    // ---------- header: identity + chips ----------
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      TextField {
        id: iconField
        Layout.preferredWidth: Style.space(44)
        Layout.preferredHeight: Style.space(32)
        text: root.draft ? root.draft.icon : ""
        horizontalAlignment: TextInput.AlignHCenter
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        selectByMouse: true
        background: Rectangle {
          radius: Style.cornerRadius
          color: Qt.alpha(Color.foreground, 0.05)
          border.width: iconField.activeFocus ? 2 : 1
          border.color: iconField.activeFocus ? Color.accent : Color.popups.border
        }
        onTextChanged: {
          if (!root.draft) return
          root.draft.icon = text
          root.touch()
        }
        Keys.onEscapePressed: event.accepted = false
      }

      TextField {
        id: nameField
        Layout.preferredWidth: Style.space(220)
        Layout.preferredHeight: Style.space(32)
        text: root.draft ? root.draft.name : ""
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        selectByMouse: true
        background: Rectangle {
          radius: Style.cornerRadius
          color: Qt.alpha(Color.foreground, 0.05)
          border.width: nameField.activeFocus ? 2 : 1
          border.color: nameField.activeFocus ? Color.accent : Color.popups.border
        }
        onTextChanged: {
          if (!root.draft) return
          root.draft.name = text
          root.touch()
        }
        Keys.onEscapePressed: event.accepted = false
      }

      Item { Layout.fillWidth: true; height: 1 }

      Text {
        visible: root.draft
        text: "special:" + (root.draft ? root.draft.id : "")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.tested
        text: qsTr("test applied")
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.border; opacity: 0.6 }

    // ---------- body ----------
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.space(12)

      // ======== left: the canvas + geometry controls ========
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.space(8)

        Item {
          id: canvas
          Layout.fillWidth: true
          Layout.fillHeight: true
          focus: true

          // logical → canvas px mapping: monitor drawn true to scale,
          // centered in whatever space the host surface gives us.
          readonly property var usable: root.usable()
          readonly property real drawScale:
            Math.min(width / usable[0], height / usable[1])
          readonly property real ox: (width - usable[0] * drawScale) / 2
          readonly property real oy: (height - usable[1] * drawScale) / 2
          readonly property var frameBox: root.draft && root.slots
            ? LayoutMath.baseRect(root.draft, usable[0], usable[1])
            : null
          function sx(x) { return ox + x * drawScale }
          function sy(y) { return oy + y * drawScale }

          // slot boxes in canvas px, for hit-testing drops
          function slotBoxesPx() {
            if (!root.draft) return []
            var boxes = LayoutMath.editorSlotBoxes(root.draft, Math.max(1, root.appCount),
                                                    usable[0], usable[1])
            var out = []
            for (var i = 0; i < boxes.length; i++) {
              out.push([sx(boxes[i][0]), sy(boxes[i][1]),
                        boxes[i][2] * drawScale, boxes[i][3] * drawScale])
            }
            return out
          }

          // monitor outline
          Rectangle {
            x: canvas.sx(0); y: canvas.sy(0)
            width: canvas.usable[0] * canvas.drawScale
            height: canvas.usable[1] * canvas.drawScale
            radius: 6
            color: Qt.alpha(Color.background, 0.5)
            border.width: 1
            border.color: Color.popups.border

            Text {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: 4
              text: canvas.usable[0] + "×" + canvas.usable[1]
              color: Color.muted
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          // scratchpad frame (slots mode)
          Rectangle {
            visible: !!canvas.frameBox
            x: canvas.frameBox ? canvas.sx(canvas.frameBox.x) : 0
            y: canvas.frameBox ? canvas.sy(canvas.frameBox.y) : 0
            width: canvas.frameBox ? canvas.frameBox.w * canvas.drawScale : 0
            height: canvas.frameBox ? canvas.frameBox.h * canvas.drawScale : 0
            radius: 4
            color: Qt.alpha(Color.accent, 0.04)
            border.width: 1
            border.color: Qt.alpha(Color.accent, 0.35)
          }

          // window cards in their slots
          Repeater {
            model: root.appCount

            Rectangle {
              id: card
              required property int index
              readonly property var app: root.draft ? root.draft.apps[index] : null
              // true slot geometry; overlaid layouts (single/stacked)
              // cascade here so every card stays visible and grabbable
              readonly property var box: root.draft
                ? LayoutMath.editorSlotBoxes(root.draft, Math.max(1, root.appCount),
                                             canvas.usable[0], canvas.usable[1])[index]
                : [0, 0, 100, 100]
              readonly property bool isSelected: canvas.focus && root.selectedSlot === index

              x: canvas.sx(box[0])
              y: canvas.sy(box[1])
              width: box[2] * canvas.drawScale
              height: box[3] * canvas.drawScale
              radius: Math.min(Style.cornerRadius, height / 6)
              color: isSelected ? Qt.alpha(Color.accent, 0.16)
                : (dragArea.containsMouse || dragArea.drag.active
                   ? Qt.alpha(Color.accent, 0.10) : Qt.alpha(Color.foreground, 0.07))
              border.width: isSelected || dragArea.drag.active ? 2 : 1
              border.color: isSelected || dragArea.drag.active ? Color.accent
                : Qt.alpha(Color.foreground, 0.30)
              z: dragArea.drag.active ? 100 : index
              scale: dragArea.drag.active ? 1.03 : 1

              Behavior on color { ColorAnimation { duration: 140 } }
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

              MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                drag.target: card
                drag.threshold: Style.space(4)
                cursorShape: containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor
                property bool wasDragged: false
                onPressed: function(mouse) {
                  wasDragged = false
                  root.selectedSlot = card.index
                  canvas.forceActiveFocus()
                }
                onPositionChanged: {
                  if (drag.active) wasDragged = true
                }
                onReleased: {
                  if (!wasDragged) return
                  // Which slot did the card's center land in?
                  var cx = card.x + card.width / 2
                  var cy = card.y + card.height / 2
                  var boxes = canvas.slotBoxesPx()
                  for (var i = 0; i < boxes.length; i++) {
                    if (cx >= boxes[i][0] && cx <= boxes[i][0] + boxes[i][2]
                        && cy >= boxes[i][1] && cy <= boxes[i][1] + boxes[i][3]) {
                      root.swapSlots(card.index, i)
                      break
                    }
                  }
                  // The drag wrote x/y imperatively, breaking their
                  // bindings; re-establish them so the card snaps to its
                  // (possibly new) slot and keeps tracking the draft.
                  card.x = Qt.binding(function() { return canvas.sx(card.box[0]) })
                  card.y = Qt.binding(function() { return canvas.sy(card.box[1]) })
                }
              }

              // slot number badge
              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Style.space(4)
                width: slotLabel.implicitWidth + Style.space(8)
                height: Style.space(16)
                radius: height / 2
                color: Qt.alpha(Color.background, 0.7)
                border.width: 1
                border.color: Qt.alpha(Color.foreground, 0.2)
                Text {
                  id: slotLabel
                  anchors.centerIn: parent
                  text: (card.index + 1)
                    + (root.draft
                       && (root.draft.layout === "single" || root.draft.layout === "stacked")
                       ? qsTr(" · overlay") : "")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Math.max(8, Style.font.caption * 0.85)
                  renderType: Text.NativeRendering
                }
              }

              // remove button (top-right, on hover)
              Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(4)
                visible: dragArea.containsMouse
                width: Style.space(20)
                height: width
                radius: width / 2
                color: removeHover.containsMouse
                  ? Qt.alpha(Color.urgent, 0.2) : Qt.alpha(Color.background, 0.7)
                border.width: 1
                border.color: Qt.alpha(Color.foreground, 0.25)

                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  color: removeHover.containsMouse ? Color.urgent : Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }

                MouseArea {
                  id: removeHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.removeApp(card.index)
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)

                Item {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Math.min(card.width * 0.4, Style.space(30))
                  height: width
                  Image {
                    id: cardIcon
                    anchors.fill: parent
                    source: {
                      if (!card.app) return ""
                      var entry = DesktopEntries.heuristicLookup(String(card.app.class || ""))
                      return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
                    }
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: cardIcon.status !== Image.Ready
                    text: card.app ? (card.app.name || "?").slice(0, 1).toUpperCase() : "?"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: parent.width * 0.55
                    renderType: Text.NativeRendering
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Math.min(card.width - Style.space(10), Style.space(140))
                  horizontalAlignment: Text.AlignHCenter
                  text: card.app ? card.app.name : ""
                  elide: Text.ElideRight
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: card.height > Style.space(56) && !!card.app
                  width: Math.min(card.width - Style.space(10), Style.space(140))
                  horizontalAlignment: Text.AlignHCenter
                  text: card.app ? card.app.class : ""
                  elide: Text.ElideMiddle
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }
              }
            }
          }

          // resize handle at the frame corner (slots mode). No drag.target:
          // pointer moves recompute sizePct and the handle follows its own
          // binding to the frame corner — no binding is ever broken.
          Item {
            visible: !!canvas.frameBox
            x: canvas.frameBox ? canvas.sx(canvas.frameBox.x + canvas.frameBox.w) - width / 2 : 0
            y: canvas.frameBox ? canvas.sy(canvas.frameBox.y + canvas.frameBox.h) - height / 2 : 0
            width: Style.space(16)
            height: Style.space(16)

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: resizeHover.containsMouse || resizeHover.pressed
                ? Color.accent : Qt.alpha(Color.accent, 0.55)
              border.width: 2
              border.color: Color.background
              Behavior on color { ColorAnimation { duration: 140 } }
            }

            MouseArea {
              id: resizeHover
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.SizeFDiagCursor
              onPressed: canvas.forceActiveFocus()
              onPositionChanged: {
                if (!pressed || !root.draft) return
                var p = mapToItem(canvas, mouse.x, mouse.y)
                var lx = (p.x - canvas.ox) / canvas.drawScale
                var ly = (p.y - canvas.oy) / canvas.drawScale
                var frame = canvas.frameBox
                if (!frame) return
                var changed = false
                var wPct = Math.round((lx - frame.x) / canvas.usable[0] * 100)
                var hPct = Math.round((ly - frame.y) / canvas.usable[1] * 100)
                if (wPct >= 30 && wPct <= 95 && wPct !== root.draft.sizePct.w) {
                  root.draft.sizePct.w = wPct; changed = true
                }
                if (hPct >= 25 && hPct <= 95 && hPct !== root.draft.sizePct.h) {
                  root.draft.sizePct.h = hPct; changed = true
                }
                if (changed) root.touch()
              }
            }
          }

          // empty / floating hints
          Column {
            anchors.centerIn: parent
            visible: root.appCount === 0 || !root.slots
            spacing: Style.space(6)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.appCount === 0
                ? qsTr("No apps yet — add one from the list")
                : qsTr("Windows float freely")
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.appCount > 0 && !root.slots
              text: qsTr("size and anchor don't apply while floating")
              color: Color.muted
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

        }

        // geometry captions + controls
        Text {
          visible: root.slots && root.draft
            && (root.draft.layout === "single" || root.draft.layout === "stacked")
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          text: qsTr("Cards cascade here so overlaid slots stay editable; on screen the windows sit exactly on top of each other.")
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }

        Text {
          visible: root.slots
          Layout.fillWidth: true
          text: qsTr("Drag a card onto another slot to swap · Del removes · Ctrl+←/→ moves")
          color: Color.muted
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }

        // geometry controls: anchor glyphs (center included) + live size
        RowLayout {
          visible: root.slots
          Layout.fillWidth: true
          spacing: Style.space(12)

          Row {
            spacing: Style.space(4)
            Repeater {
              model: [
                { id: "top",    glyph: "󰁝" },
                { id: "bottom", glyph: "󰁅" },
                { id: "left",   glyph: "󰁔" },
                { id: "right",  glyph: "󰁠" },
                { id: "center", glyph: "◎" }
              ]
              Button {
                required property var modelData
                text: modelData.glyph
                tooltipText: qsTr("anchor: %1").arg(modelData.id)
                fontSize: Style.font.caption
                selected: root.draft && root.draft.anchor === modelData.id
                onClicked: {
                  root.draft.anchor = modelData.id
                  root.touch()
                }
              }
            }
          }

          Item { Layout.fillWidth: true; height: 1 }

          Text {
            text: (root.draft ? root.draft.sizePct.w : 60) + "% × "
              + (root.draft ? root.draft.sizePct.h : 50) + "%"
              + (root.draft ? "  ·  " + root.draft.marginPx + "px" : "")
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }

        // slide-in (appear behavior) — beside the anchor it steers; the
        // center entry pairs a centered anchor with a pop-in reveal.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          Text {
            text: qsTr("Slide-in")
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Row {
            spacing: Style.space(4)
            Repeater {
              model: root.directions
              Button {
                required property var modelData
                text: modelData.glyph
                tooltipText: modelData.label
                fontSize: Style.font.caption
                selected: root.draft && root.draft.transition === modelData.id
                onClicked: root.setTransition(modelData)
              }
            }
          }

          Item { Layout.fillWidth: true; height: 1 }

          Text {
            visible: root.draft && root.draft.transition === "popin"
            text: qsTr("windows pop in at the center anchor")
            color: Color.muted
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }
      }

      // ======== right: apps, arrangement, keybind ========
      ColumnLayout {
        Layout.preferredWidth: Style.space(300)
        Layout.fillHeight: true
        spacing: Style.space(8)

        // apps list
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: Math.min(Style.space(150),
            Style.space(30) * Math.max(1, root.appCount) + Style.space(64))
          radius: Style.cornerRadius
          color: Qt.alpha(Color.foreground, 0.035)
          border.width: 1
          border.color: Color.popups.border

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(4)

            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: qsTr("Windows (%1)").arg(root.appCount)
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
              Text {
                visible: root.slots
                text: qsTr("slot order")
                color: Color.muted
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }

            Flickable {
              id: appsFlick
              Layout.fillWidth: true
              Layout.fillHeight: true
              contentWidth: width
              contentHeight: appsColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height

              Column {
                id: appsColumn
                width: appsFlick.width
                spacing: 2

                Repeater {
                  model: root.appCount

                  Item {
                    required property int index
                    width: appsFlick.width
                    height: Style.space(30)
                    readonly property var app: root.draft ? root.draft.apps[index] : null
                    readonly property bool isSel: root.selectedSlot === index && canvas.focus

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius - 2
                      color: parent.isSel ? Qt.alpha(Color.accent, 0.12)
                        : (rowMouse.containsMouse ? Qt.alpha(Color.foreground, 0.06) : "transparent")
                      border.width: parent.isSel ? 2 : 0
                      border.color: Color.accent
                    }

                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: {
                        root.selectedSlot = index
                        canvas.forceActiveFocus()
                      }
                    }

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(4)
                      spacing: Style.space(6)

                      Text {
                        Layout.preferredWidth: Style.space(16)
                        horizontalAlignment: Text.AlignHCenter
                        text: String(index + 1)
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        renderType: Text.NativeRendering
                      }

                      Item {
                        Layout.preferredWidth: Style.space(18)
                        Layout.preferredHeight: Style.space(18)
                        Image {
                          anchors.fill: parent
                          source: {
                            if (!app) return ""
                            var entry = DesktopEntries.heuristicLookup(String(app.class || ""))
                            return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
                          }
                          fillMode: Image.PreserveAspectFit
                          smooth: true
                          visible: status === Image.Ready
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                          Layout.fillWidth: true
                          text: app ? app.name : ""
                          elide: Text.ElideRight
                          color: Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          renderType: Text.NativeRendering
                        }
                        Text {
                          Layout.fillWidth: true
                          visible: app && app.webapp
                          text: qsTr("web app")
                          color: Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Math.max(8, Style.font.caption * 0.85)
                          renderType: Text.NativeRendering
                        }
                      }

                      Text {
                        visible: app && app.singleInstance
                        text: qsTr("single")
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Math.max(8, Style.font.caption * 0.85)
                        renderType: Text.NativeRendering
                      }

                      Text {
                        text: "󰅖"
                        color: rowRemove.containsMouse ? Color.urgent : Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption

                        MouseArea {
                          id: rowRemove
                          anchors.fill: parent
                          anchors.margins: -Style.space(4)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.removeApp(index)
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: root.appCount === 0
                  width: appsFlick.width
                  horizontalAlignment: Text.AlignHCenter
                  topPadding: Style.space(10)
                  text: qsTr("none yet")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }
              }
            }

            Button {
              Layout.fillWidth: true
              height: Style.space(28)
              text: qsTr("Add app")
              iconText: "󰐗"
              fontSize: Style.font.bodySmall
              onClicked: {
                root.addingApp = true
                Qt.callLater(function() { pickerOverlay.focusSearch() })
              }
            }
          }
        }

        // arrangement
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: thumbsCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.alpha(Color.foreground, 0.035)
          border.width: 1
          border.color: Color.popups.border

          ColumnLayout {
            id: thumbsCol
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: qsTr("Arrangement")
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            LayoutThumbRow {
              Layout.fillWidth: true
              compact: true
              layoutId: root.draft ? root.draft.layout : "single"
              placement: root.draft ? root.draft.placement : "slots"
              count: Math.max(1, root.appCount)
              onLayoutChosen: function(id) { root.setLayout(id) }
              onPlacementChosen: function(mode) { root.setPlacement(mode) }
            }
          }
        }

        // keybind — an editable control, not a label: click the chip (or
        // Ctrl+K) to re-capture; conflicts surface inline. Fixed height so
        // the column can never push it under the footer again.
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(148)
          radius: Style.cornerRadius
          color: Qt.alpha(Color.foreground, 0.035)
          border.width: 1
          border.color: Color.popups.border

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: qsTr("Keybind")
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
              Item { Layout.fillWidth: true; height: 1 }
              Text {
                text: qsTr("Ctrl+K to rebind")
                color: Color.muted
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Math.max(8, Style.font.caption * 0.85)
                renderType: Text.NativeRendering
              }
            }

            KeybindCapture {
              id: keybindCapture
              Layout.fillWidth: true
              Layout.fillHeight: true
              compact: true
              chord: root.draft ? root.draft.keybind : ""
              selfId: root.draft ? root.draft.id : ""
              selfName: root.draft ? root.draft.name : ""
              onChordEdited: function(chord) {
                if (!root.draft) return
                root.draft.keybind = chord
                root.touch()
              }
            }
          }
        }
      }
    }

    // ---------- footer ----------
    Row {
      Layout.fillWidth: true
      spacing: Style.space(8)
      layoutDirection: Qt.RightToLeft

      Button {
        text: root.tested ? qsTr("Save changes") : qsTr("Save")
        iconText: "󰸞"
        fontSize: Style.font.body
        onClicked: root.save()
      }

      Button {
        text: qsTr("Test it now")
        iconText: "󰓅"
        fontSize: Style.font.body
        onClicked: root.testNow()
      }

      Button {
        text: qsTr("Cancel")
        fontSize: Style.font.body
        onClicked: root.cancel()
      }
    }
  }

  // ---------- add-app overlay ----------
  Rectangle {
    anchors.fill: parent
    visible: root.addingApp
    color: Qt.alpha(Color.background, 0.9)
    radius: Style.cornerRadius
    border.width: 1
    border.color: Color.popups.border
    z: 50

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: qsTr("Add an app to “%1”").arg(root.draft ? root.draft.name : "")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          renderType: Text.NativeRendering
        }
        Button {
          text: qsTr("Done")
          iconText: "󰄬"
          fontSize: Style.font.bodySmall
          onClicked: {
            root.addingApp = false
            canvas.forceActiveFocus()
          }
        }
      }

      AppPickerList {
        id: pickerOverlay
        Layout.fillWidth: true
        Layout.fillHeight: true
        demo: root.demo
        pickedClasses: root.draft
          ? root.draft.apps.map(function (a) { return a.class })
          : []
        onPicked: function(app) { root.addApp(app) }
        onEscapeRequested: {
          root.addingApp = false
          canvas.forceActiveFocus()
        }
      }
    }
  }

  // ---------------- keyboard (all at root, one place) ----------------
  // While a text field, the chord capture, or the add-app overlay holds
  // focus, the editor shortcuts stand back — typing must never rearrange
  // windows behind the user's back.
  readonly property bool textEntry: nameField.activeFocus || iconField.activeFocus
    || keybindCapture.activeFocus || addingApp

  // Esc closes the overlay, then the editor; Ctrl+Enter saves, Ctrl+K
  // rebinds, Ctrl+A adds an app; plain arrows select the slot (canvas)
  // and Ctrl+arrows move the selected app through the slot order; Del
  // removes it.
  Keys.onEscapePressed: function(event) {
    if (addingApp) {
      addingApp = false
      canvas.forceActiveFocus()
      event.accepted = true
      return
    }
    cancel()
    event.accepted = true
  }
  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      save()
      event.accepted = true
      return
    }
    if (textEntry) {
      event.accepted = false
      return
    }
    if (ctrl && event.key === Qt.Key_K && !addingApp) {
      keybindCapture.forceCapture()
      event.accepted = true
      return
    }
    if (ctrl && event.key === Qt.Key_A) {
      addingApp = !addingApp
      if (addingApp) Qt.callLater(function() { pickerOverlay.focusSearch() })
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
      if (appCount > 0) removeApp(selectedSlot)
      event.accepted = true
      return
    }
    var horizontal = event.key === Qt.Key_Left || event.key === Qt.Key_Right
    var vertical = event.key === Qt.Key_Up || event.key === Qt.Key_Down
    if (!horizontal && !vertical) {
      event.accepted = false
      return
    }
    var forward = event.key === Qt.Key_Right || event.key === Qt.Key_Down
    if (ctrl) moveApp(selectedSlot, forward ? 1 : -1)
    else selectedSlot = forward
      ? Math.min(Math.max(0, appCount - 1), selectedSlot + 1)
      : Math.max(0, selectedSlot - 1)
    event.accepted = true
  }
}
