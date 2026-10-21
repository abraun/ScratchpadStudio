"""Every .qml file must import the module for each type it instantiates.

A missing import does not stay local: one broken view fails the whole
widget compile, which takes down the bar icon and every surface the
plugin hosts (the capture-round regression)."""
import subprocess
import sys
import unittest
from pathlib import Path

LINT = Path(__file__).resolve().parent / "qml_import_lint.py"


class TestQmlImports(unittest.TestCase):
    def test_all_qml_files_import_their_modules(self):
        result = subprocess.run(
            [sys.executable, str(LINT)], capture_output=True, text=True)
        self.assertEqual(
            result.returncode, 0,
            "qml import lint failed:\n" + result.stdout + result.stderr)

    def test_lint_catches_a_missing_layouts_import(self):
        # the lint must actually flag the regression it exists for
        import tempfile
        bad = Path(tempfile.mkdtemp()) / "Bad.qml"
        bad.write_text("import QtQuick\nColumnLayout { }\n")
        from qml_import_lint import missing_imports
        problems = missing_imports(bad)
        self.assertTrue(any("QtQuick.Layouts" in p for p in problems))
