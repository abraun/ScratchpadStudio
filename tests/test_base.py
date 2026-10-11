"""Base import shared by test modules."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixtures import FixtureCase  # noqa: E402,F401

__all__ = ["FixtureCase"]
