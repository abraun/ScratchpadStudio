import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../lib/Layout.js" as LayoutMath

// LayoutStep — pick the window arrangement, anchor, size and margin, with a
// live preview drawn from the same math the engine bakes into rules.
Item {
  id: root

  property var draft: null
  property var usable: [1800, 1125]
  signal touched()

  readonly property var layouts: LayoutMath.LAYOUTS

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    // layout thumbnails
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Repeater {
        model: root.layouts

        Rectangle {
          required property var modelData
          readonly property bool chosen: root.draft && root.draft.layout === modelData.id
          width: Style.space(96)
          height: Style.space(84)
          radius: Style.cornerRadius
          color: chosen ? Qt.alpha(Color.accent, 0.12) : Qt.alpha(Color.foreground, 0.04)
          border.width: chosen ? 2 : 1
          border.color: chosen ? Color.accent : Color.popups.border
          Behavior on border.color { ColorAnimation { duration: 140 } }
          Behavior on color { ColorAnimation { duration: 140 } }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              root.draft.layout = modelData.id
              root.touched()
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(5)

            // thumbnail: normalized slot boxes
            Item {
              width: Style.space(64)
              height: Style.space(40)
              Repeater {
                model: LayoutMath.thumbBoxes(modelData.id, Math.max(1, root.draft ? root.draft.apps.length : 1))
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

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(16)

      // anchor
      ColumnLayout {
        spacing: Style.space(4)
        Text {
          text: qsTr("Anchor")
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
        Row {
          spacing: Style.space(4)
          Repeater {
            model: ["top", "bottom", "left", "right"]
            Button {
              required property string modelData
              text: modelData
              fontSize: Style.font.bodySmall
              selected: root.draft && root.draft.anchor === modelData
              onClicked: {
                root.draft.anchor = modelData
                root.touched()
              }
            }
          }
        }
      }

      Item { Layout.fillWidth: true; height: 1 }

      // live geometry preview (monitor to scale)
      Item {
        Layout.preferredWidth: Style.space(190)
        Layout.preferredHeight: Style.space(120)

        Rectangle {
          anchors.fill: parent
          radius: 4
          color: Qt.alpha(Color.background, 0.55)
          border.width: 1
          border.color: Color.popups.border

          // screen outline label
          Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 3
            text: root.usable[0] + "×" + root.usable[1]
            color: Color.muted
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Item {
            anchors.fill: parent
            anchors.margins: 3

            Repeater {
              model: {
                if (!root.draft) return []
                var rects = LayoutMath.rects(root.draft, Math.max(1, root.draft.apps.length),
                                         root.usable[0], root.usable[1])
                return rects
              }

              Rectangle {
                required property var modelData
                required property int index
                x: modelData[0] / root.usable[0] * parent.width
                y: modelData[1] / root.usable[1] * parent.height
                width: modelData[2] / root.usable[0] * parent.width
                height: modelData[3] / root.usable[1] * parent.height
                radius: 2
                color: Qt.alpha(Color.accent, 0.18)
                border.width: 1
                border.color: Qt.alpha(Color.accent, 0.6)

                Text {
                  anchors.centerIn: parent
                  visible: parent.width > Style.space(30) && parent.height > Style.space(16)
                  text: root.draft && root.draft.apps[index] ? root.draft.apps[index].name : ""
                  elide: Text.ElideRight
                  width: parent.width - 4
                  horizontalAlignment: Text.AlignHCenter
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }
              }
            }
          }
        }
      }
    }

    // size sliders
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(12)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        RowLayout {
          Layout.fillWidth: true
          Text { text: qsTr("Width"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; renderType: Text.NativeRendering }
          Item { Layout.fillWidth: true; height: 1 }
          Text { text: (root.draft ? root.draft.sizePct.w : 60) + "%"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption; renderType: Text.NativeRendering }
        }
        Slider {
          id: widthSlider
          Layout.fillWidth: true
          from: 30; to: 95
          value: root.draft ? root.draft.sizePct.w : 60
          stepSize: 1
          onMoved: { root.draft.sizePct.w = Math.round(value); root.touched() }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        RowLayout {
          Layout.fillWidth: true
          Text { text: qsTr("Height"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; renderType: Text.NativeRendering }
          Item { Layout.fillWidth: true; height: 1 }
          Text { text: (root.draft ? root.draft.sizePct.h : 50) + "%"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption; renderType: Text.NativeRendering }
        }
        Slider {
          id: heightSlider
          Layout.fillWidth: true
          from: 25; to: 95
          value: root.draft ? root.draft.sizePct.h : 50
          stepSize: 1
          onMoved: { root.draft.sizePct.h = Math.round(value); root.touched() }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        RowLayout {
          Layout.fillWidth: true
          Text { text: qsTr("Margin"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; renderType: Text.NativeRendering }
          Item { Layout.fillWidth: true; height: 1 }
          Text { text: (root.draft ? root.draft.marginPx : 12) + " px"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption; renderType: Text.NativeRendering }
        }
        Slider {
          id: marginSlider
          Layout.fillWidth: true
          from: 0; to: 96
          value: root.draft ? root.draft.marginPx : 12
          stepSize: 2
          onMoved: { root.draft.marginPx = Math.round(value); root.touched() }
        }
      }
    }
  }
}
