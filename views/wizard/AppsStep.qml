import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// AppsStep — pick what lives in the scratchpad.
//
// Three sources, one search box: installed apps (.desktop via the helper's
// `apps` catalogue, which resolves StartupWMClass and webapp classes),
// currently running windows (exact class straight from the compositor), and
// a custom command or URL.
Item {
  id: root

  property var draft: null
  property bool demo: false
  signal touched()

  property string query: ""
  property int source: 0          // 0 installed, 1 running, 2 custom
  property var catalogue: []
  property var catalogueError: ""
  property var runningApps: []

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

  function addInstalled(app) {
    if (!draft) return
    for (var i = 0; i < draft.apps.length; i++) {
      if (draft.apps[i].class === app.wmClass) return
    }
    draft.apps.push({
      name: app.name,
      command: app.command,
      class: app.wmClass,
      webapp: !!app.webapp,
      singleInstance: !!app.singleInstance
    })
    touched()
  }

  function addRunning(cls, title) {
    if (!draft) return
    for (var i = 0; i < draft.apps.length; i++) {
      if (draft.apps[i].class === cls) return
    }
    var name = title.split(" ")[0].slice(0, 24) || cls
    draft.apps.push({
      name: name,
      command: cls,
      class: cls,
      webapp: String(cls).indexOf("chrome-") === 0,
      singleInstance: isSingleInstance(cls)
    })
    touched()
  }

  function addCustom() {
    if (!draft) return
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
    for (var i = 0; i < draft.apps.length; i++) {
      if (draft.apps[i].command === app.command) return
    }
    draft.apps.push(app)
    query = ""
    touched()
  }

  function removeApp(index) {
    if (!draft) return
    draft.apps.splice(index, 1)
    touched()
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

  Process {
    id: appsProc
    command: ["bash", "-c",
      decodeURIComponent(Qt.resolvedUrl("../../bin/scratchpad-studio").toString()
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
        placeholderText: source === 2
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
        onTextChanged: root.query = text
        onAccepted: if (root.source === 2) root.addCustom()
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
          onClicked: { root.source = index; search.text = "" }
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
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(36)
              readonly property var app: modelData
              readonly property bool picked: root.draft
                && root.draft.apps.some(function (a) { return a.class === app.wmClass })

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius - 2
                color: picked ? Qt.alpha(Color.accent, 0.12)
                  : (pickerMouse.containsMouse ? Qt.alpha(Color.foreground, 0.06) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              MouseArea {
                id: pickerMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.addInstalled(app)
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
                    visible: parent.children.length === 1 && !app.icon
                    text: app.name.slice(0, 1)
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: app.name + (app.comment !== "" ? "  ·  " + app.comment : "")
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: picked ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }

                Text {
                  text: app.webapp ? hostOf(app.url)
                    : (app.singleInstance ? qsTr("single-instance") : app.wmClass)
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }

                Text {
                  visible: picked
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
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(36)
              readonly property var win: modelData
              readonly property bool picked: root.draft
                && root.draft.apps.some(function (a) { return a.class === win.cls })

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius - 2
                color: picked ? Qt.alpha(Color.accent, 0.12)
                  : (runMouse.containsMouse ? Qt.alpha(Color.foreground, 0.06) : "transparent")
              }

              MouseArea {
                id: runMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.addRunning(win.cls, win.title)
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
                  text: win.cls
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: picked ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                }

                Text {
                  text: qsTr("window class")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
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
