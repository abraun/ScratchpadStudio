import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "views"

// StudioWindow — the studio as a normal, resizable application window.
//
// Hosted inside the shell process like blip's app window (no second
// Quickshell instance). Same views as the panel; Esc closes the window
// rather than the panel.
FloatingWindow {
  id: root

  property var hostWidget: null
  property var cards: []
  property bool demo: false

  title: "Scratchpad Studio"
  color: Color.background
  implicitWidth: 1040
  implicitHeight: 720
  // The editor's boxes have fixed minimums (apps list + arrangement +
  // keybind + spacing); below ~610px of window height the footer's
  // Cancel/Test/Save row gets pushed past the bottom edge and vanishes —
  // the captain hit exactly that after making the window shorter.
  minimumSize: Qt.size(740, 620)
  visible: false

  // The editor draft of THIS surface, for the widget's IPC inspection
  // (verification and screenshots).
  readonly property var editorDraft: winEditor.draft



  // Subtle theme-consistent depth behind the content.
  Rectangle {
    anchors.fill: parent
    color: Qt.alpha(Color.foreground, 0.02)
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    // ---------- header ----------
    Item {
      width: parent.width
      height: Style.space(32)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: qsTr("Scratchpad Studio")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        renderType: Text.NativeRendering
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(0)
        visible: root.demo
        text: ""
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.demo
          iconText: "󰀫"
          tooltipText: qsTr("Demo mode — fake data")
          size: Style.space(26)
        }

        Button {
          anchors.verticalCenter: parent.verticalCenter
          text: hostWidget && hostWidget.detail !== "" ? qsTr("Back to overview") : qsTr("New scratchpad")
          iconText: hostWidget && hostWidget.detail !== "" ? "󰁙" : "󰐗"
          fontSize: Style.font.bodySmall
          onClicked: {
            if (hostWidget) hostWidget.detail !== "" ? hostWidget.closeDetail() : hostWidget.newScratchpad()
          }
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: Color.popups.border; opacity: 0.6 }

    // ---------- content: overview, wizard, or editor (mirrors the panel) ----------
    Item {
      id: windowContent
      width: parent.width
      height: parent.height - Style.space(32) - Style.space(10) - 2 - Style.space(10)

      // The delete dialog owns the keyboard while open (arrows move its
      // selection, Enter confirms, Esc cancels) — the content item holds
      // focus in overview mode, so keys arrive here first.
      Keys.onPressed: function(event) {
        if (winDeleteDialog.opened) event.accepted = winDeleteDialog.handleKey(event)
      }

      Overview {
        id: overview
        anchors.fill: parent
        visible: !(hostWidget && hostWidget.detail !== "")
        cards: root.cards
        demo: root.demo

        onToggleRequested: function(card) { hostWidget && hostWidget.toggleScratchpad(card) }
        onEditRequested: function(card) { hostWidget && hostWidget.editScratchpad(card) }
        onDeleteRequested: function(card) { hostWidget && hostWidget.deleteScratchpad(card) }
        onCaptureRequested: function(card) { hostWidget && hostWidget.requestCapture(card) }
        onDuplicateRequested: function(card) { hostWidget && hostWidget.duplicateScratchpad(card) }
        onAdoptRequested: function(card) { hostWidget && hostWidget.helper(["adopt", card.id]) }
        onNewRequested: hostWidget && hostWidget.newScratchpad()
      }

      Wizard {
        visible: hostWidget && hostWidget.detail === "wizard"
        anchors.fill: parent
        editScratchpad: hostWidget ? hostWidget.wizardScratchpad : null
        duplicate: hostWidget ? hostWidget.wizardDuplicate : false
        demo: root.demo
        existingIds: hostWidget ? hostWidget.stateIds : []
        monitor: {
          var m = Hyprland.focusedMonitor
          return m ? { width: m.width || 0, height: m.height || 0, scale: m.scale || 1, name: m.name || "" } : null
        }

        onFinished: function(sp) { hostWidget && hostWidget.closeDetail() }
        onCanceled: hostWidget && hostWidget.closeDetail()
      }

      Editor {
        id: winEditor
        visible: hostWidget && hostWidget.detail === "editor"
        anchors.fill: parent
        editScratchpad: hostWidget ? hostWidget.editorScratchpad : null
        demo: root.demo
        monitor: {
          var em = Hyprland.focusedMonitor
          return em ? { width: em.width || 0, height: em.height || 0, scale: em.scale || 1, name: em.name || "" } : null
        }

        onSaved: function(sp) { hostWidget && hostWidget.closeDetail() }
        onCanceled: hostWidget && hostWidget.closeDetail()
        onCaptureRequested: {
          if (hostWidget && hostWidget.editorScratchpad)
            hostWidget.requestCapture(hostWidget.editorScratchpad)
        }
      }

      // Delete confirm centered over the window content (the panel hosts
      // its own copy); `deleteOpen` on the shared widget drives both, so
      // confirming in either surface closes both.
      ConfirmDialog {
        id: winDeleteDialog
        anchors.fill: parent
        opened: hostWidget ? hostWidget.deleteOpen : false
        message: hostWidget && hostWidget.deleteTarget
          ? qsTr("Delete “%1”? Its windows move to the current workspace and stay open.").arg(hostWidget.deleteTarget.name)
          : ""
        confirmText: qsTr("Delete")
        onConfirmed: hostWidget && hostWidget.confirmDelete()
        onCanceled: hostWidget && hostWidget.cancelDelete()
      }

      // Live-window capture picker over the window content; the panel
      // hosts its own copy driven by the same captureOpen flag.
      Rectangle {
        anchors.fill: parent
        visible: hostWidget ? hostWidget.captureOpen : false
        radius: Style.cornerRadius
        color: Qt.alpha(Color.background, 0.92)
        border.width: 1
        border.color: Color.popups.border

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: hostWidget
                ? qsTr("Capture a window into “%1”").arg(hostWidget.captureTargetName)
                : ""
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
              onClicked: hostWidget && hostWidget.cancelCaptureWindow()
            }
          }

          WindowPickerList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            onPicked: function(win) {
              if (hostWidget) {
                hostWidget.helper(["capture", hostWidget.captureTargetId, "--address", win.address])
                hostWidget.cancelCaptureWindow()
              }
            }
            onEscapeRequested: hostWidget && hostWidget.cancelCaptureWindow()
          }
        }
      }
    }
  }

  // FloatingWindow is a Window, not an Item — Keys doesn't attach, so a
  // Shortcut on the content does Esc-close instead. Esc backs out of the
  // delete confirm or the capture picker before it ever closes the window.
  Shortcut {
    sequence: "Esc"
    context: Qt.WindowShortcut
    onActivated: {
      if (root.hostWidget && root.hostWidget.deleteOpen) root.hostWidget.cancelDelete()
      else if (root.hostWidget && root.hostWidget.captureOpen) root.hostWidget.cancelCaptureWindow()
      else root.visible = false
    }
  }
  Component.onCompleted: root.contentItem.forceActiveFocus()

  // Hiding the window cancels any pending delete confirm — the shared
  // `deleteOpen` must not resurface the dialog next time the window opens.
  onVisibleChanged: if (!visible && hostWidget) hostWidget.cancelDelete()
}
