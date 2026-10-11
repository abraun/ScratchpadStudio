"""App catalogue parsing: .desktop resolution, webapp classes, single-instance."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_base import FixtureCase  # noqa: E402


class TestDesktopParsing(FixtureCase):
    def test_exec_binary_strips_flags_and_field_codes(self):
        self.assertEqual(self.sst._exec_binary("foot -e htop"), "foot")
        self.assertEqual(self.sst._exec_binary("code %F"), "code")
        self.assertEqual(self.sst._exec_binary("/usr/bin/firefox %u"), "firefox")
        self.assertEqual(self.sst._exec_binary(""), "")

    def test_webapp_class_derivation(self):
        self.assertEqual(self.sst.webapp_class("https://claude.ai"),
                         "chrome-claude.ai__-Default")
        self.assertEqual(self.sst.webapp_class("https://www.youtube.com/watch"),
                         "chrome-youtube.com__-Default")
        self.assertEqual(self.sst.webapp_class("https://maps.google.com"),
                         "chrome-maps.google.com__-Default")

    def test_catalogue_webapp_never_blocks_launch(self):
        entry = self.sst._parse_desktop_file.__globals__  # sanity: module alive
        apps = self.sst.app_catalogue()
        webapps = [a for a in apps if a["webapp"]]
        for app in webapps:
            self.assertFalse(
                app["singleInstance"],
                f"{app['name']}: chromium --app maps a new window per launch",
            )

    def test_catalogue_has_entries_and_shapes(self):
        apps = self.sst.app_catalogue()
        self.assertGreater(len(apps), 10)
        for app in apps:
            self.assertIn("name", app)
            self.assertIn("command", app)
            self.assertIn("wmClass", app)
            self.assertIn("webapp", app)
            self.assertIn("singleInstance", app)

    def test_cider_is_single_instance(self):
        apps = self.sst.app_catalogue()
        cider = [a for a in apps if "cider" in a["id"].lower()]
        if cider:  # only when installed (it is, on the target machine)
            self.assertTrue(cider[0]["singleInstance"])

    def test_parse_desktop_file_rejects_nondisplay(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".desktop", delete=False) as fh:
            fh.write("[Desktop Entry]\nType=Application\nNoDisplay=true\nExec=x\n")
            path = Path(fh.name)
        try:
            self.assertIsNone(self.sst._parse_desktop_file(path))
        finally:
            path.unlink()

    def test_parse_desktop_file_reads_wmclass(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".desktop", delete=False) as fh:
            fh.write("[Desktop Entry]\nType=Application\nName=Thing\n"
                     "Exec=thing-bin\nStartupWMClass=com.thing.App\n")
            path = Path(fh.name)
        try:
            entry = self.sst._parse_desktop_file(path)
            self.assertIsNotNone(entry)
        finally:
            path.unlink()
        # wmClass resolution happens in app_catalogue; verify the source value
        self.assertEqual(entry.get("StartupWMClass"), "com.thing.App")
