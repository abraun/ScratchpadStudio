import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// BasicsStep — name and icon glyph, with a live card preview of the header.
Item {
  id: root

  property var draft: null
  signal touched()

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)

      Text {
        text: qsTr("Name")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      TextField {
        id: nameField
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(34)
        placeholderText: qsTr("Music, AI, Browsing…")
        text: root.draft ? root.draft.name : ""
        color: Color.foreground
        placeholderTextColor: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        selectByMouse: true
        background: Rectangle {
          radius: Style.cornerRadius
          color: Qt.alpha(Color.foreground, 0.05)
          border.width: nameField.activeFocus ? 2 : 1
          border.color: nameField.activeFocus ? Color.accent : Color.popups.border
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }
        onTextChanged: {
          if (!root.draft) return
          root.draft.name = text
          root.draft.id = slugify(text)
          root.touched()
        }
        Keys.onEscapePressed: event.accepted = false  // wizard handles Esc
        Component.onCompleted: forceActiveFocus()
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)

      Text {
        text: qsTr("Icon (any Nerd Font glyph, optional)")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        TextField {
          id: iconField
          Layout.preferredWidth: Style.space(80)
          Layout.preferredHeight: Style.space(34)
          text: root.draft ? root.draft.icon : ""
          horizontalAlignment: TextInput.AlignHCenter
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          selectByMouse: true
          background: Rectangle {
            radius: Style.cornerRadius
            color: Qt.alpha(Color.foreground, 0.05)
            border.width: iconField.activeFocus ? 2 : 1
            border.color: iconField.activeFocus ? Color.accent : Color.popups.border
          }
          onTextChanged: {
            if (!root.draft) return
            root.draft.icon = text
            root.touched()
          }
        }

        Repeater {
          model: ["󰎈", "󰈹", "󰚩", "󰍹", "󰖟", "󰓓", "󰗃", "󰎞"]

          Button {
            required property string modelData
            Layout.preferredWidth: Style.space(34)
            Layout.preferredHeight: Style.space(34)
            text: modelData
            fontSize: Style.font.subtitle
            onClicked: {
              iconField.text = modelData
              root.touched()
            }
          }
        }
      }
    }

    Item { Layout.fillHeight: true; Layout.fillWidth: true }

    // Live preview of the card header
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(64)
      radius: Style.cornerRadius + Style.space(1)
      color: Qt.alpha(Color.foreground, 0.035)
      border.width: 1
      border.color: Color.popups.border

      Row {
        anchors.centerIn: parent
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.draft && root.draft.icon !== "" ? root.draft.icon : "󰎤"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          renderType: Text.NativeRendering
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.draft && root.draft.name !== ""
            ? root.draft.name
            : qsTr("Scratchpad name")
          color: root.draft && root.draft.name !== "" ? Color.foreground : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          renderType: Text.NativeRendering
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.draft && root.draft.id !== ""
          text: "special:" + (root.draft ? root.draft.id : "")
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }
    }
  }

  function slugify(text) {
    var s = String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    return s.length > 0 ? s.slice(0, 32) : ""
  }
}
