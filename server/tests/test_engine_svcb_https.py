"""
Unit & Integration Tests for FocusDNS RFC 9460 SVCB and HTTPS Resource Records Subsystem
========================================================================================
Validates:
  1. RFC 9460 SvcParam key-value wire format serialization and deserialization
  2. Presentation text parsing and formatting for master zone files
  3. Strict ascending numerical SvcParamKey wire ordering enforcement
  4. AliasMode (priority 0) and ServiceMode (priority > 0) behaviors
  5. ECH (Encrypted Client Hello) base64 parameter encoding/decoding
  6. Service binding resolution with ALPN negotiation and AliasMode chaining
"""

import unittest
from server.engine.svcb_https import (
    TYPE_SVCB,
    TYPE_HTTPS,
    SvcParamKey,
    SvcParam,
    SVCBRecord,
    HTTPSRecord,
    SVCBResolver,
)


class TestSvcParam(unittest.TestCase):
    """Tests wire and presentation codecs for individual SvcParam types."""

    def test_alpn_param_wire_codec(self):
        param = SvcParam(SvcParamKey.ALPN, value=["h3", "h2"])
        wire = param.to_wire()
        # [key: 2][len: 2][val: \x02h3\x02h2 = 6] -> 10 bytes
        self.assertEqual(len(wire), 10)
        self.assertEqual(param.key, 1)
        self.assertEqual(param.key_name, "alpn")

        # Decode
        dec = SvcParam(key=1, raw_value=param.raw_value)
        self.assertEqual(dec.value, ["h3", "h2"])

    def test_port_param_wire_codec(self):
        param = SvcParam(SvcParamKey.PORT, value=8443)
        self.assertEqual(param.to_wire(), b"\x00\x03\x00\x02\x20\xfb")
        dec = SvcParam(key=3, raw_value=param.raw_value)
        self.assertEqual(dec.value, 8443)

    def test_no_default_alpn_wire_codec(self):
        param = SvcParam(SvcParamKey.NO_DEFAULT_ALPN, value=True)
        # Empty length
        self.assertEqual(param.to_wire(), b"\x00\x02\x00\x00")
        dec = SvcParam(key=2, raw_value=b"")
        self.assertTrue(dec.value)

    def test_ipv4hint_param_wire_codec(self):
        param = SvcParam(SvcParamKey.IPV4HINT, value=["192.0.2.1", "198.51.100.2"])
        self.assertEqual(len(param.raw_value), 8)
        dec = SvcParam(key=4, raw_value=param.raw_value)
        self.assertEqual(dec.value, ["192.0.2.1", "198.51.100.2"])

    def test_ipv6hint_param_wire_codec(self):
        param = SvcParam(SvcParamKey.IPV6HINT, value=["2001:db8::1"])
        self.assertEqual(len(param.raw_value), 16)
        dec = SvcParam(key=6, raw_value=param.raw_value)
        self.assertEqual(dec.value, ["2001:db8::1"])

    def test_dohpath_param_wire_codec(self):
        param = SvcParam(SvcParamKey.DOHPATH, value="/dns-query{?dns}")
        self.assertEqual(param.key_name, "dohpath")
        dec = SvcParam(key=7, raw_value=param.raw_value)
        self.assertEqual(dec.value, "/dns-query{?dns}")

    def test_mandatory_param_wire_codec(self):
        param = SvcParam(SvcParamKey.MANDATORY, value=[SvcParamKey.PORT, SvcParamKey.ALPN])
        # Sorted keys: [1, 3] -> 4 bytes
        dec = SvcParam(key=0, raw_value=param.raw_value)
        self.assertEqual(dec.value, [1, 3])

    def test_ech_param_wire_codec(self):
        raw_ech = b"\xfe\x0d\x00\x1ahello_ech_config"
        import base64
        b64_ech = base64.b64encode(raw_ech).decode("ascii")
        param = SvcParam(SvcParamKey.ECH, value=b64_ech)
        dec = SvcParam(key=5, raw_value=param.raw_value)
        self.assertEqual(dec.value, b64_ech)


