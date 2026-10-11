"""Conflict detection for keybinds (milestone d core, landed with tests)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_base import FixtureCase  # noqa: E402


MOD_BITS = [
    (1, "SHIFT"),
    (2, "CAPS"),
    (4, "CTRL"),
    (8, "ALT"),
    (16, "MOD2"),
    (32, "MOD3"),
    (64, "SUPER"),
    (128, "MOD5"),
]


class TestConflictParsing(FixtureCase):
    def test_chord_to_modmask_roundtrip(self):
        self.assertEqual(self.sst.chord_modmask("SUPER + S"), 64)
        self.assertEqual(self.sst.chord_modmask("ALT + SUPER + P"), 72)
        self.assertEqual(self.sst.chord_modmask("SHIFT + CTRL + SUPER + A"), 69)
        self.assertEqual(self.sst.chord_modmask("S"), 0)

    def test_chord_key_normalization(self):
        self.assertEqual(self.sst.chord_key("ALT + SUPER + P"), "P")
        self.assertEqual(self.sst.chord_key("super+p"), "p")

    def test_invalid_chords_return_none(self):
        self.assertIsNone(self.sst.chord_modmask("SUPER + "))
        self.assertIsNone(self.sst.chord_modmask(""))
        self.assertIsNone(self.sst.chord_modmask("HYPER + X"))

    def test_conflict_against_hyprctl_binds(self):
        # Shape mirrors hyprctl -j binds entries (modmask int + key string).
        binds = [
            {"modmask": 64, "key": "S", "description": "Toggle scratchpad"},
            {"modmask": 72, "key": "P", "description": "Scratchpad: Test Pad"},
            {"modmask": 69, "key": "A", "description": "Agent"},
        ]
        hit = self.sst.find_bind_conflict("ALT + SUPER + P", binds)
        self.assertIsNotNone(hit)
        self.assertEqual(hit["description"], "Scratchpad: Test Pad")
        miss = self.sst.find_bind_conflict("ALT + SUPER + K", binds)
        self.assertIsNone(miss)

    def test_conflict_ignores_different_modifiers(self):
        binds = [{"modmask": 64, "key": "M", "description": "duper M"}]
        self.assertIsNone(self.sst.find_bind_conflict("SHIFT + SUPER + M", binds))

    def test_config_file_scan_finds_obind_lines(self):
        files = {
            "bindings.lua": 'o.bind("SUPER + M", "Mine", "cmd")\n-- noise\n',
            "other.lua": 'hl.bind("SUPER + N", fn)\n',
        }
        hits = self.sst.scan_config_chords(files)
        self.assertIn(("SUPER + M", "bindings.lua"), hits)
        self.assertIn(("SUPER + N", "other.lua"), hits)

    def test_our_own_managed_lines_are_ignored(self):
        content = (
            self.sst.BLOCK_BEGIN + "\n"
            'o.bind("SUPER + M", "Scratchpad: Music", "x")\n'
            + self.sst.BLOCK_END + "\n"
        )
        hits = self.sst.scan_config_chords({"scratchpad-studio.lua": content})
        self.assertEqual(hits, [])
