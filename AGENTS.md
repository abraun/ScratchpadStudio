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
  under the Lua config — use `hyprctl eval 'return hl.dsp.…'`. Window-rule
  `size`/`move` take pixels only (percentages silently ignored), so
  geometry is baked from `hyprctl -j monitors` at generation time.

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
   and `omarchy-restart-shell` (or reload via `qs` ipc) to pick up QML.
2. Screenshots: `grim /tmp/shot.png` after opening the panel with
   `omarchy-shell shell toggle scratchpad-studio`. Keep proof artifacts
   OUTSIDE the worktree. README screenshots must use demo mode
   (`qs -p /usr/share/omarchy/shell ipc call scratchpad-studio demo on`).
3. QML logs: `journalctl --user -u omarchy-shell -n 50` or the shell's
   stdout depending on how it was started.

## Style

- Theme strictly through `qs.Commons` (`Color.*`, `Style.space()`,
  `Style.font.*`) so the plugin re-themes with Omarchy. No hex colors in
  views.
- Transitions 150–250 ms, `Easing.OutCubic` family. Focus rings and
  keyboard paths are features, not garnish.
- Comments explain *why*, especially where Hyprland/Omarchy behavior was
  verified empirically.
