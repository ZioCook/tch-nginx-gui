from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'decompressed/gui_file'


class TestWiFiStandards(unittest.TestCase):
    def test_wifi_standards_options(self):
        modal_path = ROOT / 'www/docroot/modals/wireless-modal.lp'
        self.assertTrue(modal_path.exists(), f"File {modal_path} should exist")
        content = modal_path.read_text(encoding='utf-8', errors='ignore')

        # Check 2.4GHz standards contain 'n'
        self.assertIn('{ "n", T\'802.11n\'}', content)
        self.assertIn('{ "bg", T\'802.11b/g\'}', content)
        self.assertIn('{ "bgn", T\'802.11b/g/n\'}', content)

        # Check 5GHz standards contain 'an', 'ac', 'anac'
        self.assertIn('{ "an", T\'802.11a/n\'}', content)
        self.assertIn('{ "ac", T\'802.11ac\'}', content)
        self.assertIn('{ "anac", T\'802.11a/n/ac\'}', content)

        # Check cw mapping includes n and ac
        self.assertIn('["n"] = "channelwidth40"', content)
        self.assertIn('["ac"] = "channelwidth80"', content)

        # Check monitor classes for channel widths
        self.assertIn('monitor-bgn monitor-n monitor-an', content)
        self.assertIn('monitor-anac monitor-ac', content)

        # Check unified standard input select
        self.assertIn('ui_helper.createInputSelect(T"Standard", "standard", wifi_standard, content["standard"], stdattributes)', content)


if __name__ == '__main__':
    unittest.main()
