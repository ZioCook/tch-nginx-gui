from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'decompressed/gui_file'


class TestStatsAndSwitchView(unittest.TestCase):
    def test_006_xdsl_stats_no_orphan_end(self):
        xdsl_path = ROOT / 'www/info-cards/006_xdsl_stats.lp'
        self.assertTrue(xdsl_path.exists())
        content = xdsl_path.read_text(encoding='utf-8', errors='ignore')
        self.assertFalse(content.strip().endswith('end'))
        self.assertIn('new modgui.createAjaxUpdateCard', content)

    def test_shared_script_switch_view_toggle(self):
        script_path = ROOT / 'www/docroot/js/shared-script.js'
        self.assertTrue(script_path.exists())
        content = script_path.read_text(encoding='utf-8', errors='ignore')
        self.assertIn('activeView', content)
        self.assertIn('targetPage = (activeView == "stats") ? "cards.lp" : "stats.lp"', content)


if __name__ == '__main__':
    unittest.main()