class TestSVCBRecord(unittest.TestCase):
    """Tests SVCB and HTTPS record wire and presentation serialization."""

    def test_presentation_format_parse_and_format(self):
        text = '1 . alpn="h3,h2" port=443 ipv4hint=1.2.3.4'
        rec = SVCBRecord.parse_presentation(text)
        self.assertEqual(rec.priority, 1)
        self.assertEqual(rec.target_name, ".")
        self.assertFalse(rec.is_alias_mode)
        self.assertTrue(rec.is_service_mode)

        self.assertEqual(rec.get_param("alpn").value, ["h3", "h2"])
        self.assertEqual(rec.get_param("port").value, 443)
        self.assertEqual(rec.get_param("ipv4hint").value, ["1.2.3.4"])

        pres = rec.to_presentation()
        self.assertIn('alpn="h3,h2"', pres)
        self.assertIn("port=443", pres)
        self.assertIn("ipv4hint=1.2.3.4", pres)

    def test_alias_mode_record(self):
        rec = SVCBRecord(priority=0, target_name="target.example.net")
        self.assertTrue(rec.is_alias_mode)
        self.assertFalse(rec.is_service_mode)

        # Alias mode must not contain SvcParams
        with self.assertRaises(ValueError):
            rec.set_param(SvcParam(SvcParamKey.PORT, 443))

        wire = rec.to_wire()
        dec = SVCBRecord.from_wire(wire)
        self.assertEqual(dec.priority, 0)
        self.assertEqual(dec.target_name, "target.example.net.")
        self.assertTrue(dec.is_alias_mode)

    def test_wire_roundtrip(self):
        rec = HTTPSRecord(
            priority=1,
            target_name="svc.example.com",
            params=[
                SvcParam(SvcParamKey.PORT, 8443),
                SvcParam(SvcParamKey.ALPN, ["h3", "h2"]),
                SvcParam(SvcParamKey.IPV4HINT, ["198.51.100.10"]),
                SvcParam(SvcParamKey.DOHPATH, "/dns-query"),
            ],
        )
        self.assertTrue(rec.is_https)

        wire = rec.to_wire()
        dec = HTTPSRecord.from_wire(wire, is_https=True)
        self.assertEqual(dec.priority, 1)
        self.assertEqual(dec.target_name, "svc.example.com.")
        self.assertEqual(dec.get_param(SvcParamKey.PORT).value, 8443)
        self.assertEqual(dec.get_param(SvcParamKey.ALPN).value, ["h3", "h2"])
        self.assertEqual(dec.get_param(SvcParamKey.IPV4HINT).value, ["198.51.100.10"])
        self.assertEqual(dec.get_param(SvcParamKey.DOHPATH).value, "/dns-query")

    def test_strict_ascending_key_order_enforcement(self):
        # Construct out-of-order raw wire data: key 3 followed by key 1
        raw = bytearray()
        raw.extend(b"\x00\x01")  # priority 1
        raw.extend(b"\x00")      # target '.'
        # Param 1: key 3 (port)
        raw.extend(b"\x00\x03\x00\x02\x01\xbb")
        # Param 2: key 1 (alpn) - OUT OF ORDER!
        raw.extend(b"\x00\x01\x00\x03\x02h2")

        with self.assertRaises(ValueError) as ctx:
            SVCBRecord.from_wire(bytes(raw))
        self.assertIn("strictly ascending numerical order", str(ctx.exception))


class TestSVCBResolver(unittest.TestCase):
    """Tests resolution, capability negotiation, and AliasMode following."""

    def setUp(self):
        self.resolver = SVCBResolver()

    def test_service_mode_resolution(self):
        rec1 = HTTPSRecord(priority=1, target_name=".", params=[
            SvcParam(SvcParamKey.ALPN, ["h2"]),
            SvcParam(SvcParamKey.PORT, 443),
            SvcParam(SvcParamKey.IPV4HINT, ["1.1.1.1"]),
        ])
        rec2 = HTTPSRecord(priority=2, target_name=".", params=[
            SvcParam(SvcParamKey.ALPN, ["h3"]),
            SvcParam(SvcParamKey.PORT, 8443),
            SvcParam(SvcParamKey.IPV4HINT, ["2.2.2.2"]),
        ])
        self.resolver.add_record("example.com", rec1)
        self.resolver.add_record("example.com", rec2)

        # Client requesting h3 will get rec2
        res = self.resolver.resolve("example.com", supported_alpns=["h3"])
        self.assertTrue(res["found"])
        self.assertEqual(res["selected_record"]["priority"], 2)

        # Check address synthesis
        hints_a = self.resolver.synthesize_a_records(rec2)
        self.assertEqual(hints_a, ["2.2.2.2"])

    def test_alias_mode_following(self):
        # example.com -> alias to cdn.example.net
        alias_rec = HTTPSRecord(priority=0, target_name="cdn.example.net")
        cdn_rec = HTTPSRecord(priority=1, target_name=".", params=[
            SvcParam(SvcParamKey.ALPN, ["h3"]),
            SvcParam(SvcParamKey.PORT, 443),
        ])
        self.resolver.add_record("example.com", alias_rec)
        self.resolver.add_record("cdn.example.net", cdn_rec)

        res = self.resolver.resolve("example.com")
        self.assertTrue(res["found"])
        self.assertEqual(res["target"], "cdn.example.net")
        self.assertEqual(res["alias_chain"], ["example.com", "cdn.example.net"])
        self.assertEqual(res["selected_record"]["priority"], 1)

    def test_cyclic_alias_mode_detection(self):
        # a -> b -> a
        self.resolver.add_record("a.com", HTTPSRecord(priority=0, target_name="b.com"))
        self.resolver.add_record("b.com", HTTPSRecord(priority=0, target_name="a.com"))

        res = self.resolver.resolve("a.com")
        self.assertIn("error", res)
        self.assertIn("loop detected", res["error"])


if __name__ == "__main__":
    unittest.main()
