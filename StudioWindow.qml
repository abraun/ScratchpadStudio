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
  minimumSize: Qt.size(720, 480)
  visible: false

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
          text: qsTr("New scratchpad")
          iconText: "󰐗"
          fontSize: Style.font.bodySmall
          onClicked: hostWidget && hostWidget.newScratchpad()
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: Color.popups.border; opacity: 0.6 }

    // ---------- content ----------
    Overview {
      id: overview
      width: parent.width
      height: parent.height - Style.space(32) - Style.space(10) - 2 - Style.space(10)
      cards: root.cards
      demo: root.demo

      onToggleRequested: function(card) { hostWidget && hostWidget.toggleScratchpad(card) }
      onEditRequested: function(card) { hostWidget && hostWidget.editScratchpad(card) }
      onDeleteRequested: function(card) { hostWidget && hostWidget.deleteScratchpad(card) }
      onDuplicateRequested: function(card) { hostWidget && hostWidget.duplicateScratchpad(card) }
      onAdoptRequested: function(card) { hostWidget && hostWidget.helper(["adopt", card.id]) }
      onNewRequested: hostWidget && hostWidget.newScratchpad()
    }
  }

  // FloatingWindow is a Window, not an Item — Keys doesn't attach, so a
  // Shortcut on the content does Esc-close instead.
  Shortcut {
    sequence: "Esc"
    context: Qt.WindowShortcut
    onActivated: root.visible = false
  }
  Component.onCompleted: root.contentItem.forceActiveFocus()
}
