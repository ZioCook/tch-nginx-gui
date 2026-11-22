"""Regression checks for GUI links that cannot rely on stock firmware files."""

from pathlib import Path
import unittest


WWW = Path(__file__).resolve().parents[1] / "decompressed/gui_file/www"


class GuiAssetDependencies(unittest.TestCase):
    def test_standalone_pages_do_not_request_missing_stock_bundle(self):
        for page in ("parental-block.lp", "password-reset.lp"):
            text = (WWW / "docroot" / page).read_text()
            self.assertNotIn('src="/js/main-min.js"', text)
        reset = (WWW / "docroot/password-reset.lp").read_text()
        self.assertIn('src="/js/jquery.min.js"', reset)

    def test_optional_easymesh_tabs_check_modal_availability(self):
        tabs = (WWW / "snippets/tabs-easyMesh.lp").read_text()
        for modal in ("agent-list.lp", "wifi-devices-info.lp"):
            self.assertIn(f'modal_available("{modal}")', tabs)

    def test_wireless_client_form_targets_existing_modal(self):
        modal = WWW / "docroot/modals/wireless-client-modal.lp"
        self.assertIn('action="modals/wireless-client-modal.lp"', modal.read_text())

    def test_modal_json_configs_never_wrap_tostring_before_untaint(self):
        # web.taint __tostring returns literal "tainted string"; untaint() must run first
        offenders = [
            str(p.relative_to(WWW))
            for p in sorted(WWW.rglob("*.lp"))
            if "untaint(tostring(" in p.read_text(encoding="utf-8", errors="ignore")
        ]
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
