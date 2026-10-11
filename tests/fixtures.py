"""Shared test fixtures: import the helper CLI as a module and build states."""

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import sys
from pathlib import Path
from unittest import TestCase

HELPER = Path(__file__).resolve().parent.parent / "bin" / "scratchpad-studio"

# The helper is an extensionless executable; load it explicitly.
_loader = SourceFileLoader("scratchpad_studio", str(HELPER))
_spec = importlib.util.spec_from_loader("scratchpad_studio", _loader)
sst = importlib.util.module_from_spec(_spec)
_loader.exec_module(sst)

# A laptop-ish monitor: 2880x1800 @1.6 -> 1800x1125 logical.
MONITOR = {"name": "eDP-1", "width": 2880, "height": 1800, "scale": 1.6}
USABLE = (1800, 1125)


def sp(**overrides) -> dict:
    base = {
        "id": "music",
        "name": "Music",
        "icon": "󰎈",
        "keybind": "ALT + SUPER + M",
        "anchor": "top",
        "layout": "single",
        "transition": "down",
        "sizePct": {"w": 60, "h": 50},
        "marginPx": 12,
        "apps": [
            {"name": "Cider", "command": "cider", "class": "Cider",
             "webapp": False, "singleInstance": True},
        ],
    }
    base.update(overrides)
    return sst.normalize_sp(base)


def state(*scratchpads) -> dict:
    return {"version": 1, "scratchpads": list(scratchpads)}


class FixtureCase(TestCase):
    def setUp(self) -> None:
        self.sst = sst
