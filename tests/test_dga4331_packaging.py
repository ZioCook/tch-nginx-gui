"""Keep DGA4331 LED support separate from optional firmware modifications."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ROOT / "decompressed"
BUILD = (ROOT / "inizialize_gui.sh").read_text(encoding="utf-8", errors="ignore")
SPECIFIC = (PACKAGES / "gui_file/etc/modgui_scripts/02_specific.sh").read_text(encoding="utf-8", errors="ignore")
MODAL = (PACKAGES / "gui_file/www/docroot/modals/modgui-modal.lp").read_text(encoding="utf-8", errors="ignore")


class DGA4331Packaging(unittest.TestCase):
    def test_no_specific_app_is_built_or_installed(self):
        self.assertFalse(any(path.is_file() for path in
                             (PACKAGES / "upgrade-pack-specificDGA4331").rglob("*")))
        self.assertNotIn('"upgrade-pack-specificDGA4331"', BUILD)
        self.assertNotIn("install_specific DGA4331", SPECIFIC)
        install_case = SPECIFIC.split("# TODO: make all specifc package generic (mips/arm)", 1)[1]
        self.assertNotIn('"19."*)', install_case)
        self.assertIn('uci set modgui.app.specific_app="1" #no specific package for this firmware', SPECIFIC)
        self.assertIn('marketing_major < 19', MODAL)

    def test_led_support_remains_separate(self):
        self.assertTrue((PACKAGES / "ledfw_support-specificDGA4331/etc/ledfw/stateMachines.lua").is_file())
        self.assertIn('"ledfw_support-specificDGA4331"', BUILD)
        self.assertIn('ledfw_extract "DGA4331"', SPECIFIC)


if __name__ == "__main__":
    unittest.main()
