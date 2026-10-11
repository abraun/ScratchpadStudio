# Scratchpad Studio — agent notes

Omarchy bar plugin (Quickshell/QML + a Python helper CLI) for managing
multiple named scratchpads on Hyprland 0.5x with the Lua config.
`docs/design.md` is the source of truth for the engine decision, data
model, and file layout; read it before changing architecture.

## Hard constraints

- **Never break the user's config.** Touch only: plugin-owned files
  (`~/.config/hypr/scratchpad-studio.lua`, state under
  `~/.config/scratchpad-studio/`) and the single managed block in
  `~/.config/hypr/bindings.lua` (see `managed block` in the helper).
  Back up before writes, stay idempotent, validate with
  `hyprctl configerrors` after `hyprctl reload`, restore on failure.
- **Never close or kill the user's windows.** Delete moves scratchpad
  windows to the current workspace; it does not terminate anything.
- **No network, no telemetry.** The plugin makes zero network calls.
- Engine facts verified on this machine: `hyprctl dispatch <string>` fails
  under the Lua config — use `hyprctl dispatch 'hl.dsp.…'` (with keybind
  context) for workspace/window dispatchers; `hyprctl eval` runs Lua with
  NO keybind context, where `toggle_special` and `window.move` silently
  no-op. Window-rule `size`/`move` take pixels only (percentages silently
  ignored), so geometry is baked from `hyprctl -j monitors` at generation
  time; `hyprctl -j workspaces` omits `active` for special workspaces —
  shown-state comes from the focused monitor's `specialWorkspace` field.

## Layout / commands

- `BarWidget.qml` — bar icon + panel + app window + IPC (one process with
  omarchy-shell; imports `qs.Commons` / `qs.Ui` from the Omarchy shell).
- `views/` QML surfaces, `lib/` `.pragma library` JS (pure functions).
- `bin/scratchpad-studio` — Python 3 CLI, stdlib only: `toggle`, `list`,
  `geometry`, `apply`, `install`, `uninstall`, `conflicts`…
- `tests/` — `python3 -m unittest discover -s tests` must stay green.
- Geometry math exists twice on purpose (python generates config, JS draws
  previews): `layout_rects` in the CLI and `Layout.rects` in
  `lib/Layout.js` must stay behaviorally identical; tests pin the python
  side, visual checks pin the JS side.

## Dev loop on the live machine

1. Copy the worktree into `~/.config/omarchy/plugins/scratchpad-studio`
   (rsync, exclude `.git`), then `omarchy plugin enable scratchpad-studio`
   and `omarchy-restart-shell` to pick up QML.
2. **QML edits need a full shell restart** — plugin hot-reload recreates the
   widget but does not recompile changed QML types or re-register IPC
   functions (verified live: new IpcHandler functions only appear after
   `omarchy-restart-shell`; a session lock makes restart refuse — wait for
   the user to return rather than forcing anything).
3. Screenshots: open the app window (`ipc call scratchpad-studio window`),
   read its exact geometry from `hyprctl -j clients` (title "Scratchpad
   Studio"), and `grim -g` that rect — no desktop bleed, no real titles in
   frame. Panel shots crop imprecisely; prefer the window for README art.
   README screenshots must use demo mode
   (`qs -p /usr/share/omarchy/shell ipc call scratchpad-studio demo on`).
4. Synthetic keyboard input does NOT reach layer-shell panels
   (wtype/hl.dsp.send_key_state both fail) — keyboard flows are verified
   structurally (focus wiring + no QML errors) and by hand.
5. QML logs: `journalctl --user -n 50 | grep scratchpad-studio`.

## Style

- Theme strictly through `qs.Commons` (`Color.*`, `Style.space()`,
  `Style.font.*`) so the plugin re-themes with Omarchy. No hex colors in
  views.
- Transitions 150–250 ms, `Easing.OutCubic` family. Focus rings and
  keyboard paths are features, not garnish.
- Comments explain *why*, especially where Hyprland/Omarchy behavior was
  verified empirically.
