#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "render-xray-config.py"
SPEC = importlib.util.spec_from_file_location("render_xray_config", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RenderXrayConfigTests(unittest.TestCase):
    def test_passwall_simplified_vmess_is_retargeted(self):
        source = {
            "policy": {"levels": {"0": {"handshake": 4}}},
            "inbounds": [{"protocol": "dokodemo-door", "port": 1041}],
            "outbounds": [{"protocol": "vmess", "tag": "node", "settings": {"address": "auto.example", "port": 443, "id": "secret"}, "streamSettings": {"network": "ws", "security": "tls", "tlsSettings": {"serverName": "origin.example"}, "sockopt": {"mark": 255, "domainStrategy": "UseIP"}}}, {"protocol": "freedom", "tag": "direct"}],
        }
        config, summary = MODULE.build_config(source, "104.17.1.2")
        outbound = config["outbounds"][0]
        self.assertEqual(outbound["settings"]["address"], "104.17.1.2")
        self.assertEqual(outbound["settings"]["id"], "secret")
        self.assertNotIn("mark", outbound["streamSettings"]["sockopt"])
        self.assertEqual(config["inbounds"][0]["protocol"], "socks")
        self.assertEqual(config["routing"]["rules"][0]["outboundTag"], "node")
        self.assertEqual(summary["server_name"], "origin.example")

    def test_standard_vnext_is_supported(self):
        source = {"outbounds": [{"protocol": "vless", "tag": "vless-node", "settings": {"vnext": [{"address": "auto.example", "port": 443, "users": [{"id": "secret"}]}]}}]}
        config, _ = MODULE.build_config(source, "172.67.1.4")
        self.assertEqual(config["outbounds"][0]["settings"]["vnext"][0]["address"], "172.67.1.4")

    def test_invalid_candidate_is_rejected(self):
        with self.assertRaises(ValueError): MODULE.build_config({"outbounds": []}, "not-an-ip")

    def test_direct_only_config_is_rejected(self):
        with self.assertRaises(ValueError): MODULE.build_config({"outbounds": [{"protocol": "freedom", "tag": "direct"}]}, "104.17.1.2")


if __name__ == "__main__":
    unittest.main()
