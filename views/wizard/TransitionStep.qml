import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// TransitionStep — where the scratchpad slides in from, with a small
// animated preview. The reveal itself is Hyprland's specialWorkspace slide;
// this choice sets the anchor default and the per-window animation rule so
// newly mapped windows enter from the same side.
Item {
  id: root

  property var draft: null
  signal touched()

  readonly property var directions: [
    { id: "down",  label: qsTr("From top"),    glyph: "󰁝", anchor: "top" },
    { id: "up",    label: qsTr("From bottom"), glyph: "󰁅", anchor: "bottom" },
    { id: "right", label: qsTr("From left"),   glyph: "󰁔", anchor: "left" },
    { id: "left",  label: qsTr("From right"),  glyph: "󰁠", anchor: "right" },
    { id: "popin", label: qsTr("Centered"),    glyph: "◎", anchor: "center" }
  ]

  function choose(direction) {
    draft.transition = direction.id
    draft.anchor = direction.anchor
    touched()
    slider.t = 0
    slide.restart()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)

    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Repeater {
        model: root.directions

        Rectangle {
          required property var modelData
          readonly property bool chosen: root.draft && root.draft.transition === modelData.id
          width: Style.space(104)
          height: Style.space(72)
          radius: Style.cornerRadius
          color: chosen ? Qt.alpha(Color.accent, 0.12) : Qt.alpha(Color.foreground, 0.04)
          border.width: chosen ? 2 : 1
          border.color: chosen ? Color.accent : Color.popups.border
          Behavior on border.color { ColorAnimation { duration: 140 } }
          Behavior on color { ColorAnimation { duration: 140 } }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.choose(modelData)
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.glyph
              color: chosen ? Color.accent : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.iconLarge
              renderType: Text.NativeRendering
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

    // Motion preview: a mini screen with the panel sliding in from the
    // chosen side. t goes 0 (out) -> 1 (in); position lerps between them.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(170)
      radius: Style.cornerRadius
      color: Qt.alpha(Color.background, 0.5)
      border.width: 1
      border.color: Color.popups.border
      clip: true

      // progress of the slide, driven by the animation below
      property real t: 0

      SequentialAnimation {
        id: slide
        running: true
        loops: Animation.Infinite
        NumberAnimation { target: previewScreen; property: "t"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 620 }
        NumberAnimation { target: previewScreen; property: "t"; from: 1; to: 0; duration: 200; easing.type: Easing.InCubic }
        PauseAnimation { duration: 320 }
      }

      id: previewScreen

      Rectangle {
        id: slidingPanel
        readonly property string dir: root.draft ? root.draft.transition : "down"
        readonly property real w: parent.width * 0.6
        readonly property real h: parent.height * 0.5
        readonly property real inX: (dir === "right" || dir === "left")
          ? (dir === "right" ? Style.space(10) : parent.width - w - Style.space(10))
          : (parent.width - w) / 2
        readonly property real inY: (dir === "down" || dir === "up")
          ? (dir === "down" ? Style.space(10) : parent.height - h - Style.space(10))
          : (parent.height - h) / 2
        readonly property real outX: (dir === "right" || dir === "left")
          ? (dir === "right" ? -w : parent.width)
          : inX
        readonly property real outY: (dir === "down" || dir === "up")
          ? (dir === "down" ? -h : parent.height)
          : inY
        // popin (centered anchor): the frame stays put and scales in —
        // the popin animation the engine bakes for this transition.
        scale: dir === "popin" ? 0.35 + 0.65 * previewScreen.t : 1
        opacity: dir === "popin" ? previewScreen.t : 1
        width: w
        height: h
        radius: Style.cornerRadius - 2
        color: Qt.alpha(Color.accent, 0.16)
        border.width: 1
        border.color: Qt.alpha(Color.accent, 0.55)
        x: outX + (inX - outX) * previewScreen.t
        y: outY + (inY - outY) * previewScreen.t

        Column {
          anchors.centerIn: parent
          spacing: 3
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.draft ? (root.draft.icon || "󰎤") : ""
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.draft ? root.draft.name : ""
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      lineHeight: 1.3
      renderType: Text.NativeRendering
      text: qsTr("The reveal is Hyprland's special-workspace slide. Your pick sets the anchor and the per-window animation, so the scratchpad enters the way it sits — a top drop-down anchors top and slides down, a left drawer anchors left, and the centered pick anchors center and pops in.")
    }
  }
}
