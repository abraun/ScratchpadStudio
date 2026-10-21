"""Lua generation and managed-block editing.

The generated file is the plugin's persistent footprint in ~/.config/hypr;
these tests pin its exact shape so accidental changes surface in review.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixtures import MONITOR, sp, state  # noqa: E402
from test_base import FixtureCase  # noqa: E402

HELPER = "/home/abraun/.config/omarchy/plugins/scratchpad-studio/bin/scratchpad-studio"


class TestGenerateLua(FixtureCase):
    def test_empty_state_generates_no_scratchpad_rules(self):
        lua = self.sst.generate_lua(state(), HELPER, MONITOR)
        self.assertIn("no scratchpads configured", lua)
        # the studio's own window rule is always present; nothing else is
        self.assertEqual(lua.count("o.window"), 1)
        self.assertNotIn("o.bind", lua)

    def test_no_class_global_window_rules(self):
        # class-global o.window rules captured EVERY window of a managed
        # class - fresh launches outside the scratchpad included. The
        # generated config must never contain them: only the studio's own
        # window rule, binds, and comments.
        lua = self.sst.generate_lua(state(sp()), HELPER, MONITOR)
        self.assertNotIn("special:music silent", lua)
        self.assertEqual(lua.count("o.window"), 1)  # the studio rule only
        self.assertNotIn("Cider", lua)

    def test_bind_shape_uses_absolute_helper(self):
        lua = self.sst.generate_lua(state(sp()), HELPER, MONITOR)
        self.assertIn(
            'o.bind("ALT + SUPER + M", "Scratchpad: Music", '
            f'"{HELPER} toggle music")',
            lua,
        )

    def test_unbound_scratchpad_omits_bind(self):
        lua = self.sst.generate_lua(state(sp(keybind="")), HELPER, MONITOR)
        self.assertNotIn("o.bind", lua)

    def test_classless_app_emits_no_rule(self):
        app = {"name": "Weird", "command": "weird", "class": "",
               "webapp": False, "singleInstance": False}
        lua = self.sst.generate_lua(state(sp(apps=[app])), HELPER, MONITOR)
        # only the studio window's own rule
        self.assertEqual(lua.count("o.window"), 1)
        self.assertNotIn('class = ""', lua)

    def test_studio_window_float_rule_always_present(self):
        lua = self.sst.generate_lua(state(), HELPER, MONITOR)
        self.assertIn(
            'o.window({ class = "^org.quickshell$", title = "^Scratchpad Studio$" }, '
            '{ float = true, size = "1040 700" })',
            lua,
        )

    def test_luajacking_via_class_name_is_escaped(self):
        evil_class = 'a"), os.exit()--'
        app = {"name": "Evil", "command": "x", "class": evil_class,
               "webapp": False, "singleInstance": False}
        lua = self.sst.generate_lua(state(sp(apps=[app])), HELPER, MONITOR)
        # No rule interpolates the class anymore, so nothing can be broken
        # open; the generated config stays syntactically inert.
        self.assertNotIn('os.exit()', lua)

    def test_multi_app_layout_positions(self):
        apps = [
            {"name": "A", "command": "a", "class": "A", "webapp": False,
             "singleInstance": False},
            {"name": "B", "command": "b", "class": "B", "webapp": False,
             "singleInstance": False},
        ]
        pad = sp(layout="pair", apps=apps)
        rects = self.sst.layout_rects(pad, (1800, 1125))
        # both windows sized to half minus the gap
        self.assertEqual(rects[0][2], 537)
        self.assertEqual(rects[1][2], 537)


class TestManagedBlock(FixtureCase):
    USER_BODY = '-- personal binds\nhl.unbind("SUPER + F")\n'

    def test_insert_appends_block(self):
        out = self.sst.ensure_block(self.USER_BODY)
        self.assertIn(self.sst.BLOCK_BEGIN, out)
        self.assertIn('require("hypr.scratchpad-studio")', out)
        self.assertIn(self.sst.BLOCK_END, out)
        # user content untouched and above the block
        self.assertLess(out.index("hl.unbind"), out.index(self.sst.BLOCK_BEGIN))

    def test_insert_is_idempotent(self):
        once = self.sst.ensure_block(self.USER_BODY)
        twice = self.sst.ensure_block(once)
        self.assertEqual(once, twice)

    def test_replace_rewrites_block_content_only(self):
        once = self.sst.ensure_block(self.USER_BODY)
        tampered = once.replace('require("hypr.scratchpad-studio")',
                                'require("evil")')
        again = self.sst.ensure_block(tampered)
        self.assertIn('require("hypr.scratchpad-studio")', again)
        self.assertNotIn("evil", again)
        self.assertEqual(again.count(self.sst.BLOCK_BEGIN), 1)

    def test_remove_restores_original(self):
        once = self.sst.ensure_block(self.USER_BODY)
        self.assertEqual(self.sst.remove_block(once), self.USER_BODY)

    def test_remove_without_block_is_noop(self):
        self.assertEqual(self.sst.remove_block(self.USER_BODY), self.USER_BODY)

    def test_remove_broken_block_raises(self):
        broken = self.USER_BODY + self.sst.BLOCK_BEGIN + "\n" + 'require("x")'
        with self.assertRaises(RuntimeError):
            self.sst.remove_block(broken)

    def test_empty_bindings_file(self):
        out = self.sst.ensure_block("")
        self.assertTrue(out.startswith(self.sst.BLOCK_BEGIN))
        self.assertEqual(self.sst.remove_block(out), "")
