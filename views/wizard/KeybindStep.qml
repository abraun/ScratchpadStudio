import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

// KeybindStep — press-to-capture a chord, with live conflict detection
// (live binds + config files), suggested free chords, and a loud warning
// when the chord collides with an Omarchy default.
Item {
  id: root

  property var draft: null
  signal touched()

  property bool capturing: false
  property string captured: ""
  property string conflictText: ""
  property bool conflictIsOmarchy: false
  property var suggestionRows: []
  property var binds: []

  Component.onCompleted: {
    bindsProc.running = true
    if (root.draft && root.draft.keybind !== "") conflictProc.running = true
  }

  function refreshConflicts(chord) {
    draft.keybind = chord
    touched()
    conflictProc.args = [chord]
    conflictProc.running = true
  }

  // key name cleanup for display
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
      decodeURIComponent(Qt.resolvedUrl("../../bin/scratchpad-studio").toString()
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
    property var args: []
    command: {
      var base = decodeURIComponent(Qt.resolvedUrl("../../bin/scratchpad-studio").toString()
        .replace(/^file:\/\//, ""))
      var chord = args.length > 0 ? args[0] : (root.draft ? root.draft.keybind : "")
      return ["bash", "-c", JSON.stringify(base) + " conflicts-json " + JSON.stringify(chord) + " 2>/dev/null"]
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.liveBind) {
            conflictIsOmarchy = String(result.liveBind.description || "").length > 0
              && !String(result.liveBind.description || "").startsWith("Scratchpad")
            conflictText = conflictIsOmarchy
              ? qsTr("Bound to “%1” — an Omarchy default or another plugin. Pick another chord.").arg(result.liveBind.description)
              : qsTr("Bound to “%1”.").arg(result.liveBind.description)
          } else if (result.configLines && result.configLines.length > 0) {
            conflictIsOmarchy = false
            conflictText = qsTr("Used in your config (%1).").arg(result.configLines[0][1])
          } else {
            conflictIsOmarchy = false
            conflictText = ""
          }
        } catch (e) {
          conflictText = ""
        }
      }
    }
  }

  Keys.onPressed: function(event) {
    if (!capturing) return
    event.accepted = true
    if (event.key === Qt.Key_Escape) {
      capturing = false
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return
    if (event.key === Qt.Key_Backspace) {
      draft.keybind = ""
      touched()
      capturing = false
      return
    }
    var mods = []
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    var name = keyName(event.text !== "" && event.text !== " " ? event.text : keyFromCode(event.key))
    // modifier-only presses don't count
    if (["SHIFT", "CTRL", "ALT", "SUPER", "META"].indexOf(name) >= 0) return
    if (mods.length === 0) {
      conflictText = qsTr("Add a modifier — bare keys type into apps.")
      return
    }
    captured = mods.join(" + ") + " + " + name
    capturing = false
    refreshConflicts(captured)
  }

  function keyFromCode(code) {
    if (code >= Qt.Key_A && code <= Qt.Key_Z) return String.fromCharCode(code)
    if (code >= Qt.Key_0 && code <= Qt.Key_9) return String.fromCharCode(code)
    if (code >= Qt.Key_F1 && code <= Qt.Key_F35) return "F" + (code - Qt.Key_F1 + 1)
    return "?"
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)
    // capture well
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(76)
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
            : (root.draft && root.draft.keybind !== "" ? root.draft.keybind
               : qsTr("Click, then press a chord"))
          color: root.capturing ? Color.accent
            : (root.draft && root.draft.keybind !== "" ? Color.foreground : Color.muted)
          font.family: Style.font.family
          font.pixelSize: root.capturing || (root.draft && root.draft.keybind !== "")
            ? Style.font.subtitle : Style.font.body
          font.bold: true
          renderType: Text.NativeRendering
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.draft && root.draft.keybind !== ""
          text: qsTr("bound to o.bind(\"%1\", …) in the managed block").arg(root.draft ? root.draft.keybind : "")
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
      Layout.preferredHeight: conflictLabel.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: root.conflictIsOmarchy ? Qt.alpha(Color.urgent, 0.12) : Qt.alpha(Color.foreground, 0.06)
      border.width: 1
      border.color: root.conflictIsOmarchy ? Color.urgent : Color.popups.border

      Text {
        id: conflictLabel
        anchors.fill: parent
        anchors.margins: Style.space(8)
        wrapMode: Text.Wrap
        text: (root.conflictIsOmarchy ? "⚠  " : "·  ") + root.conflictText
        color: root.conflictIsOmarchy ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }
    }

    // suggestions
    Text {
      visible: root.suggestionRows.length > 0
      text: qsTr("Free chords")
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Flow {
      visible: root.suggestionRows.length > 0
      Layout.fillWidth: true
      spacing: Style.space(6)

      Repeater {
        model: root.suggestionRows

        Button {
          required property string modelData
          text: modelData
          fontSize: Style.font.bodySmall
          onClicked: root.refreshConflicts(modelData)
        }
      }
    }

    Item { Layout.fillHeight: true; Layout.fillWidth: true }
  }
}
