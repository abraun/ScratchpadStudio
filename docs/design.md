# Scratchpad Studio — Design

A bar plugin for Omarchy 4.0.4 (Hyprland 0.56.2, Lua config): see, create,
edit, delete, and toggle multiple named scratchpads — each a hideable set of
windows on a named `special:*` workspace, bound to a chord.

## Engine decision: native special-workspace engine (no pyprland)

**Decision: implement natively with named special workspaces, generated
window rules, and a launch-or-toggle helper. Do not use pyprland.**

Why (verified on the live machine, 2026-10-11):

1. **pyprland is not packaged.** Not in the official Arch repos
   (`pacman -Si pyprland` → nothing), not installed. Shipping it would mean
   an AUR dependency plus a resident daemon — a heavy footprint for a bar
   plugin, and the captain's environment runs Omarchy-managed packages.
2. **pyprland's dispatch surface fails under the Lua config.** pyprland
   drives Hyprland through string dispatches (`hyprctl dispatch
   togglespecialworkspace name` …). On 0.56.2 with the Lua config these
   fail:
   `hyprctl dispatch togglespecialworkspace` →
   `error: hl.dispatch: expected a dispatcher (e.g. hl.dsp.window.close())`.
   pyprland would need patching upstream; a fork is a maintenance trap.
3. **Everything pyprland does here is available natively.** Verified live:
   - `hyprctl eval 'return hl.dsp.workspace.toggle_special("name")'` — ok.
   - Window rules move+place windows in hidden special workspaces silently
     (`workspace = "special:x silent"`, `float`, `size`, `move`,
     `animation`) — tested with a disposable `foot` window; mapping into a
     hidden special workspace steals no focus.
   - `o.bind` / `o.window` generate persistent config through Omarchy's own
     helpers (`/usr/share/omarchy/default/hypr/helpers.lua`).
   - Omarchy already sets `hide_special_on_workspace_change = true`, so
     scratchpads auto-hide on workspace switch, like pyprland's behavior.

Trade-off accepted: window-rule `size`/`move` take **pixels only**
(percentages are ignored — verified), so the generator bakes pixel geometry
from the current monitor (`hyprctl -j monitors`). The plugin watches monitor
changes and regenerates automatically. Documented in the README.

### How the native engine works

- **State** (source of truth, plugin-owned):
  `~/.config/scratchpad-studio/scratchpads.json`.
- **Generated config** (plugin-owned file, fully rewritten on each apply):
  `~/.config/hypr/scratchpad-studio.lua` — emits, for every scratchpad:
  - one `o.bind(chord, "Scratchpad Studio: <name>",
    "<plugin>/bin/scratchpad-studio toggle <id>")` line,
  - per app: `o.window({ class = "^<class>$", workspace = "special:<id> silent" },
    { float = true, size = "<w> <h>", move = "<x> <y>", animation = "slide" })`
    with pixel geometry computed from the layout, anchor, size and margin.
- **Managed include block** in `~/.config/hypr/bindings.lua`:
  `-- >>> scratchpad-studio >>>` … `require("hypr.scratchpad-studio")` …
  `-- <<< scratchpad-studio <<<`. Idempotent; backed up before every write;
  removed on uninstall. Nothing else in user config is ever touched.
- **Apply flow**: write state JSON → regenerate `scratchpad-studio.lua` →
  `hyprctl reload` → check `hyprctl configerrors` (non-empty ⇒ restore
  backup, report). Live `hyprctl eval` rules are never used for persistence.
- **Toggle flow** (`bin/scratchpad-studio toggle <id>`):
  if the special workspace is currently visible → hide it; else launch any
  configured apps whose window class is absent from `hyprctl -j clients`
  (rules route them into the hidden special workspace), then reveal. No PID
  tracking at all — presence is class-based, which is exactly the fix for
  single-instance apps (Cider) and web apps (`chrome-<host>__-Default`
  classes from `--app=URL`).
- **Never kills windows**: delete removes rules + state; windows that were
  living on the special workspace are moved to the current workspace
  first (unless empty).

## Data model

`~/.config/scratchpad-studio/scratchpads.json`:

```jsonc
{
  "version": 1,
  "scratchpads": [
    {
      "id": "music",                    // slug, stable; = special workspace name
      "name": "Music",
      "icon": "audio-x-generic",        // icon-theme name or 1-2 char glyph
      "keybind": "SUPER + M",           // "" = unbound
      "anchor": "top",                  // top|bottom|left|right
      "sizePct": { "w": 60, "h": 50 },  // of usable monitor area
      "marginPx": 12,
      "layout": "single",               // single|pair|stacked|three-up|grid
      "transition": "down",             // slide-in direction: down|up|right|left
      "apps": [
        {
          "name": "Cider",
          "command": "cider",           // shell command; --app=URL for web apps
          "class": "Cider",             // window class match (match_by=class)
          "webapp": false,
          "singleInstance": true        // process_tracking=false equivalent
        }
      ]
    }
  ]
}
```

