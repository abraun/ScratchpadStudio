import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../lib/WindowIdentity.js" as WindowIdentity

// AppPickerList — the shared app picker: installed apps, running windows,
// or a custom command/URL, one search box for all three. Used by the
// wizard's AppsStep and the editor's add-app overlay. Emits fully-formed
// app objects on `picked`; duplicate classes are highlighted via
// `pickedClasses` so both surfaces show what is already in the scratchpad.
//
// Keyboard: type to filter, Down/Up move the cursor, Enter picks the
// highlighted row (or adds the custom entry in Custom mode), Esc bubbles
// out via `escapeRequested`.
Item {
  id: root

  property bool demo: false
  property bool compact: false
  property var pickedClasses: []          // ["atlas", ...] — shows the ✓ state
  signal picked(var app)
  signal escapeRequested()

  property string query: ""
  property int source: 0                  // 0 installed, 1 running, 2 custom
  property var catalogue: []
  property var catalogueError: ""
  property var runningApps: []
  property int cursor: 0                  // highlighted row (keyboard)

  readonly property var filteredInstalled: {
    var q = query.trim().toLowerCase()
    if (q === "") return catalogue.slice(0, 60)
    return catalogue.filter(function (a) {
      return a.name.toLowerCase().indexOf(q) >= 0
        || String(a.wmClass || "").toLowerCase().indexOf(q) >= 0
        || a.id.toLowerCase().indexOf(q) >= 0
    }).slice(0, 60)
  }

  readonly property var filteredRunning: {
    var seen = {}
    var out = []
    var q = query.trim().toLowerCase()
    for (var i = 0; i < runningApps.length; i++) {
      var w = runningApps[i]
      if (seen[w.cls]) continue
      seen[w.cls] = true
      if (q !== "" && w.cls.toLowerCase().indexOf(q) < 0
          && w.title.toLowerCase().indexOf(q) < 0) continue
      out.push(w)
    }
    return out.slice(0, 40)
  }

  readonly property var activeList:
    source === 0 ? filteredInstalled : source === 1 ? filteredRunning : []

  onActiveListChanged: cursor = 0

  Component.onCompleted: {
    refreshRunning()
    if (!demo) appsProc.running = true
    else catalogue = demoCatalogue()
  }

  function refreshRunning() {
    var seen = {}
    var out = []
    var items = Hyprland.toplevels.values
    for (var i = 0; i < items.length; i++) {
      var w = items[i]
      var ipc = w.lastIpcObject || {}
      var wsName = w.workspace ? String(w.workspace.name) : ""
      if (wsName.indexOf("special:") === 0) continue
      var cls = String(ipc.class || (w.wayland ? w.wayland.appId : "") || "")
      if (cls === "" || seen[cls]) continue
      seen[cls] = true
      out.push({ cls: cls, title: String(w.title || "") })
    }
    runningApps = out
  }

  function demoCatalogue() {
    return [
      { id: "atlas", name: "Atlas", icon: "atlas", wmClass: "atlas", webapp: false,
        url: "", singleInstance: false, command: "atlas", comment: "demo browser" },
      { id: "nebula", name: "Nebula Player", icon: "nebula", wmClass: "nebula", webapp: false,
        url: "", singleInstance: true, command: "nebula", comment: "demo music player" },
      { id: "sage", name: "Sage", icon: "sage", wmClass: "chrome-sage.example__-Default",
        webapp: true, url: "https://sage.example", singleInstance: false,
        command: "omarchy-launch-webapp https://sage.example", comment: "demo AI web app" }
    ]
  }

  function pickInstalled(app) {
    picked({
      name: app.name,
      command: app.command,
      class: app.wmClass,
      webapp: !!app.webapp,
      singleInstance: !!app.singleInstance
    })
  }

  function pickRunning(cls, title) {
    var name = WindowIdentity.appName(DesktopEntries, cls, title)
    picked({
      name: name,
      command: cls,
      class: cls,
      webapp: String(cls).indexOf("chrome-") === 0,
      singleInstance: isSingleInstance(cls)
    })
  }

  function addCustom() {
    var text = query.trim()
    if (text === "") return
    var isUrl = /^https?:\/\//.test(text)
    var app = isUrl
      ? {
          name: hostOf(text),
          command: "omarchy-launch-webapp " + shellQuote(text),
          class: "chrome-" + hostOf(text) + "__-Default",
          webapp: true,
          singleInstance: false   // chromium --app maps a new window per launch
        }
      : {
          name: text.split(" ")[0].split("/").pop().slice(0, 24),
          command: text,
          class: guessClass(text),
          webapp: false,
          singleInstance: isSingleInstance(text)
        }
    picked(app)
    query = ""
  }

  function pickCursor() {
    if (source === 2) { addCustom(); return }
    var list = activeList
    if (cursor < 0 || cursor >= list.length) return
    var row = list[cursor]
    if (source === 0) pickInstalled(row)
    else pickRunning(row.cls, row.title)
  }

  function moveCursor(delta) {
    var list = activeList
    if (list.length === 0) return
    cursor = Math.min(list.length - 1, Math.max(0, cursor + delta))
  }

  function hostOf(url) {
    var host = String(url).split("//")[1] || String(url)
    host = host.split("/")[0]
    return host.indexOf("www.") === 0 ? host.slice(4) : host
  }

  function guessClass(command) {
    var bin = String(command).split(" ")[0].split("/").pop()
    return bin
  }

  function isSingleInstance(text) {
    var known = ["cider", "spotube", "youtube-music", "webcord", "discord",
                 "slack", "1password", "bitwarden", "signal", "telegramdesktop",
                 "whatsapp", "spotify", "steam", "obs", "zoom"]
    var t = String(text).toLowerCase()
    for (var i = 0; i < known.length; i++) if (t.indexOf(known[i]) >= 0) return true
    return false
  }

  function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'"
  }

  function focusSearch() {
    search.forceActiveFocus()
  }

  Process {
    id: appsProc
    command: ["bash", "-c",
      decodeURIComponent(Qt.resolvedUrl("../bin/scratchpad-studio").toString()
        .replace(/^file:\/\//, "")) + " apps 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.catalogue = JSON.parse(text) }
        catch (e) { root.catalogueError = "catalogue unavailable" }
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    // search / custom entry
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      TextField {
        id: search
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(32)
        placeholderText: root.source === 2
          ? qsTr("Command (e.g. foot -e htop) or https://url…")
          : qsTr("Search apps…")
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
        // Ctrl+1/2/3 switch the source without reaching for the tabs.
        Keys.onPressed: function(event) {
          if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_1) { root.source = 0; event.accepted = true }
            else if (event.key === Qt.Key_2) { root.source = 1; event.accepted = true }
            else if (event.key === Qt.Key_3) {
              root.source = 2
              root.query = ""
              event.accepted = true
            }
          }
        }
        Component.onCompleted: forceActiveFocus()
      }

      Button {
        visible: root.source === 2
        text: qsTr("Add")
        iconText: "󰐗"
        fontSize: Style.font.bodySmall
        onClicked: root.addCustom()
      }
    }

    // source tabs
    Row {
      spacing: Style.space(6)

      Repeater {
        model: [qsTr("Installed"), qsTr("Running"), qsTr("Custom")]

        Button {
          required property string modelData
          required property int index
          text: modelData
          fontSize: Style.font.bodySmall
          selected: root.source === index
          onClicked: { root.source = index; search.text = ""; search.forceActiveFocus() }
        }
      }
    }

    // picker list
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      radius: Style.cornerRadius
      color: Qt.alpha(Color.background, 0.45)
      border.width: 1
      border.color: Color.popups.border

      Flickable {
        id: listFlick
        anchors.fill: parent
        anchors.margins: Style.space(4)
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: listColumn
          width: listFlick.width
          spacing: 2

          // ---- installed ----
          Repeater {
            model: root.source === 0 ? root.filteredInstalled : 0

            Item {
              id: installedRow
              required property var modelData
              required property int index
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(36)
              readonly property var app: modelData
              readonly property bool pickedByKeyboard:
                root.source === 0 && root.cursor === index && search.activeFocus
              readonly property bool pickedAlready:
                root.pickedClasses.indexOf(String(app.wmClass)) >= 0

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius - 2
                color: parent.pickedAlready ? Qt.alpha(Color.accent, 0.12)
                  : (rowMouse.containsMouse || parent.pickedByKeyboard
                     ? Qt.alpha(Color.foreground, 0.08) : "transparent")
                border.width: parent.pickedByKeyboard ? 2 : 0
                border.color: Color.accent
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.pickInstalled(app)
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Item {
                  Layout.preferredWidth: Style.space(22)
                  Layout.preferredHeight: Style.space(22)
                  Image {
                    anchors.fill: parent
                    source: app.icon ? Quickshell.iconPath(app.icon, true) : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: !app.icon
                    text: app.name.slice(0, 1)
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    renderType: Text.NativeRendering
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: app.name + (app.comment !== "" ? "  ·  " + app.comment : "")
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: installedRow.pickedAlready ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }

                Text {
                  text: app.webapp ? root.hostOf(app.url)
                    : (app.singleInstance ? qsTr("single-instance") : app.wmClass)
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }

                Text {
                  visible: installedRow.pickedAlready
                  text: "󰄬"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          // ---- running ----
          Repeater {
            model: root.source === 1 ? root.filteredRunning : 0

            Item {
              id: runningRow
              required property var modelData
              required property int index
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(36)
              readonly property var win: modelData
              readonly property bool pickedByKeyboard:
                root.source === 1 && root.cursor === index && search.activeFocus
              readonly property bool pickedAlready:
                root.pickedClasses.indexOf(String(win.cls)) >= 0

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius - 2
                color: parent.pickedAlready ? Qt.alpha(Color.accent, 0.12)
                  : (runMouse.containsMouse || parent.pickedByKeyboard
                     ? Qt.alpha(Color.foreground, 0.08) : "transparent")
                border.width: parent.pickedByKeyboard ? 2 : 0
                border.color: Color.accent
              }

              MouseArea {
                id: runMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.pickRunning(win.cls, win.title)
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Item {
                  Layout.preferredWidth: Style.space(22)
                  Layout.preferredHeight: Style.space(22)
                  Image {
                    anchors.fill: parent
                    source: {
                      var entry = DesktopEntries.heuristicLookup(win.cls)
                      return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
                    }
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                  }
                }

                Text {
                  Layout.fillWidth: true
                  // app name from the desktop entry (class fallback) —
                  // the class string alone reads like developer jargon
                  text: WindowIdentity.appName(DesktopEntries, win.cls, win.title)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: runningRow.pickedAlready ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  renderType: Text.NativeRendering
                }

                Text {
                  Layout.fillWidth: true
                  text: win.title !== "" ? win.title : win.cls
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: root.compact
                    ? Math.max(8, Style.font.caption * 0.85) : Style.font.caption
                  renderType: Text.NativeRendering
                }
              }
            }
          }

          // ---- custom hint ----
          Text {
            visible: root.source === 2
            Layout.fillWidth: true
            Layout.margins: Style.space(8)
            wrapMode: Text.Wrap
            text: qsTr("Enter a command or a URL. URLs open as web apps (chromium --app), and the window class is derived from the host. For single-instance apps the class match is used instead of process tracking, so launchers that exit immediately still work.")
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            lineHeight: 1.3
            renderType: Text.NativeRendering
          }

          Text {
            visible: (root.source === 0 && root.filteredInstalled.length === 0 && root.catalogue.length > 0)
              || (root.source === 1 && root.filteredRunning.length === 0)
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(16)
            text: root.query.trim() !== "" ? qsTr("No matches") : qsTr("Nothing to show")
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
