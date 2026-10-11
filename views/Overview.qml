import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import ".."

// Overview — the studio's home: a grid of scratchpad cards plus foreign
// specials, an empty state when there is nothing yet, and keyboard-first
// navigation (arrows move the cursor, Enter toggles, Esc closes).
Item {
  id: root

  required property var cards            // LiveModel.buildCards(...) output
  property bool demo: false
  property bool compact: false           // panel (true) vs app window (false)

  signal toggleRequested(var card)
  signal editRequested(var card)
  signal duplicateRequested(var card)
  signal deleteRequested(var card)
  signal adoptRequested(var card)
  signal newRequested()
  signal closeRequested()

  property int cursor: 0
  readonly property var cardList: cards || []
  readonly property real cardW: Style.space(288)
  readonly property real cardH: Style.space(212)
  readonly property real gridGap: Style.space(12)
  readonly property int columns: Math.max(1, Math.floor((width + gridGap) / (cardW + gridGap)))
  readonly property int rows: Math.max(1, Math.ceil(cardList.length / columns))

  onCardsChanged: {
    if (cursor >= cardList.length) cursor = Math.max(0, cardList.length - 1)
  }

  function moveCursor(dx, dy) {
    if (cardList.length === 0) return
    var col = cursor % columns
    var row = Math.floor(cursor / columns)
    if (dx !== 0) col = Math.min(columns - 1, Math.max(0, col + dx))
    if (dy !== 0) row = Math.min(rows - 1, Math.max(0, row + dy))
    var next = row * columns + col
    cursor = Math.min(cardList.length - 1, next)
    ensureVisible(cursor)
  }

  function ensureVisible(index) {
    // Grid lays out fixed-size cards regularly; compute the row offset
    // instead of fishing for delegate items.
    var y = Math.floor(index / columns) * (cardH + gridGap)
    if (y < flick.contentY) flick.contentY = y
    else if (y + cardH > flick.contentY + flick.height)
      flick.contentY = y + cardH - flick.height
  }

  function activate() {
    if (cardList.length === 0) { newRequested(); return }
    var card = cardList[cursor]
    if (card) toggleRequested(card)
  }

  // ---------- empty state ----------
  EmptyState {
    anchors.fill: parent
    visible: root.cardList.length === 0
    onNewRequested: root.newRequested()
  }

  // ---------- grid ----------
  Flickable {
    id: flick
    anchors.fill: parent
    visible: root.cardList.length > 0
    contentWidth: width
    contentHeight: grid.height + Style.space(4)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Grid {
      id: grid
      x: 0
      y: 0
      width: flick.width
      columns: root.columns
      spacing: root.gridGap

      Repeater {
        model: root.cardList.length

        ScratchpadCard {
          required property int index

          card: root.cardList[index]
          demo: root.demo
          hasCursor: root.cursor === index && root.cardList.length > 0

          onToggleRequested: root.toggleRequested(card)
          onEditRequested: root.editRequested(card)
          onDuplicateRequested: root.duplicateRequested(card)
          onDeleteRequested: root.deleteRequested(card)
          onAdoptRequested: root.adoptRequested(card)
        }
      }
    }
  }
}
