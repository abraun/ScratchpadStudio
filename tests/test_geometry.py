"""Geometry math: anchors, sizes, layouts, margins.

These numbers are baked into generated window rules as pixels, so they are
pinned precisely here. lib/Layout.js mirrors this logic for the wizard
preview — if a test here changes, update the JS twin to match.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixtures import MONITOR, USABLE, sp, state  # noqa: E402
from test_base import FixtureCase  # noqa: E402

HELPER = "/home/abraun/.config/omarchy/plugins/scratchpad-studio/bin/scratchpad-studio"


class TestBaseRect(FixtureCase):
    def test_top_anchor_centers_horizontally(self):
        rect = self.sst.base_rect(sp(anchor="top"), USABLE)
        self.assertEqual(rect, (360, 12, 1080, 562))

    def test_bottom_anchor(self):
        rect = self.sst.base_rect(sp(anchor="bottom"), USABLE)
        self.assertEqual(rect[1], 1125 - 12 - 562)  # 551
        self.assertEqual(rect[0], 360)  # still centered

    def test_left_anchor_centers_vertically(self):
        rect = self.sst.base_rect(sp(anchor="left"), USABLE)
        self.assertEqual(rect[0], 12)
        self.assertEqual(rect[1], (1125 - 562) // 2)

    def test_right_anchor(self):
        rect = self.sst.base_rect(sp(anchor="right"), USABLE)
        self.assertEqual(rect[0], 1800 - 12 - 1080)

    def test_margin_scales_with_state(self):
        rect = self.sst.base_rect(sp(anchor="top", marginPx=0), USABLE)
        self.assertEqual(rect[1], 0)

    def test_minimum_size_clamp(self):
        rect = self.sst.base_rect(
            sp(anchor="top", sizePct={"w": 30, "h": 25}), (400, 300))
        # 30% of 400 = 120 -> clamped to 200; 25% of 300 = 75 -> clamped to 140
        self.assertEqual(rect[2], 200)
        self.assertEqual(rect[3], 140)


class TestLayoutRects(FixtureCase):
    def apps(self, n, cls="App"):
        return [
            {"name": f"App {i}", "command": f"app{i}", "class": f"{cls}{i}",
             "webapp": False, "singleInstance": False}
            for i in range(n)
        ]

    def test_single_app_fills_base(self):
        rects = self.sst.layout_rects(sp(), USABLE)
        self.assertEqual(len(rects), 1)
        self.assertEqual(rects[0], (360, 12, 1080, 562))

    def test_pair_splits_two_columns(self):
        rects = self.sst.layout_rects(
            sp(layout="pair", apps=self.apps(2)), USABLE)
        self.assertEqual(len(rects), 2)
        left, right = rects
        self.assertEqual(left[0], 360)
        self.assertEqual(right[0], left[0] + left[2] + 6)  # gap = margin/2
        self.assertEqual(left[3], right[3])  # same height
        # columns tile the base width with the gap between them
        self.assertEqual(left[2] + 6 + right[2], 1080)

    def test_stacked_overlays_all_windows(self):
        rects = self.sst.layout_rects(
            sp(layout="stacked", apps=self.apps(3)), USABLE)
        self.assertEqual(len(rects), 3)
        for rect in rects[1:]:
            self.assertEqual(rect, rects[0])

    def test_three_up_three_columns(self):
        rects = self.sst.layout_rects(
            sp(layout="three-up", apps=self.apps(3)), USABLE)
        cols = sorted(r[0] for r in rects)
        self.assertEqual(len(rects), 3)
        self.assertNotEqual(cols[0], cols[1])
        self.assertNotEqual(cols[1], cols[2])

    def test_grid_two_by_two(self):
        rects = self.sst.layout_rects(
            sp(layout="grid", apps=self.apps(4)), USABLE)
        self.assertEqual(len(rects), 4)
        xs = {r[0] for r in rects}
        ys = {r[1] for r in rects}
        self.assertEqual(len(xs), 2)  # two columns
        self.assertEqual(len(ys), 2)  # two rows

    def test_extra_apps_beyond_grid_wrap_rows(self):
        rects = self.sst.layout_rects(
            sp(layout="grid", apps=self.apps(6)), USABLE)
        ys = {r[1] for r in rects}
        self.assertEqual(len(ys), 3)  # three rows of two

    def test_single_layout_extra_apps_overlay(self):
        rects = self.sst.layout_rects(
            sp(layout="single", apps=self.apps(2)), USABLE)
        self.assertEqual(rects[0], rects[1])


class TestNormalization(FixtureCase):
    def test_defaults_fill_missing_fields(self):
        out = self.sst.normalize_sp({"id": "x"})
        self.assertEqual(out["anchor"], "top")
        self.assertEqual(out["layout"], "single")
        self.assertEqual(out["sizePct"], {"w": 60, "h": 50})
        self.assertEqual(out["marginPx"], 12)
        self.assertEqual(out["apps"], [])

    def test_size_pct_clamped(self):
        out = self.sst.normalize_sp({"id": "x", "sizePct": {"w": 500, "h": 1}})
        self.assertEqual(out["sizePct"], {"w": 95, "h": 25})

    def test_bad_values_fall_back(self):
        out = self.sst.normalize_sp(
            {"id": "x", "anchor": "diagonal", "layout": "blob"})
        self.assertEqual(out["anchor"], "top")
        self.assertEqual(out["layout"], "single")

    def test_slug_generation(self):
        self.assertEqual(self.sst.slug("My Music! Pad"), "my-music-pad")
        self.assertEqual(self.sst.slug("??"), "scratchpad")

    def test_state_roundtrip(self):
        st = self.sst.normalize_state(state(sp()))
        self.assertEqual(st["version"], 1)
        self.assertEqual(len(st["scratchpads"]), 1)
        self.assertEqual(st["scratchpads"][0]["id"], "music")


class TestCenterAnchor(FixtureCase):
    """The center anchor: frame centered on both axes (margin-free), slots
    laid out inside it exactly like any other anchor."""

    def test_center_anchor_centers_both_axes(self):
        rect = self.sst.base_rect(sp(anchor="center"), USABLE)
        self.assertEqual(rect[0], (1800 - 1080) // 2)   # 360
        self.assertEqual(rect[1], (1125 - 562) // 2)    # 281 (floor)
        # margin does not push a centered frame off-center
        self.assertEqual(
            self.sst.base_rect(sp(anchor="center", marginPx=40), USABLE),
            rect,
        )

    def test_center_anchor_passes_normalization(self):
        out = self.sst.normalize_sp({"id": "x", "anchor": "center"})
        self.assertEqual(out["anchor"], "center")

    def test_center_slots_inside_frame(self):
        pad = sp(anchor="center", layout="pair", apps=[
            {"name": "A", "command": "a", "class": "A",
             "webapp": False, "singleInstance": False},
            {"name": "B", "command": "b", "class": "B",
             "webapp": False, "singleInstance": False},
        ])
        rects = self.sst.layout_rects(pad, USABLE)
        x, y, w, h = self.sst.base_rect(pad, USABLE)
        left, right = rects
        self.assertEqual(left[0], x)
        self.assertEqual(left[1], y)
        self.assertEqual(right[0] + right[2], x + w)
        self.assertEqual(right[1], y)
        self.assertEqual(left[3], h)
        self.assertEqual(right[3], h)


class TestPopinTransition(FixtureCase):
    def test_popin_passes_normalization(self):
        out = self.sst.normalize_sp({"id": "x", "transition": "popin"})
        self.assertEqual(out["transition"], "popin")

    def test_invalid_transition_still_falls_back(self):
        out = self.sst.normalize_sp({"id": "x", "transition": "zoom"})
        self.assertEqual(out["transition"], "down")

    def test_popin_rule_uses_popin_animation(self):
        pad = sp(transition="popin")
        rules = self.sst.runtime_rules(pad, MONITOR)
        self.assertIn('animation = "popin"', rules[0])
        self.assertNotIn('animation = "slide"', rules[0])
        lua = self.sst.generate_lua(state(pad), HELPER, MONITOR)
        self.assertIn('animation = "popin"', lua)


class TestWideLayouts(FixtureCase):
    """One window spans its half, the rest stack in the other — the
    L-shape the captain asked for (chromium full-height left, two stacked
    right)."""

    def apps(self, n):
        return [
            {"name": f"App {i}", "command": f"app{i}", "class": f"A{i}",
             "webapp": False, "singleInstance": False}
            for i in range(n)
        ]

    def wide(self, layout, n):
        return sp(layout=layout, anchor="right", sizePct={"w": 72, "h": 80},
                  apps=self.apps(n))

    def test_wide_left_three(self):
        pad = self.wide("wide-left", 3)
        rects = self.sst.layout_rects(pad, USABLE)
        tall, top, bottom = rects
        x, y, w, h = self.sst.base_rect(pad, USABLE)
        # tall window: full height of the left half
        self.assertEqual(tall, (x, y, (w - 6) // 2, h))
        # two stacked right, evenly split with a gap
        self.assertEqual(top[0], bottom[0])
        self.assertEqual(top[2], bottom[2])
        self.assertEqual(top[1] + top[3] + 6, bottom[1])
        self.assertEqual(bottom[1] + bottom[3], y + h)
        # columns do not overlap
        self.assertLessEqual(tall[0] + tall[2] + 6, top[0])

    def test_wide_right_mirrors(self):
        pad = self.wide("wide-right", 3)
        rects = self.sst.layout_rects(pad, USABLE)
        top, bottom, tall = rects
        x, y, w, h = self.sst.base_rect(pad, USABLE)
        self.assertEqual(tall, (x + w - (w - 6) // 2, y, (w - 6) // 2, h))
        self.assertEqual(top[0], bottom[0])
        self.assertEqual(top[1] + top[3] + 6, bottom[1])

    def test_two_apps_is_pair(self):
        pad = self.wide("wide-left", 2)
        pair = sp(layout="pair", anchor="right", sizePct={"w": 72, "h": 80},
                  apps=self.apps(2))
        self.assertEqual(self.sst.layout_rects(pad, USABLE),
                         self.sst.layout_rects(pair, USABLE))

    def test_single_app_fills_frame(self):
        pad = self.wide("wide-left", 1)
        rects = self.sst.layout_rects(pad, USABLE)
        self.assertEqual(rects[0], self.sst.base_rect(pad, USABLE))

    def test_layouts_pass_normalization(self):
        self.assertEqual(self.sst.normalize_sp({"id": "x", "layout": "wide-left"})["layout"],
                         "wide-left")
        self.assertEqual(self.sst.normalize_sp({"id": "x", "layout": "wide-right"})["layout"],
                         "wide-right")
        self.assertEqual(self.sst.normalize_sp({"id": "x", "layout": "diagonal"})["layout"],
                         "single")
