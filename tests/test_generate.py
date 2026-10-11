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
    def test_empty_state_generates_comment_only(self):
        lua = self.sst.generate_lua(state(), HELPER, MONITOR)
        self.assertNotIn("o.window", lua)
        self.assertNotIn("o.bind", lua)
        self.assertIn("no scratchpads configured", lua)

    def test_window_rule_shape(self):
        lua = self.sst.generate_lua(state(sp()), HELPER, MONITOR)
        self.assertIn(
            'o.window({ class = "Cider" }, '
            '{ workspace = "special:music silent", float = true, '
            'size = "1080 562", move = "360 12", '
            'monitor = "eDP-1", animation = "slide" })',
            lua,
        )

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
        self.assertNotIn("o.window", lua)

    def test_luajacking_via_class_name_is_escaped(self):
        evil_class = 'a"), os.exit()--'
        app = {"name": "Evil", "command": "x", "class": evil_class,
               "webapp": False, "singleInstance": False}
        lua = self.sst.generate_lua(state(sp(apps=[app])), HELPER, MONITOR)
        # The quote inside the class is escaped, so no rule is syntactically
        # broken open (the class simply will not match a real window).
        self.assertIn('class = "a\\"), os.exit()--"', lua)

    def test_multi_app_layout_positions(self):
        apps = [
            {"name": "A", "command": "a", "class": "A", "webapp": False,
             "singleInstance": False},
            {"name": "B", "command": "b", "class": "B", "webapp": False,
             "singleInstance": False},
        ]
        lua = self.sst.generate_lua(state(sp(layout="pair", apps=apps)), HELPER, MONITOR)
        self.assertIn('class = "A"', lua)
        self.assertIn('class = "B"', lua)
        # both windows sized to half minus the gap
        self.assertIn('size = "537 562"', lua)


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
