import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../lib/Layout.js" as LayoutMath

// SummaryStep — everything about the scratchpad at a glance, a mini
// preview of where it lands on screen, and the "Test it now" button.
Item {
  id: root

  property var draft: null
  property var usable: [1800, 1125]
  signal testNow()

  readonly property var rows: {
    if (!draft) return []
    var appNames = draft.apps.map(function (a) { return a.name })
    return [
      { label: qsTr("Name"), value: draft.name || "—" },
      { label: qsTr("Workspace"), value: "special:" + (draft.id || "…") },
      { label: qsTr("Keybind"), value: draft.keybind !== "" ? draft.keybind : qsTr("none (toggle from the studio)") },
      { label: qsTr("Apps"), value: appNames.length > 0 ? appNames.join(" · ") : qsTr("none yet") },
      { label: qsTr("Windows"), value: draft.placement === "floating" ? qsTr("floating freely") : qsTr("arranged in slots") },
      { label: qsTr("Layout"), value: draft.placement === "floating" ? "—"
          : draft.layout + " · " + draft.anchor + " · "
            + draft.sizePct.w + "%×" + draft.sizePct.h + "% · " + draft.marginPx + "px margin" },
      { label: qsTr("Slide-in"), value: draft.transition }
    ]
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(14)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        Repeater {
          model: root.rows

          RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.preferredWidth: Style.space(84)
              text: modelData.label
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
            Text {
              Layout.fillWidth: true
              text: modelData.value
              elide: Text.ElideRight
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
          }
        }
      }

      // mini screen placement preview
      Rectangle {
        Layout.preferredWidth: Style.space(150)
        Layout.preferredHeight: Style.space(96)
        radius: 4
        color: Qt.alpha(Color.background, 0.55)
        border.width: 1
        border.color: Color.popups.border

        Item {
          anchors.fill: parent
          anchors.margins: 3

          Repeater {
            model: root.draft
              ? LayoutMath.rects(root.draft, Math.max(1, root.draft.apps.length),
                             root.usable[0], root.usable[1])
              : []

            Rectangle {
              required property var modelData
              x: modelData[0] / root.usable[0] * parent.width
              y: modelData[1] / root.usable[1] * parent.height
              width: modelData[2] / root.usable[0] * parent.width
              height: modelData[3] / root.usable[1] * parent.height
              radius: 2
              color: Qt.alpha(Color.accent, 0.18)
              border.width: 1
              border.color: Qt.alpha(Color.accent, 0.6)
            }
          }
        }
      }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.border; opacity: 0.6 }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      lineHeight: 1.3
      renderType: Text.NativeRendering
      text: qsTr("Saving writes the keybind as an o.bind() line in a managed block of your bindings file, regenerates the window rules, and reloads — your own config is never touched outside that block. “Test it now” applies the same config and toggles the scratchpad once, so you can feel the slide before committing. Cancel after testing restores what you had.")
    }

    RowLayout {
      Layout.fillWidth: true

      Button {
        text: qsTr("Test it now")
        iconText: "󰓅"
        fontSize: Style.font.body
        onClicked: root.testNow()
      }

      Item { Layout.fillWidth: true; height: 1 }
    }
  }
}
