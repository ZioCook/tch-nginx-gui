"""Unit tests for MTU configuration in Internet routed connection snippets."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'decompressed/gui_file'


class WanMtuConfigTests(unittest.TestCase):
    def test_pppoe_mtu_configuration(self):
        content = (ROOT / 'www/snippets/internet-pppoe-routed.lp').read_text(encoding='utf-8')
        self.assertIn('uci_wan_mtu = "uci.network.interface.@wan.mtu"', content)
        self.assertIn('uci_wan_mtu = gOV(post_helper.getValidateNumberInRange(576, 9200))', content)
        self.assertIn('ui_helper.createInputText(T"MTU","uci_wan_mtu", content["uci_wan_mtu"], nil, helpmsg["uci_wan_mtu"])', content)

    def test_dhcp_mtu_configuration(self):
        content = (ROOT / 'www/snippets/internet-dhcp-routed.lp').read_text(encoding='utf-8')
        self.assertIn('uci_wan_mtu = "uci.network.interface.@wan.mtu"', content)
        self.assertIn('uci_wan_mtu = gOV(post_helper.getValidateNumberInRange(576, 9200))', content)
        self.assertIn('ui_helper.createInputText(T"MTU","uci_wan_mtu", content["uci_wan_mtu"], nil, helpmsg["uci_wan_mtu"])', content)

    def test_static_mtu_configuration(self):
        content = (ROOT / 'www/snippets/internet-static-routed.lp').read_text(encoding='utf-8')
        self.assertIn('uci_wan_mtu = "uci.network.interface.@wan.mtu"', content)
        self.assertIn('uci_wan_mtu = gOV(post_helper.getValidateNumberInRange(576, 9200))', content)
        self.assertIn('ui_helper.createInputText(T"MTU","uci_wan_mtu", content["uci_wan_mtu"], nil, helpmsg["uci_wan_mtu"])', content)

    def test_pppoa_mtu_configuration(self):
        content = (ROOT / 'www/snippets/internet-pppoa-routed.lp').read_text(encoding='utf-8')
        self.assertIn('uci_wan_mtu = "uci.network.interface.@wan.mtu"', content)
        self.assertIn('uci_wan_mtu = gOV(post_helper.getValidateNumberInRange(576, 9200))', content)
        self.assertIn('ui_helper.createInputText(T"MTU", "uci_wan_mtu", content["uci_wan_mtu"], nil, helpmsg["uci_wan_mtu"])', content)
