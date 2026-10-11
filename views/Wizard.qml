import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "wizard"
import ".."

// Wizard — create or edit a scratchpad in six steps.
//
// Keyboard-first: Enter advances, Esc goes back one step (or cancels from
// the first step). The draft lives entirely in QML; steps mutate it and
// call touch() so every preview re-renders. Saving goes through the helper
// CLI (`upsert`), which owns state merging, config regeneration and reload.
Item {
  id: root

  required property var editScratchpad     // null = create; object = edit
  property bool demo: false
  property var monitor: null               // {width, height, scale} for previews

  signal finished(var scratchpad)
  signal canceled()

  // ---------------- draft state ----------------
  property var draft: ({
    id: "",
    name: "",
    icon: "",
    keybind: "",
    anchor: "top",
    layout: "single",
    transition: "down",
    sizePct: { w: 60, h: 50 },
    marginPx: 12,
    apps: []
  })

  property int step: 0
  readonly property var steps: ["Basics", "Apps", "Layout", "Slide-in", "Keybind", "Review"]
  readonly property bool editing: !!editScratchpad
  readonly property var original: editScratchpad ? JSON.parse(JSON.stringify(editScratchpad)) : null
  property bool tested: false

  Component.onCompleted: {
    if (editScratchpad) draft = JSON.parse(JSON.stringify(editScratchpad))
    forceActiveFocus()
  }

  // Re-assign the draft so var-property bindings (previews, summaries)
  // re-evaluate after a step mutated it in place.
  function touch() {
    draft = JSON.parse(JSON.stringify(draft))
  }

  function usable() {
    var scale = monitor && monitor.scale ? monitor.scale : 1
    return monitor
      ? [Math.round(monitor.width / scale), Math.round(monitor.height / scale)]
      : [1800, 1125]
  }

  function canAdvance() {
    if (step === 0) return String(draft.name || "").trim().length > 0
    return true
  }

  function advance() {
    if (!canAdvance()) return
    if (step < steps.length - 1) {
      step++
      Qt.callLater(function() { root.forceActiveFocus() })
    } else {
      finish()
    }
  }

  function goBack() {
    if (step > 0) {
      step--
      Qt.callLater(function() { root.forceActiveFocus() })
    } else {
      cancel()
    }
  }

  function cancel() {
    // "Test it now" writes the draft for real; canceling afterwards restores
    // what was there before the wizard opened.
    if (tested) {
      if (original) runHelper("upsert", JSON.stringify(original))
      else if (draft.id) runHelper(["delete", draft.id])
    }
    canceled()
  }

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

  function finish() {
    if (!demo) runHelper("upsert", JSON.stringify(draft))
    finished(draft)
  }

  function testNow() {
    if (demo) return
    runHelper("upsert", JSON.stringify(draft))
    Qt.callLater(function() {
      runHelper(["toggle", draft.id || "scratchpad"])
    })
    tested = true
  }

  // ---------------- chrome ----------------

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    // step header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        Layout.alignment: Qt.AlignVCenter
        text: root.editing
          ? qsTr("Edit “%1”").arg(root.original ? root.original.name : "")
          : qsTr("New scratchpad")
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        renderType: Text.NativeRendering
      }

      Item { Layout.fillWidth: true; height: 1 }

      Repeater {
        model: root.steps.length
        Rectangle {
          required property int index
          Layout.alignment: Qt.AlignVCenter
          width: Style.space(index === root.step ? 18 : 8)
          height: Style.space(8)
          radius: height / 2
          color: index <= root.step ? Color.accent : Qt.alpha(Color.foreground, 0.2)
          Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 150 } }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Step %1 of %2 — %3").arg(root.step + 1).arg(root.steps.length).arg(root.steps[root.step])
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.border; opacity: 0.6 }

    StackLayout {
      id: body
      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: root.step

      BasicsStep { draft: root.draft; onTouched: root.touch() }
      AppsStep { draft: root.draft; demo: root.demo; onTouched: root.touch() }
      LayoutStep { draft: root.draft; usable: root.usable(); onTouched: root.touch() }
      TransitionStep { draft: root.draft; onTouched: root.touch() }
      KeybindStep { draft: root.draft; onTouched: root.touch() }
      SummaryStep {
        draft: root.draft
        usable: root.usable()
        onTestNow: root.testNow()
      }
    }

    // footer nav
    Row {
      Layout.fillWidth: true
      spacing: Style.space(8)
      layoutDirection: Qt.RightToLeft

      Button {
        text: root.step === root.steps.length - 1
          ? (root.editing ? qsTr("Save") : qsTr("Create"))
          : qsTr("Next")
        iconText: root.step === root.steps.length - 1 ? "󰸞" : "󰁔"
        fontSize: Style.font.body
        enabled: root.canAdvance()
        onClicked: root.advance()
      }

      Button {
        visible: root.step === root.steps.length - 1
        text: qsTr("Test it now")
        iconText: "󰓅"
        fontSize: Style.font.body
        onClicked: root.testNow()
      }

      Button {
        text: root.step > 0 ? qsTr("Back") : qsTr("Cancel")
        fontSize: Style.font.body
        onClicked: root.goBack()
      }
    }
  }

  Keys.onEscapePressed: root.goBack()
  Keys.onReturnPressed: root.advance()
  Keys.onEnterPressed: root.advance()
}
