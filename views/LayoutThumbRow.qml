import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../lib/Layout.js" as LayoutMath

// LayoutThumbRow — the arrangement picker: window placement (arranged in
// slots vs floating freely) plus layout thumbnails for slot arrangements.
// Shared by the wizard's LayoutStep and the editor. The placement choice
// exists because windows on a scratchpad either follow the baked slot
// geometry (float + size/move rules) or float at their own size — the
// browser-in-a-slot vs free-floating-window distinction.
Item {
  id: root

  property string layoutId: "single"
  property string placement: "slots"      // "slots" | "floating"
  property int count: 1
  signal layoutChosen(string layoutId)
  signal placementChosen(string placement)

  implicitHeight: placementRow.implicitHeight
     + (placement === "slots" ? thumbs.implicitHeight + Style.space(8) : 0)

  ColumnLayout {
    id: column
    anchors.fill: parent
    spacing: Style.space(8)

    // placement segmented control
    Row {
      id: placementRow
      spacing: Style.space(6)

      Repeater {
        model: [
          { id: "slots", label: qsTr("Arranged in slots"), glyph: "󰁃" },
          { id: "floating", label: qsTr("Floating"), glyph: "󰐰" }
        ]

        Button {
          required property var modelData
          text: modelData.glyph + "  " + modelData.label
          fontSize: Style.font.bodySmall
          selected: root.placement === modelData.id
          onClicked: root.placementChosen(modelData.id)
        }
      }
    }

    // thumbnails (only meaningful when windows are arranged in slots)
    Flow {
      id: thumbs
      visible: root.placement === "slots"
      Layout.fillWidth: true
      spacing: Style.space(8)

      Repeater {
        model: LayoutMath.LAYOUTS

        Rectangle {
          required property var modelData
          readonly property bool chosen: root.layoutId === modelData.id
          width: Style.space(92)
          height: Style.space(80)
          radius: Style.cornerRadius
          color: chosen ? Qt.alpha(Color.accent, 0.12) : Qt.alpha(Color.foreground, 0.04)
          border.width: chosen ? 2 : 1
          border.color: chosen ? Color.accent : Color.popups.border
          Behavior on border.color { ColorAnimation { duration: 140 } }
          Behavior on color { ColorAnimation { duration: 140 } }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.layoutChosen(modelData.id)
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(5)

            // thumbnail: normalized slot boxes
            Item {
              width: Style.space(60)
              height: Style.space(38)
              Repeater {
                model: LayoutMath.thumbBoxes(modelData.id, Math.max(1, root.count))
                Rectangle {
                  required property var modelData
                  x: modelData.x * parent.width
                  y: modelData.y * parent.height
                  width: modelData.w * parent.width
                  height: modelData.h * parent.height
                  radius: 2
                  color: chosen ? Qt.alpha(Color.accent, 0.45) : Qt.alpha(Color.foreground, 0.22)
                  border.width: 1
                  border.color: chosen ? Color.accent : Qt.alpha(Color.foreground, 0.35)
                }
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.label
              color: chosen ? Color.foreground : Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }
        }
      }
    }

    Text {
      visible: root.placement === "floating"
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: qsTr("Windows open floating at their own size and stay where you put them — no slot geometry. Arrange them once on screen; the scratchpad remembers their positions for the session.")
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      lineHeight: 1.3
      renderType: Text.NativeRendering
    }
  }
}
