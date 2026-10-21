import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import ".."

// AppsStep — pick what lives in the scratchpad. The picker itself is the
// shared AppPickerList (also used by the editor's add-app overlay); this
// step owns the draft's app list and shows it as removable chips.
Item {
  id: root

  property var draft: null
  property bool demo: false
  signal touched()

  function addApp(app) {
    if (!draft) return
    for (var i = 0; i < draft.apps.length; i++) {
      if (draft.apps[i].class === app.class) return
    }
    draft.apps.push(app)
    touched()
  }

  function removeApp(index) {
    if (!draft) return
    draft.apps.splice(index, 1)
    touched()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    AppPickerList {
      id: picker
      Layout.fillWidth: true
      Layout.fillHeight: true
      demo: root.demo
      pickedClasses: root.draft
        ? root.draft.apps.map(function (a) { return a.class })
        : []
      onPicked: function(app) { root.addApp(app) }
    }

    // chosen apps
    Text {
      visible: root.draft && root.draft.apps.length > 0
      text: qsTr("In this scratchpad")
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Flow {
      visible: root.draft && root.draft.apps.length > 0
      Layout.fillWidth: true
      spacing: Style.space(6)

      Repeater {
        model: root.draft ? root.draft.apps.length : 0

        Rectangle {
          required property int index
          readonly property var app: root.draft ? root.draft.apps[index] : null
          width: chipRow.implicitWidth + Style.space(30)
          height: Style.space(26)
          radius: height / 2
          color: Qt.alpha(Color.accent, 0.10)
          border.width: 1
          border.color: Qt.alpha(Color.accent, 0.35)

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: app ? app.name : ""
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: app ? (app.webapp ? "web" : (app.singleInstance ? "single" : app.class)) : ""
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅖"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.removeApp(index)
            }
          }
        }
      }
    }
  }
}
