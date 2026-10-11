import QtQuick
import qs.Commons
import qs.Ui

// EmptyState — a real empty state, not a stub: what a scratchpad is, and the
// two ways to get one (create fresh, or adopt an existing special workspace).
Item {
  id: root

  signal newRequested()

  Column {
    anchors.centerIn: parent
    spacing: Style.space(10)
    width: Math.min(parent.width - Style.space(48), Style.space(360))

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "󰎞"
      textFormat: Text.PlainText
      color: Color.muted
      opacity: 0.9
      font.family: Style.font.family
      font.pixelSize: Style.font.displayLarge
      renderType: Text.NativeRendering
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: qsTr("No scratchpads yet")
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      renderType: Text.NativeRendering
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: qsTr("A scratchpad is a named set of windows that slides in on a keybind and hides away when you're done. Create one for browsing, AI, music — whatever you want one chord away.")
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      lineHeight: 1.35
      renderType: Text.NativeRendering
    }

    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: Style.space(6)
      text: qsTr("New scratchpad")
      iconText: "󰐗"
      fontSize: Style.font.subtitle
      onClicked: root.newRequested()
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: false // shown once an existing special workspace is adoptable
      text: qsTr("Existing special workspaces appear here and can be adopted.")
      color: Color.muted
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }
}
