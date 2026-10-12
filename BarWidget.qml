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
      if (event.name === "activespecial") {
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
        return
      }
      // Window-rule geometry is baked in pixels; a monitor change must
      // regenerate the rules for the new usable area.
      if (event.name === "monitoradded" || event.name === "monitorremoved") {
        reapplyTimer.restart()
      }
    }
  }

  Timer {
    id: reapplyTimer
    interval: 1500
    onTriggered: root.helper(["apply"])
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

  // After a capture into the scratchpad being edited, re-arm the editor's
  // draft from the refreshed state so the captured app shows up (the
  // helper added it to the state file; the FileView reloads stateJson).
  property bool editorCaptureRefresh: false
  onStateChanged: {
    if (!editorCaptureRefresh || detail !== "editor" || !editorScratchpad) return
    var fresh = findStateScratchpad(editorScratchpad.id)
    if (fresh) {
      editorScratchpad = null
      editorScratchpad = fresh
    }
    editorCaptureRefresh = false
  }

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

  // Deleting never kills windows — the helper moves them out first — but
  // it removes the keybind and rules, so it deserves an explicit confirm.
  // `deleteOpen` drives BOTH surfaces' dialogs: whichever is visible shows
  // its own centered confirm, and confirming in either closes both (the
  // v0.1 dialog hung directly off this Panel with no size — it rendered
  // its buttons clamped to the top-left corner and, because `opened` was
  // never reset, stayed stuck there after the delete).
  function deleteScratchpad(card) {
    deleteTarget = card
    deleteOpen = true
  }

  function confirmDelete() {
    if (root.deleteTarget && !root.demoMode) root.helper(["delete", root.deleteTarget.id])
    deleteTarget = null
    deleteOpen = false
  }

  function cancelDelete() {
    deleteTarget = null
    deleteOpen = false
  }

  // Window capture: the card's capture button opens the live-window
  // picker; picking a row runs `capture <id> --address <addr>` which
  // moves that exact window into the scratchpad and adds its class.
  function requestCapture(card) {
    captureTargetId = card.id
    captureTargetName = card.name
    captureOpen = true
  }

  function cancelCaptureWindow() {
    captureTargetId = ""
    captureOpen = false
  }

  property string captureTargetId: ""
  property string captureTargetName: ""
  property bool captureOpen: false

  // A modal confirm must not outlive its panel: closing the panel (click
  // away, Esc from the bar, panel switch) cancels any pending delete so
  // it cannot reappear the next time the panel opens. Same for the
  // capture picker.
  onOpenedChanged: {
    if (!opened) {
      cancelDelete()
      cancelCaptureWindow()
    }
  }

  property var deleteTarget: null
  property bool deleteOpen: false

  function newScratchpad() {
    wizardScratchpad = null
    wizardDuplicate = false
    detail = "wizard"
  }

  function editScratchpad(card) {
    var sp = findStateScratchpad(card.id)
    if (!sp) return
    // Null-first so re-entering the editor for the same scratchpad
    // re-arms selection/tested state (same object identity would not).
    editorScratchpad = null
    editorScratchpad = sp
    detail = "editor"
  }

  function findStateScratchpad(id) {
    var sps = (root.state && root.state.scratchpads) || []
    for (var i = 0; i < sps.length; i++) {
      if (sps[i].id === id) return sps[i]
    }
    return null
  }

  // Every taken scratchpad id plus the reserved built-in "scratchpad"
  // (Omarchy's special:scratchpad, SUPER+S) — the wizard's first step
  // assigns the new scratchpad a free id from this list so two
  // scratchpads never share one special workspace.
  readonly property var stateIds: {
    var sps = (state && state.scratchpads) || []
    var ids = ["scratchpad"]
    for (var i = 0; i < sps.length; i++) ids.push(sps[i].id)
    return ids
  }

  function duplicateScratchpad(card) {
    var sp = findStateScratchpad(card.id)
    if (!sp) return
    var copy = JSON.parse(JSON.stringify(sp))
    copy.id = copy.id + "-copy"
    copy.name = copy.name + " copy"
    copy.keybind = ""
    wizardScratchpad = copy
    wizardDuplicate = true
    detail = "wizard"
  }

  function closeDetail() {
    detail = ""
    wizardScratchpad = null
    editorScratchpad = null
    wizardDuplicate = false
  }

  // Which full-screen flow owns the panel/window content:
  // "" overview, "wizard" create/duplicate, "editor" edit.
  property string detail: ""
  property var wizardScratchpad: null
  property bool wizardDuplicate: false
  property var editorScratchpad: null
  readonly property var monitorInfo: {
    var m = Hyprland.focusedMonitor
    return m ? { width: m.width || 0, height: m.height || 0, scale: m.scale || 1, name: m.name || "" } : null
  }

  function openWindow() {
    studioWindow.visible = true
    // FloatingWindow exposes no raise() in this Quickshell build (calling
    // it logged a TypeError on every open) — showing is what matters.
    if (typeof studioWindow.raise === "function") studioWindow.raise()
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
      headerRow.height + (detail === "editor" ? Style.space(640) : detail !== "" ? Style.space(600) : overview.contentHeightNeeded())
      + Style.space(10), Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The wizard/editor own the keyboard while open: their TextFields
      // eat typing and chord capture needs raw keys (arrows included).
      // The delete dialog owns it while open — arrows move its selection,
      // Enter confirms, Esc cancels (instead of closing the panel). The
      // capture picker's search field takes it while that is open.
      blocked: root.detail !== "" || root.captureOpen

      onMoveRequested: function(dx, dy) {
        if (root.deleteOpen && dx !== 0)
          panelDeleteDialog.selectedIndex = panelDeleteDialog.selectedIndex === 0 ? 1 : 0
        else overview.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.deleteOpen) root.confirmDelete()
        else overview.activate()
      }
      onCloseRequested: {
        if (root.deleteOpen) root.cancelDelete()
        else if (root.captureOpen) root.cancelCaptureWindow()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.deleteOpen)
          panelDeleteDialog.selectedIndex = panelDeleteDialog.selectedIndex === 0 ? 1 : 0
        else root.switchPanel(direction)
      }
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
                text: root.detail !== "" ? qsTr("Back to overview") : qsTr("New")
                iconText: root.detail !== "" ? "󰁙" : "󰐗"
                fontSize: Style.font.bodySmall
                onClicked: root.detail !== "" ? root.closeDetail() : root.newScratchpad()
              }
            }
          }

          // ---------- content: overview, wizard (create), or editor ----------
          Item {
            width: panelFlick.width
            height: Math.max(overview.visible ? overview.contentHeightNeeded() : 0,
                             wizard.visible ? Style.space(600) : 0,
                             editor.visible ? Style.space(640) : 0)

            Overview {
              id: overview
              visible: root.detail === ""
              anchors.fill: parent
              cards: root.cards
              demo: root.demoMode
              compact: true

              function contentHeightNeeded() {
                return Math.max(Style.space(160),
                                rows * (cardH + gridGap) + gridGap)
              }

              onToggleRequested: function(card) { root.toggleScratchpad(card) }
              onEditRequested: function(card) { root.editScratchpad(card) }
              onDeleteRequested: function(card) { root.deleteScratchpad(card) }
              onDuplicateRequested: function(card) { root.duplicateScratchpad(card) }
              onAdoptRequested: function(card) { root.helper(["adopt", card.id]) }
              onCaptureRequested: function(card) { root.requestCapture(card) }
              onNewRequested: root.newScratchpad()
            }

            Wizard {
              id: wizard
              visible: root.detail === "wizard"
              anchors.fill: parent
              editScratchpad: root.wizardScratchpad
              duplicate: root.wizardDuplicate
              demo: root.demoMode
              monitor: root.monitorInfo
              existingIds: root.stateIds

              onFinished: function(sp) { root.closeDetail() }
              onCanceled: root.closeDetail()
            }

            Editor {
              id: editor
              visible: root.detail === "editor"
              anchors.fill: parent
              editScratchpad: root.editorScratchpad
              demo: root.demoMode
              monitor: root.monitorInfo

              onSaved: function(sp) { root.closeDetail() }
              onCanceled: root.closeDetail()
              onCaptureRequested: {
                if (root.editorScratchpad) root.requestCapture(root.editorScratchpad)
              }
            }
          }
        }
      }

      // Delete confirm, hosted where it belongs: filling the panel card
      // so the scrim covers the content and the dialog centers over it
      // (the v0.1 copy hung off the sizeless Panel root and clamped to
      // the top-left corner, stuck there because `opened` never reset).
      // Declared after the Flickable so it paints above the content.
      ConfirmDialog {
        id: panelDeleteDialog
        anchors.fill: parent
        opened: root.deleteOpen
        message: root.deleteTarget
          ? qsTr("Delete “%1”? Its windows move to the current workspace and stay open.").arg(root.deleteTarget.name)
          : ""
        confirmText: qsTr("Delete")
        onConfirmed: root.confirmDelete()
        onCanceled: root.cancelDelete()
      }

      // Live-window capture picker, hosted over the panel content like the
      // delete confirm. Picking a row runs the capture command for that
      // exact window address; the state refresh moves the card's app list
      // and the reflow lands the window on its slot.
      Rectangle {
        anchors.fill: parent
        visible: root.captureOpen
        radius: Style.cornerRadius
        color: Qt.alpha(Color.background, 0.92)
        border.width: 1
        border.color: Color.popups.border

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              text: qsTr("Capture a window into “%1”").arg(root.captureTargetName)
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              renderType: Text.NativeRendering
            }
            Button {
              text: qsTr("Done")
              iconText: "󰄬"
              fontSize: Style.font.bodySmall
              onClicked: root.cancelCaptureWindow()
            }
          }

          WindowPickerList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            compact: true
            onPicked: function(win) {
              root.helper(["capture", root.captureTargetId, "--address", win.address])
              // Editing that scratchpad? Reload its draft once the helper
              // has written the captured app into the state file.
              if (root.detail === "editor" && root.editorScratchpad
                  && root.captureTargetId === root.editorScratchpad.id)
                root.editorCaptureRefresh = true
              root.cancelCaptureWindow()
            }
            onEscapeRequested: root.cancelCaptureWindow()
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

  // Deleting never kills windows — the helper moves them out first — but
  // it removes the keybind and rules, so it deserves an explicit confirm.
  // The app window hosts its own copy (inside its content, centered over
  // it); the panel hosts one inside its key catcher. Both are driven by
  // `deleteOpen`, so confirming in either surface closes both.

  // ---------------- IPC ----------------

  IpcHandler {
    target: "scratchpad-studio"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function window(): string { root.openWindow(); return "ok" }
    // Graceful hide (the Esc path): lets Quickshell unmap and reuse the
    // window. Killing the surface from the compositor side leaves the
    // FloatingWindow unable to remap until the widget is recreated.
    function hideWindow(): void { studioWindow.visible = false }
    function startWizard(): void { root.open(); Qt.callLater(root.newScratchpad) }
    function wizardStep(n: int): void { wizard.step = n; wizard.forceActiveFocus() }
    // Open the visual editor for one scratchpad (works in demo mode too).
    function edit(id: string): string {
      var sp = root.findStateScratchpad(id)
      if (!sp) return "no such scratchpad: " + id
      root.editorScratchpad = null
      root.editorScratchpad = sp
      root.detail = "editor"
      root.open()
      return "editing " + id
    }
    function demo(mode: string): void {
      root.demoMode = String(mode) === "on" || String(mode) === "true"
    }
    function status(): string {
      return "v" + "0.2.0" + " demo=" + root.demoMode + " scratchpads=" + root.cards.length
        + " detail=" + root.detail
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
      var editorInfo = null
      // The app window and the panel each hold a draft; report whichever
      // surface holds data (window first — it is the one IPC flows drive).
      var draft = studioWindow.editorDraft || (editor.visible ? editor.draft : null)
      if (root.detail === "editor" && draft) {
        editorInfo = {
          id: draft.id,
          name: draft.name,
          placement: draft.placement,
          layout: draft.layout,
          anchor: draft.anchor,
          keybind: draft.keybind,
          apps: draft.apps.map(function (a) { return a.name })
        }
      }
      return JSON.stringify({
        cursor: overview.cursor,
        columns: overview.columns,
        rows: overview.rows,
        detail: root.detail,
        editor: editorInfo,
        names: root.cards.map(function (c) { return c.id + ":" + c.status }),
        focusedWorkspace: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.name || "") : "",
        specials: specials
      })
    }
  }
}
