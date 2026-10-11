import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

// KeybindCapture — press-to-capture a chord with live conflict detection
// (live binds + textual config scan), suggested free chords, and a loud
// warning for Omarchy-default collisions. Shared by the wizard's KeybindStep
// and the editor.
//
// `selfId` names the scratchpad being edited: its own current chord is not
// a conflict (saving replaces the old o.bind line wholesale), so the helper
// filters that bind out before matching (`conflicts-json --self <id>`).
Item {
  id: root

  property string chord: ""              // current chord ("" = unbound)
  property string selfId: ""             // scratchpad id whose bind is ours
  property string selfName: ""
  property bool compact: false
  signal chordEdited(string chord)

  // Keyboard path: the well is tab-reachable and Enter/Space arms capture
  // (clicking works too) — chord changes never require the mouse.
  activeFocusOnTab: true

  property bool capturing: false
  property string captured: ""
  property string conflictText: ""
  property bool conflictIsOmarchy: false
  property bool conflictIsOtherScratchpad: false
  property var suggestionRows: []
  property var binds: []

  Component.onCompleted: {
    bindsProc.running = true
    if (root.chord !== "") checkConflicts(root.chord)
  }

  onSelfIdChanged: if (root.chord !== "") checkConflicts(root.chord)

  // Entering with no chord armed: start capturing immediately — focus
  // alone is the invitation.
  onActiveFocusChanged: {
    if (activeFocus && root.chord === "") capturing = true
  }

  function setChord(chord) {
    root.chord = chord
    chordEdited(chord)
    checkConflicts(chord)
  }

  function forceCapture() {
    capturing = true
    forceActiveFocus()
  }

  function checkConflicts(chord) {
    conflictProc.chordArg = chord
    conflictProc.running = true
  }

  function keyName(key) {
    var map = {
      " ": "SPACE", "Escape": "ESC", "Return": "ENTER", "Tab": "TAB",
      "Backspace": "BACKSPACE", "Left": "LEFT", "Right": "RIGHT",
      "Up": "UP", "Down": "DOWN"
    }
    if (map[key] !== undefined) return map[key]
    if (key.length === 1) return key.toUpperCase()
    return key.toUpperCase()
  }

  Process {
    id: bindsProc
    command: ["bash", "-c",
      decodeURIComponent(Qt.resolvedUrl("../bin/scratchpad-studio").toString()
        .replace(/^file:\/\//, "")) + " binds-json 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.binds = JSON.parse(text) }
        catch (e) { root.binds = [] }
        root.rebuildSuggestions()
      }
    }
  }

  function rebuildSuggestions() {
    // Chords Omarchy leaves free for scratchpads: SUPER+ALT and
    // SUPER+SHIFT+ALT letters, checked against live binds.
    var taken = {}
    for (var i = 0; i < binds.length; i++) {
      taken[binds[i].modmask + ":" + binds[i].key] = true
    }
    var combos = []
    var letters = "BNPVXCEFGHIJKLOQRTUWXYZD"
    for (var l = 0; l < letters.length && combos.length < 5; l++) {
      var key = letters[l]
      if (!taken["72:" + key]) combos.push("ALT + SUPER + " + key)
    }
    for (var l2 = 0; l2 < letters.length && combos.length < 8; l2++) {
      var key2 = letters[l2]
      if (!taken["73:" + key2]) combos.push("SHIFT + ALT + SUPER + " + key2)
    }
    suggestionRows = combos
  }

  Process {
    id: conflictProc
    property string chordArg: ""
    command: {
      var base = decodeURIComponent(Qt.resolvedUrl("../bin/scratchpad-studio").toString()
        .replace(/^file:\/\//, ""))
      var cmd = JSON.stringify(base) + " conflicts-json " + JSON.stringify(chordArg)
      if (root.selfId !== "") cmd += " --self " + JSON.stringify(root.selfId)
      return ["bash", "-c", cmd + " 2>/dev/null"]
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.liveBind) {
            var desc = String(result.liveBind.description || "")
            conflictIsOtherScratchpad = desc.indexOf("Scratchpad: ") === 0
              || String(result.liveBind.arg || "").indexOf(" toggle ") >= 0
            conflictIsOmarchy = !conflictIsOtherScratchpad
            conflictText = conflictIsOtherScratchpad
              ? qsTr("Already used by another scratchpad (%1). Saving would make one chord toggle two scratchpads — pick another.").arg(desc.replace("Scratchpad: ", ""))
              : desc !== ""
                ? qsTr("Bound to “%1” — an Omarchy default or another plugin. Pick another chord.").arg(desc)
                : qsTr("Already bound to another action.")
          } else if (result.configLines && result.configLines.length > 0) {
            conflictIsOmarchy = false
            conflictIsOtherScratchpad = false
            conflictText = qsTr("Used in your config (%1).").arg(result.configLines[0][1])
          } else {
            conflictIsOmarchy = false
            conflictIsOtherScratchpad = false
            conflictText = ""
          }
        } catch (e) {
          conflictText = ""
        }
      }
    }
  }

  Keys.onPressed: function(event) {
    if (!capturing) {
      // Unmodified Enter/Space on the focused well starts capture; anything
      // with modifiers (the host's Ctrl+Enter save, arrows, …) falls
      // through to the host surface untouched.
      var plain = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space
      if (plain && event.modifiers === Qt.NoModifier) {
        forceCapture()
        event.accepted = true
      } else {
        event.accepted = false
      }
      return
    }
    event.accepted = true
    if (event.key === Qt.Key_Escape) {
      capturing = false
      return
    }
    // Swallow Enter while capturing so it cannot bubble up and trigger
    // the wizard's advance / the editor's focused buttons.
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return
    if (event.key === Qt.Key_Backspace) {
      setChord("")
      capturing = false
      return
    }
    var mods = []
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    // event.text under Ctrl is a control character (or empty), never the
    // letter — trust it only when printable, else derive from the key code.
    var t = event.text
    var printable = t.length === 1 && t.charCodeAt(0) >= 33 && t.charCodeAt(0) <= 126
    var name = keyName(printable ? t : keyFromCode(event.key))
    // modifier-only presses don't count
    if (["SHIFT", "CTRL", "ALT", "SUPER", "META"].indexOf(name) >= 0) return
    if (mods.length === 0) {
      conflictText = qsTr("Add a modifier — bare keys type into apps.")
      conflictIsOmarchy = false
      conflictIsOtherScratchpad = false
      return
    }
    captured = mods.join(" + ") + " + " + name
    capturing = false
    setChord(captured)
  }

  function keyFromCode(code) {
    if (code >= Qt.Key_A && code <= Qt.Key_Z) return String.fromCharCode(code)
    if (code >= Qt.Key_0 && code <= Qt.Key_9) return String.fromCharCode(code)
    if (code >= Qt.Key_F1 && code <= Qt.Key_F35) return "F" + (code - Qt.Key_F1 + 1)
    return "?"
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    // capture well
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: root.compact ? Style.space(64) : Style.space(76)
      radius: Style.cornerRadius + 2
      color: capturing ? Qt.alpha(Color.accent, 0.10) : Qt.alpha(Color.foreground, 0.04)
      border.width: capturing ? 2 : 1
      border.color: capturing ? Color.accent : Color.popups.border
      Behavior on border.color { ColorAnimation { duration: 140 } }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          root.capturing = true
          root.forceActiveFocus()
        }
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(4)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.capturing
            ? qsTr("Press a chord…  (Esc cancels, Backspace clears)")
            : (root.chord !== "" ? root.chord : qsTr("Click, then press a chord"))
          color: root.capturing ? Color.accent
            : (root.chord !== "" ? Color.foreground : Color.muted)
          font.family: Style.font.family
          font.pixelSize: root.capturing || root.chord !== ""
            ? Style.font.subtitle : Style.font.body
          font.bold: true
          renderType: Text.NativeRendering
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: !root.compact && root.chord !== ""
          text: qsTr("saving rewrites the o.bind(\"%1\", …) line — no orphan binds").arg(root.chord)
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }
    }

    // conflict banner
    Rectangle {
      Layout.fillWidth: true
      visible: root.conflictText !== ""
      Layout.preferredHeight: conflictLabel.implicitHeight + Style.space(14)
      radius: Style.cornerRadius
      color: (root.conflictIsOmarchy || root.conflictIsOtherScratchpad)
        ? Qt.alpha(Color.urgent, 0.12) : Qt.alpha(Color.foreground, 0.06)
      border.width: 1
      border.color: (root.conflictIsOmarchy || root.conflictIsOtherScratchpad)
        ? Color.urgent : Color.popups.border

      Text {
        id: conflictLabel
        anchors.fill: parent
        anchors.margins: Style.space(8)
        wrapMode: Text.Wrap
        text: (root.conflictIsOmarchy || root.conflictIsOtherScratchpad ? "⚠  " : "·  ") + root.conflictText
        color: (root.conflictIsOmarchy || root.conflictIsOtherScratchpad) ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }
    }

    // suggestions
    Text {
      visible: !root.compact && root.suggestionRows.length > 0
      text: qsTr("Free chords")
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Flow {
      visible: !root.compact && root.suggestionRows.length > 0
      Layout.fillWidth: true
      spacing: Style.space(6)

      Repeater {
        model: root.suggestionRows

        Button {
          required property string modelData
          text: modelData
          fontSize: Style.font.bodySmall
          onClicked: root.setChord(modelData)
        }
      }
    }

    Item { Layout.fillHeight: true; Layout.fillWidth: true }
  }
}
