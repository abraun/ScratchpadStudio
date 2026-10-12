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
  // Chord captured in this session. Kept separate from `chord` (which the
  // host binds) because assigning to a bound property destroys its
  // binding — a previous version did that and the control went "static"
  // after the first capture (re-opening the editor showed a stale chord).
  // shownChord prefers the live value; a real external chord change wins.
  property string liveChord: ""
  onChordChanged: {
    liveChord = ""
    // Re-check when the host's chord settles (opening a scratchpad while
    // another one was edited before used to run the check with the stale
    // chord and flag a conflict that was never typed).
    if (root.chord !== "") checkConflicts(root.chord)
    else conflictText = ""
  }
  readonly property string shownChord: liveChord !== "" ? liveChord : chord
  // Modifiers currently held while capturing, in press order — the live
  // "SUPER + SHIFT + …" display. Key RELEASES remove them again so the
  // display tracks the fingers, not history.
  property var heldMods: []
  property string captureHint: ""
  property int checkProcSerial: 0
  property string conflictText: ""
  property bool conflictIsOmarchy: false
  property bool conflictIsOtherScratchpad: false
  // A conflict means the chord is taken — by another scratchpad, an
  // Omarchy default, or the user's own config — and the host must refuse
  // to save until it is resolved (the captain asked for a hard block, not
  // a warning that can be overwritten).
  readonly property bool blockingConflict: conflictText !== ""
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
    if (activeFocus && root.chord === "" && !capturing) beginCapture()
  }

  function setChord(chord) {
    liveChord = chord
    chordEdited(chord)
    checkConflicts(chord)
  }

  function beginCapture() {
    capturing = true
    heldMods = []
    captureHint = ""
    conflictText = ""
    // Re-read the live binds: the list from shell startup goes stale as
    // soon as a new scratchpad (or any o.bind) is written this session.
    bindsProc.running = true
    forceActiveFocus()
  }

  function endCapture() {
    capturing = false
    heldMods = []
    captureHint = ""
  }

  function forceCapture() {
    beginCapture()
  }

  function checkConflicts(chord) {
    // Serial-stamped: only the newest check may write the banner. Opening
    // scratchpad B right after editing scratchpad A fires two checks
    // (stale chord, then settled chord) — the stale result must lose.
    checkProcSerial++
    conflictProc.runSerial = checkProcSerial
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

  // Canonical chord-modifier name for a modifier key code, or "" when the
  // key is not a modifier. Qt reports the Super key as Qt.Key_Super_L/R
  // (Qt.Meta being the windows-key alias); without this mapping a pressed
  // SUPER used to complete the chord as "SUPER + ?" — the capture-stops-
  // at-the-first-key bug — because keyFromCode() did not know the code.
  function modifierName(key) {
    switch (key) {
      case Qt.Key_Shift: case Qt.Key_Shift_L: case Qt.Key_Shift_R:
        return "SHIFT"
      case Qt.Key_Control: case Qt.Key_Control_L: case Qt.Key_Control_R:
        return "CTRL"
      case Qt.Key_Alt: case Qt.Key_Alt_L: case Qt.Key_Alt_R:
        return "ALT"
      case Qt.Key_Meta: case Qt.Key_Super_L: case Qt.Key_Super_R:
      case Qt.Key_Hyper_L: case Qt.Key_Hyper_R:
        return "SUPER"
    }
    return ""
  }

  // Lock/cluster keys: neither modifiers Hyprland binds on nor keys we
  // want to end capture — swallowed while capturing.
  function ignoredKeyName(key) {
    switch (key) {
      case Qt.Key_CapsLock: case Qt.Key_NumLock: case Qt.Key_ScrollLock:
      case Qt.Key_AltGr: case Qt.Key_Direction_L: case Qt.Key_Direction_R:
        return true
    }
    return false
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
    property int runSerial: 0
    command: {
      var base = decodeURIComponent(Qt.resolvedUrl("../bin/scratchpad-studio").toString()
        .replace(/^file:\/\//, ""))
      var cmd = JSON.stringify(base) + " conflicts-json " + JSON.stringify(chordArg)
      if (root.selfId !== "") cmd += " --self " + JSON.stringify(root.selfId)
      return ["bash", "-c", cmd + " 2>/dev/null"]
    }
    stdout: StdioCollector {
      onStreamFinished: {
        // A newer check (or a cleared state) supersedes this result.
        if (conflictProc.runSerial !== root.checkProcSerial) return
        try {
          var result = JSON.parse(text)
          // State is the authority for scratchpad chords — live binds can
          // be stale in a long-running shell, which once made this
          // scratchpad's own chord report a phantom conflict.
          if (result.scratchpadOwners && result.scratchpadOwners.length > 0) {
            conflictIsOtherScratchpad = true
            conflictIsOmarchy = false
            var names = result.scratchpadOwners.map(function(o) { return o.name })
            conflictText = qsTr("Already used by another scratchpad (%1) — pick another chord; saving stays blocked until it is free.").arg(names.join(", "))
          } else if (result.liveBind) {
            var desc = String(result.liveBind.description || "")
            conflictIsOtherScratchpad = desc.indexOf("Scratchpad: ") === 0
              || String(result.liveBind.arg || "").indexOf(" toggle ") >= 0
            conflictIsOmarchy = !conflictIsOtherScratchpad
            conflictText = conflictIsOtherScratchpad
              ? qsTr("Already used by another scratchpad (%1) — pick another chord; saving stays blocked until it is free.").arg(desc.replace("Scratchpad: ", ""))
              : desc !== ""
                ? qsTr("Bound to “%1” — an Omarchy default or another plugin. Pick another chord; saving stays blocked.").arg(desc)
                : qsTr("Already bound to another action — pick another chord; saving stays blocked.")
          } else if (result.configLines && result.configLines.length > 0) {
            conflictIsOmarchy = false
            conflictIsOtherScratchpad = false
            conflictText = qsTr("Used in your config (%1) — pick another chord; saving stays blocked.").arg(result.configLines[0][1])
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
        beginCapture()
        event.accepted = true
      } else {
        event.accepted = false
      }
      return
    }
    event.accepted = processCaptureKey(event.key, event.modifiers, event.text)
  }

  Keys.onReleased: function(event) {
    if (!capturing) return
    var mod = modifierName(event.key)
    if (mod !== "")
      heldMods = heldMods.filter(function(m) { return m !== mod })
  }

  // The capture state machine, callable both from real key events and
  // from verification IPC (synthetic codes) — one code path, so what the
  // tests drive is what the keyboard drives.
  // Returns true when the event was consumed.
  function processCaptureKey(key, modifiers, text) {
    if (key === Qt.Key_Escape) {
      endCapture()
      if (root.chord !== "") checkConflicts(root.chord)
      return true
    }
    // Swallow Enter while capturing so it cannot bubble up and trigger
    // the wizard's advance / the editor's focused buttons.
    if (key === Qt.Key_Return || key === Qt.Key_Enter) return true
    if (key === Qt.Key_Backspace) {
      setChord("")
      endCapture()
      return true
    }

    // The full-chord contract: modifier-only presses (in any order, any
    // number) update the live display and keep waiting; the first
    // non-modifier key completes the chord, taking its modifier state
    // from the event itself.
    var mod = modifierName(key)
    if (mod !== "") {
      captureHint = ""
      if (heldMods.indexOf(mod) < 0) heldMods = heldMods.concat([mod])
      return true
    }
    if (ignoredKeyName(key)) return true

    var name = keyNameFor(key, text)
    if (name === "") {
      captureHint = qsTr("That key can’t be bound — use a letter, number or F-key")
      return true
    }
    var mods = []
    if (modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (modifiers & Qt.AltModifier) mods.push("ALT")
    if (modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (mods.length === 0) {
      // A capture hint, not a chord conflict — conflictText blocks saving.
      captureHint = qsTr("Add a modifier — bare keys type into apps.")
      return true
    }
    var chord = mods.join(" + ") + " + " + name
    endCapture()
    setChord(chord)
    return true
  }

  // Key name for the chord's final key. The key CODE is preferred over
  // the key text: the code is layout- and shift-stable (SHIFT+1 records
  // "1", not "!"), while text under Ctrl is a control character and
  // under Shift is the shifted glyph — neither makes a Hyprland chord.
  function keyNameFor(key, text) {
    var fromCode = keyFromCode(key)
    if (fromCode !== "") return fromCode
    if (text && text.length === 1 && text.charCodeAt(0) >= 33 && text.charCodeAt(0) <= 126)
      return keyName(text)
    return ""
  }

  // "" when the code has no chord-safe name (the caller keeps capturing
  // and hints the user instead of committing garbage like "SUPER + ?").
  function keyFromCode(code) {
    if (code >= Qt.Key_A && code <= Qt.Key_Z) return String.fromCharCode(code)
    if (code >= Qt.Key_0 && code <= Qt.Key_9) return String.fromCharCode(code)
    if (code >= Qt.Key_F1 && code <= Qt.Key_F35) return "F" + (code - Qt.Key_F1 + 1)
    var punct = {
      "44": "comma", "46": "period", "47": "slash", "59": "semicolon",
      "39": "apostrophe", "91": "bracketleft", "93": "bracketright",
      "92": "backslash", "45": "minus", "61": "equal", "96": "grave"
    }
    return punct[String(code)] || ""
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: root.compact ? Style.space(6) : Style.space(10)

    // capture well — reads as an editable control: the chord in bold,
    // a pencil affordance on hover, accent ring while capturing.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: root.compact ? Style.space(46) : Style.space(76)
      radius: Style.cornerRadius + 2
      color: capturing ? Qt.alpha(Color.accent, 0.10)
        : (wellMouse.containsMouse ? Qt.alpha(Color.foreground, 0.08) : Qt.alpha(Color.foreground, 0.04))
      border.width: capturing ? 2 : 1
      border.color: capturing || root.activeFocus ? Color.accent : Color.popups.border
      Behavior on border.color { ColorAnimation { duration: 140 } }
      Behavior on color { ColorAnimation { duration: 140 } }

      MouseArea {
        id: wellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.beginCapture()
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          // Live while holding: held modifiers build up ("SUPER + SHIFT + …");
          // the completed chord once captured. shownChord keeps the host's
          // `chord` binding intact — see the property comment above.
          text: root.capturing
            ? (root.heldMods.length > 0
               ? root.heldMods.join(" + ") + "  +  …"
               : qsTr("Press a chord…"))
            : (root.shownChord !== "" ? root.shownChord : qsTr("Click, then press a chord"))
          color: root.capturing ? Color.accent
            : (root.shownChord !== "" ? Color.foreground : Color.muted)
          font.family: Style.font.family
          font.pixelSize: root.compact ? Style.font.body
            : (root.capturing || root.shownChord !== "" ? Style.font.subtitle : Style.font.body)
          font.bold: true
          elide: Text.ElideRight
          width: Math.min(implicitWidth, root.width - Style.space(72))
          renderType: Text.NativeRendering
        }

        // editable-control affordance: pencil while hovering, plus while idle
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.capturing
          text: wellMouse.containsMouse ? "󰏫" : "󰏅"
          color: root.shownChord !== "" ? Color.muted : Color.accent
          opacity: wellMouse.containsMouse ? 1 : 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }

      Text {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Style.space(4)
        visible: root.capturing && !root.compact
        text: qsTr("Esc cancels · Backspace clears")
        color: Color.muted
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Math.max(8, Style.font.caption * 0.8)
        renderType: Text.NativeRendering
      }
    }

    // live capture hint (unsupported key pressed, etc.)
    Text {
      visible: root.capturing && root.captureHint !== ""
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: root.captureHint
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      visible: !root.compact && root.shownChord !== ""
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: qsTr("saving rewrites the o.bind(\"%1\", …) line — no orphan binds").arg(root.shownChord)
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
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
        font.pixelSize: root.compact ? Style.font.caption : Style.font.bodySmall
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
