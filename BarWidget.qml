import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "views"
import "lib/StudioState.js" as StudioState
import "lib/LiveModel.js" as LiveModel

// Scratchpad Studio — bar widget + panel + app window.
//
// One entry point hosts everything inside the omarchy-shell process, like
// Omarchy's own panel plugins: the bar icon (BarIconButton), the studio
// panel (KeyboardPanel, keyboard-first), and a resizable app window for
// when the panel feels cramped. All engine work goes through the helper
// CLI (`bin/scratchpad-studio`); QML never touches user config itself.
Panel {
  id: root

  moduleName: "scratchpad-studio"
  ipcTarget: "scratchpad-studio"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.config/scratchpad-studio"
  readonly property string statePath: stateDir + "/scratchpads.json"
  readonly property string helperPath:
    decodeURIComponent(Qt.resolvedUrl("bin/scratchpad-studio").toString().replace(/^file:\/\//, ""))

  // Demo mode comes from the shell.json widget settings (schema in the
  // manifest) and can be flipped at runtime over IPC for screenshots.
  property bool demoMode: setting("demoMode", "Off") === "On" || setting("demoMode", false) === true
  property string stateJson: ""
  readonly property var state: {
    if (demoMode) return StudioState.demoState()
    if (stateJson === "") return StudioState.defaultState()
    try { return StudioState.normalizeState(JSON.parse(stateJson)) }
    catch (e) { return StudioState.defaultState() }
  }

  // Live card model. Reading Hyprland.toplevels.values and
  // Hyprland.workspaces.values re-evaluates this whenever a window maps,
  // moves, closes or a workspace toggles — no polling.
  readonly property var cards: {
    var state = root.state
    var shown = root.shownSpecials
    if (demoMode) return LiveModel.demoCards(state, StudioState.demoWindows)
    return LiveModel.buildCards(state, Hyprland.toplevels.values,
                                Hyprland.workspaces.values, shown)
  }

  // Which specials are revealed, by id. Quickshell's workspace model keeps
  // `active` false for special workspaces on this Hyprland (verified), so
  // the activespecial event is the live source; `shown` CLI seeds startup.
  property var shownSpecials: ({})

  Component.onCompleted: shownProc.running = true

  Process {
    id: shownProc
    command: ["bash", "-c", JSON.stringify(root.helperPath) + " shown 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var ids = JSON.parse(text)
          var next = {}
          for (var i = 0; i < ids.length; i++) next[ids[i]] = true
          root.shownSpecials = next
        } catch (e) { }
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "activespecial") return
      // activespecial>>special:name,MONITOR (empty name = hidden)
      var parts = String(event.data || "").split(",")
      var name = parts[0] || ""
      var id = name.replace(/^special:/, "")
      var next = {}
      for (var k in root.shownSpecials) next[k] = root.shownSpecials[k]
      if (id !== "") next[id] = true
      else {
        // A monitor dropped its special; only that monitor's id clears — but
        // the event does not say which one had it. Cross-check via the CLI.
        shownProc.running = true
      }
      root.shownSpecials = next
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------- state file ----------------

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.stateJson = text()
    onLoadFailed: root.stateJson = ""
  }

  // ---------------- engine bridge (helper CLI) ----------------

  function helper(args) {
    if (demoMode) return
    Quickshell.execDetached(["bash", "-c",
      JSON.stringify(root.helperPath) + " " + args.map(JSON.stringify).join(" ") + " 2>&1"])
    // Fire-and-forget for toggles: the CLI is fast and the live card model
    // updates from Hyprland events, not from CLI output.
  }

  function toggleScratchpad(card) {
    helper(["toggle", card.id])
  }

  function deleteScratchpad(card) {
    deleteTarget = card
    deleteDialog.opened = true
  }

  property var deleteTarget: null

  function newScratchpad() {
    console.warn("scratchpad-studio: wizard lands in milestone c")
  }

  function openWindow() {
    studioWindow.visible = true
    studioWindow.raise()
  }

  // ---------------- bar icon ----------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃽"
    tooltipText: qsTr("Scratchpad Studio")
    onPressed: function(code) {
      if (code === Qt.RightButton) root.openWindow()
      else root.toggle()
    }
  }

  // ---------------- studio panel ----------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(936))
    contentHeight: panel.fittedContentHeight(
      headerRow.height + overview.height + Style.space(10), Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) { overview.moveCursor(dx, dy) }
      onActivateRequested: overview.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n" || t === "N") root.newScratchpad()
        else if (t === "w" || t === "W") root.openWindow()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // ---------- header ----------
          Item {
            id: headerRow
            width: parent.width
            height: Style.space(30)

            Text {
              id: headerTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: qsTr("Scratchpads")
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              renderType: Text.NativeRendering
            }

            Text {
              anchors.left: headerTitle.right
              anchors.leftMargin: Style.space(8)
              anchors.baseline: headerTitle.baseline
              visible: root.demoMode
              text: qsTr("demo — fake data")
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰹑"
                tooltipText: qsTr("Open as a resizable window")
                size: Style.space(26)
                onClicked: { root.openWindow(); root.close() }
              }

              Button {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("New")
                iconText: "󰐗"
                fontSize: Style.font.bodySmall
                onClicked: root.newScratchpad()
              }
            }
          }

          // ---------- grid ----------
          Overview {
            id: overview
            width: parent.width
            height: Math.max(Style.space(160),
                             overview.rows * (overview.cardH + overview.gridGap) + overview.gridGap)
            cards: root.cards
            demo: root.demoMode
            compact: true

            onToggleRequested: function(card) { root.toggleScratchpad(card) }
            onEditRequested: function(card) { console.warn("scratchpad-studio: wizard lands in milestone c:", card.id) }
            onDeleteRequested: function(card) { root.deleteScratchpad(card) }
            onDuplicateRequested: function(card) { console.warn("scratchpad-studio: duplicate lands in milestone c:", card.id) }
            onAdoptRequested: function(card) { root.helper(["adopt", card.id]) }
            onNewRequested: root.newScratchpad()
          }
        }
      }
    }
  }

  // ---------------- app window ----------------

  StudioWindow {
    id: studioWindow
    hostWidget: root
    cards: root.cards
    demo: root.demoMode
  }

  // Deleting never kills windows — the helper moves them out first — but it
  // removes the keybind and rules, so it deserves an explicit confirm.
  ConfirmDialog {
    id: deleteDialog
    message: root.deleteTarget
      ? qsTr("Delete “%1”? Its windows move to the current workspace and stay open.").arg(root.deleteTarget.name)
      : ""
    confirmText: qsTr("Delete")
    onConfirmed: {
      if (root.deleteTarget) root.helper(["delete", root.deleteTarget.id])
      root.deleteTarget = null
    }
    onCanceled: root.deleteTarget = null
  }

  // ---------------- IPC ----------------

  IpcHandler {
    target: "scratchpad-studio"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function window(): string { root.openWindow(); return "ok" }
    function demo(mode: string): void {
      root.demoMode = String(mode) === "on" || String(mode) === "true"
    }
    function status(): string {
      return "demo=" + root.demoMode + " scratchpads=" + root.cards.length
        + " helper=" + (root.helperPath.length > 0 ? "ok" : "?")
    }
    function inspect(): string {
      var specials = []
      var items = Hyprland.workspaces.values
      for (var i = 0; i < items.length; i++) {
        var name = String(items[i].name || "")
        if (name.indexOf("special:") === 0)
          specials.push({ name: name, active: items[i].active === true, id: items[i].id })
      }
      return JSON.stringify({
        cursor: overview.cursor,
        columns: overview.columns,
        rows: overview.rows,
        names: root.cards.map(function (c) { return c.id + ":" + c.status }),
        focusedWorkspace: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.name || "") : "",
        specials: specials
      })
    }
  }
}
