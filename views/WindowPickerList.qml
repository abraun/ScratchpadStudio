import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../lib/WindowIdentity.js" as WindowIdentity

// WindowPickerList — live desktop windows to capture into a scratchpad:
// one row per window (workspace number, class, title), search box, click
// or Enter to capture. Data comes from the helper's windows-json (regular
// workspaces only, the studio's own window excluded) so rows carry the
// exact address the capture command moves.
Item {
  id: root

  property bool compact: false
  signal picked(var window)
  signal escapeRequested()

  property string query: ""
  property var windows: []
  property int cursor: 0
  property bool loading: true

  readonly property var filtered: {
    var q = query.trim().toLowerCase()
    var out = []
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      var cls = String(win.class || "")
      if (q !== "" && cls.toLowerCase().indexOf(q) < 0
          && win.title.toLowerCase().indexOf(q) < 0
          && String(win.workspace).indexOf(q) < 0) continue
      out.push(win)
    }
    return out.slice(0, 60)
  }

  onFilteredChanged: cursor = 0

  Component.onCompleted: windowsProc.running = true

  function pickCursor() {
    var list = filtered
    if (cursor < 0 || cursor >= list.length) return
    picked(list[cursor])
  }

  function moveCursor(delta) {
    var list = filtered
    if (list.length === 0) return
    cursor = Math.min(list.length - 1, Math.max(0, cursor + delta))
  }

  function focusSearch() {
    search.forceActiveFocus()
  }

  Process {
    id: windowsProc
    command: ["bash", "-c",
      decodeURIComponent(Qt.resolvedUrl("../bin/scratchpad-studio").toString()
        .replace(/^file:\/\//, "")) + " windows-json 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        try { root.windows = JSON.parse(text) }
        catch (e) { root.windows = [] }
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    TextField {
      id: search
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(32)
      placeholderText: qsTr("Search windows (class, title or workspace)…")
      text: root.query
      color: Color.foreground
      placeholderTextColor: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      selectByMouse: true
      background: Rectangle {
        radius: Style.cornerRadius
        color: Qt.alpha(Color.foreground, 0.05)
        border.width: search.activeFocus ? 2 : 1
        border.color: search.activeFocus ? Color.accent : Color.popups.border
      }
      onTextChanged: { root.query = text; root.cursor = 0 }
      onAccepted: root.pickCursor()
      Keys.onDownPressed: { root.moveCursor(1); event.accepted = true }
      Keys.onUpPressed: { root.moveCursor(-1); event.accepted = true }
      Keys.onEscapePressed: root.escapeRequested()
      Component.onCompleted: forceActiveFocus()
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      radius: Style.cornerRadius
      color: Qt.alpha(Color.background, 0.45)
      border.width: 1
      border.color: Color.popups.border

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: listColumn
          width: parent.width
          spacing: 2

          Repeater {
            model: root.filtered

            Item {
              id: row
              required property var modelData
              required property int index
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(36)
              readonly property var win: modelData
              readonly property bool byKeyboard:
                root.cursor === index && search.activeFocus

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius - 2
                color: row.byKeyboard || rowMouse.containsMouse
                  ? Qt.alpha(Color.foreground, 0.08) : "transparent"
                border.width: row.byKeyboard ? 2 : 0
                border.color: Color.accent
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(row.win)
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                // app identity: themed icon from the class's desktop entry,
                // letter fallback - a row never renders without an identity
                Item {
                  Layout.preferredWidth: Style.space(24)
                  Layout.preferredHeight: Style.space(24)
                  Image {
                    id: appIcon
                    anchors.fill: parent
                    source: WindowIdentity.iconUrl(Quickshell, DesktopEntries, row.win.class)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: appIcon.status !== Image.Ready
                    text: WindowIdentity.initial(row.win.class, row.win.title)
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    renderType: Text.NativeRendering
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  Text {
                    Layout.fillWidth: true
                    text: WindowIdentity.appName(DesktopEntries, row.win.class, row.win.title)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    renderType: Text.NativeRendering
                  }
                  Text {
                    Layout.fillWidth: true
                    text: row.win.title !== "" ? row.win.title : row.win.class
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: root.compact
                      ? Math.max(8, Style.font.caption * 0.85) : Style.font.caption
                    renderType: Text.NativeRendering
                  }
                }

                Rectangle {
                  Layout.preferredWidth: Style.space(34)
                  Layout.preferredHeight: Style.space(22)
                  radius: Style.cornerRadius - 2
                  color: Qt.alpha(Color.accent, 0.12)
                  Text {
                    anchors.centerIn: parent
                    text: row.win.workspace
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    renderType: Text.NativeRendering
                  }
                }
              }
            }
          }

          Text {
            visible: !root.loading && root.filtered.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(16)
            text: root.loading ? qsTr("Loading windows…")
              : (root.query.trim() !== "" ? qsTr("No matches") : qsTr("No desktop windows to capture"))
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }
}
