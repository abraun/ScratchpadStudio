"""Edit-mode behaviors: placement mode, reflow planning, app-removal
relocation, and keybind replacement in the generated config.

The editor's save path is `upsert`: state merge -> regenerate -> reload ->
relocate removed apps' windows -> reflow open windows onto new slots.
Everything hyprctl-touching stays thin; the pure planning functions here
are what these tests pin.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixtures import MONITOR, USABLE, sp, state  # noqa: E402
from test_base import FixtureCase  # noqa: E402

HELPER = "/home/abraun/.config/omarchy/plugins/scratchpad-studio/bin/scratchpad-studio"


def client(cls, address, ws="special:music", mapped=True):
    return {"class": cls, "address": address, "mapped": mapped,
            "workspace": {"name": ws}}


class TestPlacement(FixtureCase):
    def test_missing_placement_defaults_to_slots(self):
        out = self.sst.normalize_sp({"id": "x"})
        self.assertEqual(out["placement"], "slots")

    def test_placement_values_pass_through_or_fallback(self):
        self.assertEqual(self.sst.normalize_sp(
            {"id": "x", "placement": "floating"})["placement"], "floating")
        self.assertEqual(self.sst.normalize_sp(
            {"id": "x", "placement": "tiled?!"})["placement"], "slots")

    def test_floating_rule_omits_geometry(self):
        lua = self.sst.generate_lua(
            state(sp(placement="floating")), HELPER, MONITOR)
        self.assertIn(
            'o.window({ class = "Cider" }, '
            '{ workspace = "special:music silent", float = true, '
            'animation = "slide" })',
            lua,
        )
        self.assertNotIn("size =", lua.replace('size = "1040 700"', ""))
        self.assertNotIn("move =", lua)
        self.assertNotIn('monitor = "eDP-1"', lua)

    def test_slots_rule_unchanged_shape(self):
        lua = self.sst.generate_lua(state(sp()), HELPER, MONITOR)
        self.assertIn('size = "1080 562", move = "360 12"', lua)
        self.assertIn('monitor = "eDP-1"', lua)

    def test_runtime_rules_match_placement(self):
        rules = self.sst.runtime_rules(sp(placement="floating"), MONITOR)
        self.assertEqual(len(rules), 1)
        self.assertNotIn("size", rules[0])
        rules = self.sst.runtime_rules(sp(), MONITOR)
        self.assertIn('size = "1080 562"', rules[0])


class TestRemovedClasses(FixtureCase):
    def test_removed_app_class_is_reported(self):
        old = sp(apps=[
            {"name": "A", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
            {"name": "B", "command": "b", "class": "B",
             "webapp": False, "singleInstance": False},
        ])
        new = sp(apps=[old["apps"][0]])
        self.assertEqual(self.sst.removed_classes(old, new), ["B"])

    def test_kept_and_reordered_apps_report_nothing(self):
        old = sp(layout="pair", apps=[
            {"name": "A", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
            {"name": "B", "command": "b", "class": "B",
             "webapp": False, "singleInstance": False},
        ])
        new = sp(layout="pair", apps=[old["apps"][1], old["apps"][0]])
        self.assertEqual(self.sst.removed_classes(old, new), [])

    def test_class_removed_then_readded_elsewhere_in_list(self):
        # same class still present => its windows stay on the scratchpad
        old = sp(apps=[
            {"name": "A", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
        ])
        new = sp(apps=[
            {"name": "A2", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
        ])
        self.assertEqual(self.sst.removed_classes(old, new), [])

    def test_classless_app_removal_is_ignored(self):
        old = sp(apps=[{"name": "W", "command": "w", "class": "",
                        "webapp": False, "singleInstance": False}])
        new = sp(apps=[])
        self.assertEqual(self.sst.removed_classes(old, new), [])


class TestPlanReflow(FixtureCase):
    def test_windows_map_to_their_app_slots(self):
        pad = sp(layout="pair", apps=[
            {"name": "A", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
            {"name": "B", "command": "b", "class": "B",
             "webapp": False, "singleInstance": False},
        ])
        clients = [client("B", "0x2"), client("A", "0x1")]
        plans = self.sst.plan_reflow(pad, USABLE, clients)
        by_class = {p["class"]: p for p in plans}
        left, right = self.sst.layout_rects(pad, USABLE)
        self.assertEqual(by_class["A"]["rect"], left)
        self.assertEqual(by_class["B"]["rect"], right)
        self.assertEqual(by_class["A"]["address"], "0x1")
        # tiled windows are flagged so reflow floats them first
        self.assertFalse(by_class["A"]["floating"])
        floated = [dict(c, floating=True) for c in clients]
        plans = self.sst.plan_reflow(pad, USABLE, floated)
        self.assertTrue(all(p["floating"] for p in plans))

    def test_windows_of_same_class_share_the_slot(self):
        pad = sp(layout="single", apps=[
            {"name": "A", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
        ])
        clients = [client("A", "0x1"), client("A", "0x2")]
        plans = self.sst.plan_reflow(pad, USABLE, clients)
        self.assertEqual(len(plans), 2)
        self.assertEqual(plans[0]["rect"], plans[1]["rect"])

    def test_unmapped_and_foreign_windows_ignored(self):
        pad = sp()
        clients = [
            client("Cider", "0x1", mapped=False),
            client("Cider", "0x2", ws="special:elsewhere"),
            client("Cider", "0x3", ws="1"),
        ]
        self.assertEqual(self.sst.plan_reflow(pad, USABLE, clients), [])

    def test_floating_placement_pins_nothing(self):
        pad = sp(placement="floating")
        clients = [client("Cider", "0x1")]
        self.assertEqual(self.sst.plan_reflow(pad, USABLE, clients), [])


class TestKeybindReplacement(FixtureCase):
    def test_changed_bind_replaces_old_line(self):
        old = sp(keybind="ALT + SUPER + M")
        new = sp(keybind="ALT + SUPER + N")
        lua = self.sst.generate_lua(state(new), HELPER, MONITOR)
        self.assertIn('o.bind("ALT + SUPER + N"', lua)
        self.assertNotIn("ALT + SUPER + M", lua)
        # exactly one bind for the scratchpad — no orphans
        self.assertEqual(lua.count("o.bind("), 1)

    def test_cleared_bind_emits_none(self):
        lua = self.sst.generate_lua(state(sp(keybind="")), HELPER, MONITOR)
        self.assertNotIn("o.bind", lua)

    def test_two_scratchpads_one_bind_each(self):
        other = sp(id="ai", name="AI", keybind="ALT + SUPER + A")
        lua = self.sst.generate_lua(
            state(sp(keybind="ALT + SUPER + M"), other), HELPER, MONITOR)
        self.assertEqual(lua.count("o.bind("), 2)

    def test_self_bind_match_by_arg_and_description(self):
        self.assertTrue(self.sst.self_bind_match(
            {"arg": "/helper toggle music",
             "description": "Scratchpad: Music"}, "music", "Music"))
        self.assertTrue(self.sst.self_bind_match(
            {"arg": "", "description": "Scratchpad: Music"}, "music", "Music"))
        self.assertFalse(self.sst.self_bind_match(
            {"arg": "/helper toggle ai",
             "description": "Scratchpad: AI"}, "music", "Music"))
        self.assertFalse(self.sst.self_bind_match(
            {"arg": "", "description": "Toggle scratchpad"}, "music", "Music"))

    def test_filter_self_binds_keeps_the_rest(self):
        binds = [
            {"modmask": 72, "key": "M", "description": "Scratchpad: Music",
             "arg": "/helper toggle music"},
            {"modmask": 72, "key": "A", "description": "Scratchpad: AI",
             "arg": "/helper toggle ai"},
            {"modmask": 64, "key": "S", "description": "Omarchy scratchpad",
             "arg": "togglespecialworkspace"},
        ]
        kept = self.sst.filter_self_binds(binds, "music", "Music")
        self.assertEqual(len(kept), 2)
        self.assertIsNone(self.sst.find_bind_conflict("ALT + SUPER + M", kept))
        hit = self.sst.find_bind_conflict("ALT + SUPER + A", kept)
        self.assertIsNotNone(hit)


class TestUniqueId(FixtureCase):
    """New scratchpads must never share a special workspace: ids are
    de-duplicated against state AND the reserved built-in (the captain's
    SUPER+S/SUPER+D confusion came from a scratchpad slugged 'scratchpad'
    landing on Omarchy's built-in special:scratchpad)."""

    def test_free_id_passes_through(self):
        self.assertEqual(self.sst.unique_id("music", ["ai", "browsing"]), "music")

    def test_reserved_builtin_is_never_assigned(self):
        self.assertEqual(self.sst.unique_id("scratchpad", []), "scratchpad-2")
        self.assertEqual(self.sst.unique_id("Scratchpad", ["ai"]), "scratchpad-2")

    def test_collision_chains_forward(self):
        taken = ["scratchpad", "scratchpad-2", "scratchpad-3"]
        self.assertEqual(self.sst.unique_id("scratchpad", taken), "scratchpad-4")
        self.assertEqual(self.sst.unique_id("music", ["music", "music-2"]), "music-3")

    def test_slug_normalization_applies_first(self):
        self.assertEqual(self.sst.unique_id("My Music!!", ["my-music"]), "my-music-2")

    def test_empty_candidate_still_avoids_reserved(self):
        self.assertEqual(self.sst.unique_id("", []), "scratchpad-2")


class TestChordOwners(FixtureCase):
    """Conflict detection by state: another scratchpad's chord is a hard
    conflict; the scratchpad being edited never conflicts with itself."""

    def owners(self, chord, exclude=None):
        return self.sst.scratchpad_chord_owners(
            state(sp(keybind="ALT + SUPER + M"),
                  sp(id="ai", name="AI", keybind="ALT + SUPER + A")),
            chord, exclude)

    def test_other_scratchpad_chord_is_reported(self):
        self.assertEqual(self.owners("ALT + SUPER + A"),
                         [{"id": "ai", "name": "AI"}])

    def test_own_chord_is_excluded(self):
        self.assertEqual(self.owners("ALT + SUPER + M", exclude="music"), [])

    def test_empty_chord_has_no_owners(self):
        self.assertEqual(self.owners(""), [])


class TestManagedBindFiltering(FixtureCase):
    """The live-bind conflict check must skip every managed bind, even when
    the scratchpad being edited has been renamed (its own bind still
    carries the old description and Hyprland reports our args as numbers,
    so nothing else identifies it)."""

    def test_renamed_scratchpads_stale_bind_is_not_a_conflict(self):
        # the scratchpad was renamed "Music" -> "Focus"; its live bind still
        # says "Scratchpad: Music" until the next apply
        stale_own = {"modmask": 72, "key": "M",
                     "description": "Scratchpad: Music", "arg": "92"}
        kept = self.sst.filter_managed_binds([stale_own])
        self.assertEqual(kept, [])
        self.assertIsNone(self.sst.find_bind_conflict("ALT + SUPER + M", kept))

    def test_foreign_binds_survive_the_filter(self):
        omarchy = {"modmask": 64, "key": "S",
                   "description": "Toggle scratchpad", "arg": "131"}
        kept = self.sst.filter_managed_binds([omarchy])
        self.assertEqual(len(kept), 1)
        self.assertIsNotNone(self.sst.find_bind_conflict("SUPER + S", kept))
