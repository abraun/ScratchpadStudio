import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import ".."

// KeybindStep — the wizard's keybind page. The capture well, conflict
// detection and free-chord suggestions live in the shared KeybindCapture
// (also used by the editor); this step only owns the wizard focus flow:
// grab focus when the step becomes current so capture works without a
// click, and push chords into the draft.
Item {
  id: root

  property var draft: null
  property string selfId: ""            // editing: the scratchpad's own id
  property string selfName: ""
  signal touched()

  Component.onCompleted: {
    if (root.activeFocus) capture.forceCapture()
  }

  Connections {
    target: root
    function onActiveFocusChanged() {
      if (root.activeFocus) capture.forceCapture()
    }
  }

  function forceCapture() {
    capture.forceCapture()
  }

  // True when the draft's chord is taken (another scratchpad, an Omarchy
  // default, the user's own config) — the host must refuse to save.
  readonly property alias blockingConflict: capture.blockingConflict

  KeybindCapture {
    id: capture
    anchors.fill: parent
    chord: root.draft ? root.draft.keybind : ""
    selfId: root.selfId
    selfName: root.selfName
    onChordEdited: function(chord) {
      if (!root.draft) return
      root.draft.keybind = chord
      root.touched()
    }
  }
}