Foreign `special:*` workspaces found live (e.g. a pre-existing
`special:music`) are listed in the grid and can be **adopted** into state
(toggle/edit work from then on) without disturbing their windows.
Omarchy's built-in `special:scratchpad` is shown, clearly labeled, and can
be toggled but is never rewritten by us.

## File layout

```
manifest.json            kinds: bar-widget; entryPoints.barWidget: BarWidget.qml
BarWidget.qml            bar icon + PopupCard panel host + FloatingWindow host + IPC
StudioWindow.qml         resizable app-window surface (same views)
views/                   Overview.qml, Wizard.qml, ScratchpadCard.qml, AppPicker.qml,
                         LayoutPicker.qml, TransitionPicker.qml, KeybindCapture.qml,
                         ConfirmDelete.qml, EmptyState.qml
lib/                     State.js  (load/watch/apply JSON, call helper)
                         Live.js   (hyprctl clients/workspaces/monitors/bind polling)
                         Layout.js (pure geometry math, shared with tests)
                         Demo.js   (fake data for screenshots/demos)
bin/scratchpad-studio    Python 3 CLI: toggle|apply|regenerate|install|uninstall|
                         conflicts|import|adopt|list  (stdlib only)
tests/                   test_geometry.py, test_generate.py, test_conflicts.py,
                         test_managed_block.py  (unittest, no network)
docs/design.md           this file
screenshots/             README shots, demo mode only
```

Installed footprint (all created by `omarchy plugin add` + first run):
`~/.config/omarchy/plugins/scratchpad-studio/` (the repo clone),
`~/.config/scratchpad-studio/{scratchpads.json,backups/}`,
`~/.config/hypr/scratchpad-studio.lua`, managed block in
`~/.config/hypr/bindings.lua`. Uninstall removes exactly these.

## GUI surfaces

1. **Bar widget** (left-click): opens the Studio panel (PopupCard, up to
   ~1000×680 logical px) — overview grid by default.
2. **App window**: right-click / button opens a FloatingWindow
   (`StudioWindow.qml`) with identical views; per-session size persistence
   like blip.
3. **IPC**: `qs -p /usr/share/omarchy/shell ipc call scratchpad-studio
   open|close|toggle|demo …`; `omarchy-shell shell toggle scratchpad-studio`
   works for keybinds (verified routing: shell → bar.summonBarWidget →
   widget.open()).

### Views

- **Overview grid**: card per scratchpad — name + icon, keybind chip,
  status dot (running = has windows / shown = special visible / idle),
  live schematic preview: real window rectangles from `hyprctl clients -j`
  drawn to scale with app icons (`DesktopEntries.heuristicLookup` +
  `Quickshell.iconPath`); screencopy of hidden windows is impossible, so
  schematics are the honest preview. Actions: toggle, edit, duplicate,
  delete. Foreign specials show an "Adopt" affordance instead of edit.
- **Wizard** (new/edit, 5 steps, keyboard-first, Esc = back):
  1. Name + icon (glyph field with suggestions).
  2. Apps: search installed `.desktop` entries, pick a live window
     (auto-fills class from `hyprctl clients`), or custom command/URL.
     Single-instance and web-app detection sets `class`/`singleInstance`
     automatically (known-apps table + `--app=` heuristics).
  3. Layout: thumbnails (single / pair / stacked / three-up / grid) +
     anchor + size sliders (percent) + margin.
  4. Transition: from-top/bottom/left/right with a small motion preview
     (the reveal itself follows Hyprland's specialWorkspace animation;
     the choice drives window `animation` rule + anchor defaults).
  5. Keybind: press-to-capture (PanelKeyCatcher), live conflict check
     against `hyprctl -j binds` **and** textual scan of `~/.config/hypr/`
     `o.bind(`/`hl.bind(` lines; suggested free chords (e.g. SUPER+M…);
     Omarchy-default collisions get a loud warning. Summary + "Test it
     now" (applies temporarily, toggles the real scratchpad, undo).
- **Theming**: `qs.Commons` `Color`/`Style` singletons — palette from
  `~/.local/state/omarchy/current/theme/colors.toml` via the shell; spacing
  via `Style.space()`; the shell re-reads on theme change, so the plugin
  follows automatically. Focus rings from Style state tokens.

## Testing & verification

- `tests/` unit-test geometry math, Lua generation (golden strings),
  conflict detection, and managed-block add/remove/idempotency against
  copies of a real bindings.lua.
- Milestone screenshots via `grim` into the task data dir; README shots
  use demo mode (fake windows/titles only).
- Manual matrix: fresh install, existing-config upgrade, uninstall
  residue check (`git -C ~/.config/hypr diff` + file list), Cider
  single-instance, web app class, monitor-dock regeneration.

## Milestones

a. Read-only overview grid with live schematics + demo mode
b. Toggle/delete + helper CLI + apply pipeline (state→lua→reload→verify)
c. Wizard: app picker, layout, transition, summary, test-it-now
d. Keybind capture + conflict detection + managed block writes
e. Polish (keyboard nav, focus rings, empty states), tests, README,
   uninstall
