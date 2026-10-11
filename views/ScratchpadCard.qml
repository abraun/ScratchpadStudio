import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import ".."

// ScratchpadCard — one scratchpad in the overview grid.
//
// Shows: icon, name, status dot + label, keybind chip, a live schematic of
// the windows inside, and the action row. Foreign specials show Adopt
// instead of Edit; the builtin Omarchy scratchpad keeps its SUPER+S chip
// and loses the destructive actions.
Item {
  id: root

  required property var card
  property bool demo: false
  property bool hasCursor: false

  signal toggleRequested()
  signal editRequested()
  signal duplicateRequested()
  signal deleteRequested()
  signal adoptRequested()

  readonly property color hairline: Color.popups.border
  readonly property color dim: Qt.darker(Color.foreground, 1.45)
  readonly property color statusColor:
    card.status === "shown" ? Color.accent
    : card.status === "running" ? Color.foreground
    : Color.muted

  width: Style.space(288)
  height: Style.space(212)

  Rectangle {
    id: plate
    anchors.fill: parent
    radius: Style.cornerRadius + Style.space(1)
    color: Qt.alpha(Color.foreground, root.hasCursor ? 0.07 : 0.035)
    border.width: root.hasCursor ? 2 : 1
    border.color: root.hasCursor ? Color.accent : root.hairline

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
    Behavior on border.width { NumberAnimation { duration: 120 } }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: root.toggleRequested()
  }

  // ---- header ----
  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(10)
    height: Style.space(28)

    Text {
      id: glyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: card.icon !== "" ? card.icon : "󰎤"
      textFormat: Text.PlainText
      color: Color.foreground
      opacity: 0.92
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      renderType: Text.NativeRendering
    }

    Column {
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - glyph.width - Style.space(8) - metaRow.width - Style.space(8)
      spacing: 0

      Text {
        width: parent.width
        text: card.name
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        renderType: Text.NativeRendering
      }
      Text {
        width: parent.width
        text: subtitle()
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    Row {
      id: metaRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Rectangle {
        id: statusDot
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        height: width
        radius: width / 2
        color: root.statusColor
        opacity: root.card.status === "idle" ? 0.55 : 1

        SequentialAnimation on opacity {
          running: root.card.status === "shown" && !root.demo
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.45; to: 1; duration: 1100; easing.type: Easing.InOutSine }
        }
      }

      Chip {
        anchors.verticalCenter: parent.verticalCenter
        label: card.keybind !== "" ? card.keybind : "no key"
        emphasized: card.keybind !== ""
      }
    }
  }

  // ---- live schematic ----
  Rectangle {
    id: preview
    anchors.top: header.bottom
    anchors.topMargin: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(10)
    height: parent.height - header.height - actions.height - Style.space(10) * 2 - Style.space(8)
    radius: Math.max(2, Style.cornerRadius - Style.space(1))
    color: Qt.alpha(Color.background, 0.5)
    border.width: 1
    border.color: Qt.alpha(root.hairline, 0.6)

    Schematic {
      anchors.fill: parent
      anchors.margins: Style.space(4)
      windows: root.card.windows
    }

    Text {
      anchors.centerIn: parent
      visible: root.card.windows.length === 0
      text: emptyHint()
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }
  }

  // ---- actions ----
  Row {
    id: actions
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(10)
    spacing: Style.space(6)

    Button {
      text: root.card.status === "shown" ? qsTr("Hide") : qsTr("Show")
      height: Style.space(28)
      width: parent.width - editBtn.width - copyBtn.width - deleteBtn.width - parent.spacing * 3
      fontSize: Style.font.bodySmall
      iconText: root.card.status === "shown" ? "󰈈" : "󰈄"
      onClicked: root.toggleRequested()
    }
    Button {
      id: editBtn
      visible: root.card.editable || root.card.adoptable
      text: root.card.adoptable ? qsTr("Adopt") : qsTr("Edit")
      height: Style.space(28)
      fontSize: Style.font.bodySmall
      iconText: root.card.adoptable ? "󰐗" : "󰏫"
      onClicked: root.card.adoptable ? root.adoptRequested() : root.editRequested()
    }
    Button {
      id: copyBtn
      visible: root.card.editable
      text: qsTr("Copy")
      tooltipText: qsTr("Duplicate this scratchpad")
      height: Style.space(28)
      fontSize: Style.font.bodySmall
      iconText: "󰆏"
      onClicked: root.duplicateRequested()
    }
    Button {
      id: deleteBtn
      visible: root.card.origin !== "builtin"
      text: qsTr("Delete")
      height: Style.space(28)
      fontSize: Style.font.bodySmall
      foreground: Color.urgent
      iconText: "󰪮"
      onClicked: root.deleteRequested()
    }
  }

  function subtitle() {
    if (card.origin === "builtin") return "Omarchy built-in"
    if (card.origin === "foreign") return "existing workspace"
    var apps = card.apps.length
    var wins = card.windows.length
    if (apps === 0 && wins === 0) return "no apps yet"
    var bits = []
    bits.push(apps === 1 ? "1 app" : apps + " apps")
    bits.push(wins === 1 ? "1 window" : wins + " windows")
    return bits.join(" · ")
  }

  function emptyHint() {
    if (card.origin !== "managed") return "empty"
    return card.apps.length > 0 ? "launches on first toggle" : "empty"
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool emphasized: false
    height: Style.space(18)
    width: labelText.width + Style.space(10)
    radius: height / 2
    color: emphasized ? Qt.alpha(Color.accent, 0.16) : Qt.alpha(Color.foreground, 0.06)
    border.width: 1
    border.color: emphasized ? Qt.alpha(Color.accent, 0.5) : Qt.alpha(Color.foreground, 0.12)

    Text {
      id: labelText
      anchors.centerIn: parent
      text: chip.label
      textFormat: Text.PlainText
      color: chip.emphasized ? Color.accent : Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }
}
