"""Tests for the parts of omarchy-gp that do not need a display or a VPN."""
import ipaddress
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import omarchy_gp as gp  # noqa: E402

CACHE = """\
Scope protocol=dns ifindex=7 ifname=wlan0 DNSSEC=no DNSOverTLS=no
example.org IN A 93.184.215.14

Scope protocol=dns ifindex=16 ifname=gpoc0 DNSSEC=no DNSOverTLS=no
www.example.com IN CNAME edge.cdn.example.net
edge.cdn.example.net IN CNAME a1.cdn.example.net
a1.cdn.example.net IN A 203.0.113.9
wiki.corp.example.com IN A 10.20.4.18
missing.example.com IN ANY NXDOMAIN
"""


class Formatting(unittest.TestCase):
    def test_bytes(self):
        self.assertEqual(gp.human_bytes(0), "0 B")
        self.assertEqual(gp.human_bytes(5300), "5 KB")
        self.assertEqual(gp.human_bytes(3_400_000), "3.4 MB")
        self.assertEqual(gp.human_bytes(173_000_000), "173 MB")
        self.assertEqual(gp.human_bytes(2_800_000_000), "2.8 GB")

    def test_time(self):
        self.assertEqual(gp.human_time(45), "45 s")
        self.assertEqual(gp.human_time(600), "10 min")
        self.assertEqual(gp.human_time(8040), "2 h 14 min")
        self.assertEqual(gp.long_time(59), "0 min")
        self.assertEqual(gp.short_time(5400), "1.5h")


class Routing(unittest.TestCase):
    def setUp(self):
        self.old = gp.IFACE
        gp.IFACE = "gpoc0"
        self.routes = sorted(
            [(ipaddress.ip_network("0.0.0.0/0"), "wlan0"), (ipaddress.ip_network("10.0.0.0/8"), "gpoc0"),
             (ipaddress.ip_network("10.201.0.0/24"), "docker0")],
            key=lambda r: r[0].prefixlen, reverse=True)

    def tearDown(self):
        gp.IFACE = self.old

    def test_internal_goes_through_vpn(self):
        self.assertTrue(gp.via_vpn("10.20.4.18", self.routes))

    def test_public_goes_direct(self):
        self.assertFalse(gp.via_vpn("142.250.74.110", self.routes))

    def test_more_specific_route_wins(self):
        self.assertFalse(gp.via_vpn("10.201.0.5", self.routes))

    def test_ipv6_and_garbage_are_direct(self):
        self.assertFalse(gp.via_vpn("2a00:1450::200e", self.routes))
        self.assertFalse(gp.via_vpn("not-an-ip", self.routes))


class Sockets(unittest.TestCase):
    def test_peer_forms(self):
        self.assertEqual(gp.PEER.match("142.250.74.110:443").group(1), "142.250.74.110")
        self.assertEqual(gp.PEER.match("[::ffff:10.20.4.18]:22").group(1), "10.20.4.18")
        self.assertEqual(gp.PEER.match("[2a00:1450::200e]:443").group(1), "2a00:1450::200e")
        self.assertIsNone(gp.PEER.match("*:*"))
        self.assertIsNone(gp.PEER.match("0.0.0.0:*"))


class DnsCache(unittest.TestCase):
    def test_names_and_cname_chain(self):
        names, via_vpn = gp.parse_dns_cache(CACHE, "gpoc0")
        self.assertEqual(names["203.0.113.9"], "www.example.com")
        self.assertEqual(names["10.20.4.18"], "wiki.corp.example.com")
        self.assertEqual(names["93.184.215.14"], "example.org")
        self.assertTrue(via_vpn)

    def test_scope_detection(self):
        self.assertFalse(gp.parse_dns_cache(CACHE, "gpd0")[1])
        self.assertEqual(gp.parse_dns_cache("", "gpoc0"), ({}, False))


if __name__ == "__main__":
    unittest.main()
