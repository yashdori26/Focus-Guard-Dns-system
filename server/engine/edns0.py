"""
FocusDNS Engine - EDNS0 Advanced Options Subsystem
Standards:
- RFC 6891: Extension Mechanisms for DNS (EDNS(0)) & OPT Pseudo-RR
- RFC 7871: Client Subnet in DNS Queries (ECS) with Privacy Anonymization
- RFC 7873: Domain Name System (DNS) Cookies with Cryptographic HMAC-SHA256
- RFC 8914: Extended DNS Errors (EDE) Detailed Diagnostics
"""

import hmac
import hashlib
import ipaddress
import os
import struct
import time
from typing import Dict, List, Optional, Tuple, Any

from dnslib import DNSRecord, RR, QTYPE, RCODE

# Standard EDNS0 Option Codes (IANA Registry)
OPT_CODE_LLQ = 1
OPT_CODE_UL = 2
OPT_CODE_NSID = 3
OPT_CODE_DAU = 5
OPT_CODE_DHU = 6
OPT_CODE_N3U = 7
OPT_CODE_ECS = 8             # RFC 7871 Client Subnet
OPT_CODE_EXPIRE = 9
OPT_CODE_COOKIE = 10         # RFC 7873 DNS Cookie
OPT_CODE_TCP_KEEPALIVE = 11
OPT_CODE_PADDING = 12
OPT_CODE_CHAIN = 13
OPT_CODE_KEY_TAG = 14
OPT_CODE_EDE = 15            # RFC 8914 Extended DNS Errors

# RFC 8914 Extended DNS Error (EDE) Codes
EDE_OTHER = 0
EDE_UNSUPPORTED_DNSKEY_ALG = 1
EDE_UNSUPPORTED_DS_DIGEST = 2
EDE_STALE_ANSWER = 3         # RFC 8767 Stale Answer Served
EDE_FORGED_ANSWER = 4
EDE_DNSSEC_INDETERMINATE = 5
EDE_DNSSEC_BOGUS = 6         # DNSSEC Cryptographic Forgery Detected
EDE_SIGNATURE_EXPIRED = 7
EDE_SIGNATURE_NOT_YET_VALID = 8
EDE_DNSKEY_MISSING = 9
EDE_RRSIGS_MISSING = 10
EDE_NO_ZONE_KEY_BIT = 11
EDE_NSEC_MISSING = 12
EDE_CACHED_ERROR = 13
EDE_NOT_READY = 14
EDE_BLOCKED = 15             # Universal Denylist / Threat Feed
EDE_CENSORED = 16
EDE_FILTERED = 17            # Deep Focus / Category Filtering
EDE_PROHIBITED = 18
EDE_STALE_NXDOMAIN = 19
EDE_NOT_AUTHORITATIVE = 20
EDE_NOT_SUPPORTED = 21
EDE_NO_REACHABLE_AUTHORITY = 22
EDE_NETWORK_ERROR = 23
EDE_INVALID_DATA = 24

EDE_DESCRIPTIONS = {
    EDE_OTHER: "Other Error",
    EDE_UNSUPPORTED_DNSKEY_ALG: "Unsupported DNSKEY Algorithm",
    EDE_UNSUPPORTED_DS_DIGEST: "Unsupported DS Digest Type",
    EDE_STALE_ANSWER: "Stale Answer (RFC 8767)",
    EDE_FORGED_ANSWER: "Forged Answer",
    EDE_DNSSEC_INDETERMINATE: "DNSSEC Indeterminate",
    EDE_DNSSEC_BOGUS: "DNSSEC Bogus (MITM Detected)",
    EDE_SIGNATURE_EXPIRED: "Signature Expired",
    EDE_SIGNATURE_NOT_YET_VALID: "Signature Not Yet Valid",
    EDE_DNSKEY_MISSING: "DNSKEY Missing",
    EDE_RRSIGS_MISSING: "RRSIGs Missing",
    EDE_NO_ZONE_KEY_BIT: "No Zone Key Bit Set",
    EDE_NSEC_MISSING: "NSEC Missing",
    EDE_CACHED_ERROR: "Cached Error",
    EDE_NOT_READY: "Not Ready",
    EDE_BLOCKED: "Blocked by Administrator Policy",
    EDE_CENSORED: "Censored",
    EDE_FILTERED: "Filtered by Deep Focus Category",
    EDE_PROHIBITED: "Prohibited",
    EDE_STALE_NXDOMAIN: "Stale NXDOMAIN Answer",
    EDE_NOT_AUTHORITATIVE: "Not Authoritative",
    EDE_NOT_SUPPORTED: "Not Supported",
    EDE_NO_REACHABLE_AUTHORITY: "No Reachable Authority",
    EDE_NETWORK_ERROR: "Network Error",
    EDE_INVALID_DATA: "Invalid Data",
}

# Standard Recommended UDP Buffer Size (DNS Flag Day standard)
DEFAULT_EDNS_UDP_PAYLOAD_SIZE = 1232
MAX_EDNS_UDP_PAYLOAD_SIZE = 4096


class EDNSOption:
    """Represents a single Type-Length-Value (TLV) EDNS option."""

    __slots__ = ("code", "data")

    def __init__(self, code: int, data: bytes):
        self.code = code
        self.data = data

    def serialize(self) -> bytes:
        return struct.pack("!HH", self.code, len(self.data)) + self.data

    @classmethod
    def parse(cls, raw: bytes) -> Tuple["EDNSOption", bytes]:
        if len(raw) < 4:
            raise ValueError("Insufficient data for EDNS option header")
        code, length = struct.unpack("!HH", raw[:4])
        if len(raw) < 4 + length:
            raise ValueError(f"EDNS option length {length} exceeds buffer {len(raw) - 4}")
        data = raw[4:4 + length]
        return cls(code, data), raw[4 + length:]

    def __repr__(self) -> str:
        return f"<EDNSOption code={self.code} len={len(self.data)}>"


class EDNSClientSubnet:
    """
    RFC 7871 EDNS Client Subnet (ECS) Option.
    Option Code: 8.
    Format:
    - Family (uint16): 1 for IPv4, 2 for IPv6
    - Source Netmask (uint8)
    - Scope Netmask (uint8)
    - Address Prefix (variable length)
    """

    FAMILY_IPV4 = 1
    FAMILY_IPV6 = 2

    def __init__(
        self,
        family: int,
        source_netmask: int,
        scope_netmask: int,
        address: str,
    ):
        self.family = family
        self.source_netmask = source_netmask
        self.scope_netmask = scope_netmask
        self.address = address

    def serialize(self) -> bytes:
        ip_obj = ipaddress.ip_address(self.address)
        raw_ip = ip_obj.packed

        # Number of bytes required to store prefix bits: ceil(source_netmask / 8)
        prefix_bytes_len = (self.source_netmask + 7) // 8
        prefix_bytes = raw_ip[:prefix_bytes_len]

        hdr = struct.pack("!HBB", self.family, self.source_netmask, self.scope_netmask)
        return hdr + prefix_bytes

    @classmethod
    def parse(cls, data: bytes) -> "EDNSClientSubnet":
        if len(data) < 4:
            raise ValueError("Malformed ECS option: length < 4")
        family, source_netmask, scope_netmask = struct.unpack("!HBB", data[:4])
        prefix_bytes = data[4:]

        if family == cls.FAMILY_IPV4:
            expected_full_len = 4
        elif family == cls.FAMILY_IPV6:
            expected_full_len = 16
        else:
            raise ValueError(f"Unsupported ECS address family: {family}")

        # Pad with zeros to reconstitute full address
        padded = prefix_bytes + b"\x00" * (expected_full_len - len(prefix_bytes))
        ip_str = str(ipaddress.ip_address(padded[:expected_full_len]))

        return cls(family, source_netmask, scope_netmask, ip_str)

    def anonymize(self, ipv4_mask: int = 24, ipv6_mask: int = 56) -> "EDNSClientSubnet":
        """
        Anonymizes client IP by zeroing out host identifier bits for privacy.
        IPv4 is masked to /24 (256-address block), IPv6 to /56.
        """
        ip_obj = ipaddress.ip_address(self.address)
        if self.family == self.FAMILY_IPV4:
            target_mask = min(self.source_netmask, ipv4_mask)
            network = ipaddress.IPv4Network(f"{self.address}/{target_mask}", strict=False)
            return EDNSClientSubnet(self.family, target_mask, self.scope_netmask, str(network.network_address))
        else:
            target_mask = min(self.source_netmask, ipv6_mask)
            network = ipaddress.IPv6Network(f"{self.address}/{target_mask}", strict=False)
            return EDNSClientSubnet(self.family, target_mask, self.scope_netmask, str(network.network_address))

    def __repr__(self) -> str:
        return f"<EDNSClientSubnet ip={self.address}/{self.source_netmask} scope={self.scope_netmask}>"


class DNSCookie:
    """
    RFC 7873 DNS Cookies Engine.
    Option Code: 10.
    Format:
    - Client Cookie (8 octets, mandatory)
    - Server Cookie (8 to 32 octets, optional in queries, mandatory in replies)
    Defends against spoofed off-path reflection / amplification attacks.
    """

    def __init__(self, client_cookie: bytes, server_cookie: Optional[bytes] = None):
        if len(client_cookie) != 8:
            raise ValueError("Client cookie must be exactly 8 bytes")
        if server_cookie is not None and not (8 <= len(server_cookie) <= 32):
            raise ValueError("Server cookie must be between 8 and 32 bytes")
        self.client_cookie = client_cookie
        self.server_cookie = server_cookie

    def serialize(self) -> bytes:
        if self.server_cookie:
            return self.client_cookie + self.server_cookie
        return self.client_cookie

    @classmethod
    def parse(cls, data: bytes) -> "DNSCookie":
        if len(data) < 8:
            raise ValueError("Cookie length must be at least 8 bytes")
        client_cookie = data[:8]
        server_cookie = data[8:] if len(data) > 8 else None
        return cls(client_cookie, server_cookie)

    @staticmethod
    def generate_client_cookie() -> bytes:
        """Generates random 8-octet cryptographically secure client cookie."""
        return os.urandom(8)

    @staticmethod
    def generate_server_cookie(
        client_ip: str,
        client_cookie: bytes,
        secret_key: bytes,
        timestamp: Optional[int] = None,
    ) -> bytes:
        """
        Generates RFC 7873 / RFC 9018 compliant Server Cookie.
        Format: Version (1B: 0x01) + Reserved (3B) + Timestamp (4B) + HMAC-SHA256 (8B) = 16 bytes.
        """
        ts = int(time.time()) if timestamp is None else timestamp
        version_reserved_ts = struct.pack("!B3sI", 1, b"\x00\x00\x00", ts)

        ip_raw = ipaddress.ip_address(client_ip).packed
        data_to_hash = client_cookie + version_reserved_ts + ip_raw

        h = hmac.new(secret_key, data_to_hash, hashlib.sha256).digest()
        cookie_hash = h[:8]  # First 64 bits of HMAC

        return version_reserved_ts + cookie_hash

    @staticmethod
    def verify_server_cookie(
        server_cookie: bytes,
        client_ip: str,
        client_cookie: bytes,
        secret_key: bytes,
        max_age_seconds: int = 3600,
    ) -> bool:
        """Validates a server cookie against client IP, timestamp window, and cryptographic HMAC."""
        if len(server_cookie) != 16:
            return False

        version = server_cookie[0]
        if version != 1:
            return False

        ts = struct.unpack("!I", server_cookie[4:8])[0]
        now = int(time.time())
        # Check timestamp window (+/- max_age_seconds)
        if abs(now - ts) > max_age_seconds:
            return False

        expected_cookie = DNSCookie.generate_server_cookie(client_ip, client_cookie, secret_key, timestamp=ts)
        return hmac.compare_digest(server_cookie, expected_cookie)

    def __repr__(self) -> str:
        s_hex = self.server_cookie.hex() if self.server_cookie else "None"
        return f"<DNSCookie client={self.client_cookie.hex()} server={s_hex}>"


class ExtendedDNSError:
    """
    RFC 8914 Extended DNS Error (EDE).
    Option Code: 15.
    Format:
    - INFO-CODE: 16-bit uint
    - EXTRA-TEXT: Optional UTF-8 error string
    """

    def __init__(self, info_code: int, extra_text: str = ""):
        self.info_code = info_code
        self.extra_text = extra_text

    def serialize(self) -> bytes:
        text_bytes = self.extra_text.encode("utf-8") if self.extra_text else b""
        return struct.pack("!H", self.info_code) + text_bytes

    @classmethod
    def parse(cls, data: bytes) -> "ExtendedDNSError":
        if len(data) < 2:
            raise ValueError("EDE option data must be at least 2 bytes")
        info_code = struct.unpack("!H", data[:2])[0]
        extra_text = data[2:].decode("utf-8", errors="replace") if len(data) > 2 else ""
        return cls(info_code, extra_text)

    @property
    def description(self) -> str:
        return EDE_DESCRIPTIONS.get(self.info_code, f"Unknown Error ({self.info_code})")

    def __repr__(self) -> str:
        txt = f" '{self.extra_text}'" if self.extra_text else ""
        return f"<ExtendedDNSError code={self.info_code} ({self.description}){txt}>"


class EDNSMessage:
    """
    High-level EDNS(0) OPT Resource Record manager.
    Parses and builds RFC 6891 OPT records and provides clean getters/setters
    for ECS, Cookies, and Extended DNS Errors.
    """

    def __init__(
        self,
        udp_payload_size: int = DEFAULT_EDNS_UDP_PAYLOAD_SIZE,
        ext_rcode: int = 0,
        version: int = 0,
        dnssec_ok: bool = False,
        options: Optional[List[EDNSOption]] = None,
    ):
        self.udp_payload_size = udp_payload_size
        self.ext_rcode = ext_rcode
        self.version = version
        self.dnssec_ok = dnssec_ok
        self.options: List[EDNSOption] = options or []

    def add_option(self, option: EDNSOption):
        # Remove existing option with same code if duplicate
        self.options = [opt for opt in self.options if opt.code != option.code]
        self.options.append(option)

    def get_option(self, code: int) -> Optional[EDNSOption]:
        for opt in self.options:
            if opt.code == code:
                return opt
        return None

    def remove_option(self, code: int):
        self.options = [opt for opt in self.options if opt.code != code]

    # --- Typed Getters & Setters ---

    def set_ecs(self, ecs: EDNSClientSubnet):
        """Attaches an EDNS Client Subnet option (RFC 7871)."""
        self.add_option(EDNSOption(OPT_CODE_ECS, ecs.serialize()))

    def get_ecs(self) -> Optional[EDNSClientSubnet]:
        opt = self.get_option(OPT_CODE_ECS)
        if opt:
            try:
                return EDNSClientSubnet.parse(opt.data)
            except Exception:
                return None
        return None

    def set_cookie(self, cookie: DNSCookie):
        """Attaches a DNS Cookie option (RFC 7873)."""
        self.add_option(EDNSOption(OPT_CODE_COOKIE, cookie.serialize()))

    def get_cookie(self) -> Optional[DNSCookie]:
        opt = self.get_option(OPT_CODE_COOKIE)
        if opt:
            try:
                return DNSCookie.parse(opt.data)
            except Exception:
                return None
        return None

    def set_ede(self, ede: ExtendedDNSError):
        """Attaches an Extended DNS Error option (RFC 8914)."""
        self.add_option(EDNSOption(OPT_CODE_EDE, ede.serialize()))

    def get_ede(self) -> Optional[ExtendedDNSError]:
        opt = self.get_option(OPT_CODE_EDE)
        if opt:
            try:
                return ExtendedDNSError.parse(opt.data)
            except Exception:
                return None
        return None

    def serialize_rdata(self) -> bytes:
        """Serializes all concatenated TLV options into raw OPT RDATA bytes."""
        out = bytearray()
        for opt in self.options:
            out.extend(opt.serialize())
        return bytes(out)

    @classmethod
    def from_dnslib_record(cls, req: DNSRecord) -> Optional["EDNSMessage"]:
        """Extracts and parses EDNS(0) OPT record from an existing dnslib.DNSRecord."""
        for ar in getattr(req, "ar", []):
            if ar.rtype == 41:  # OPT record
                # rclass = udp_payload_size
                udp_size = ar.rclass
                # ttl holds ext_rcode (byte 3), version (byte 2), and flags (bytes 0-1)
                ttl_val = ar.ttl
                ext_rcode = (ttl_val >> 24) & 0xFF
                version = (ttl_val >> 16) & 0xFF
                flags = ttl_val & 0xFFFF
                dnssec_ok = bool(flags & 0x8000)

                # Parse RDATA TLVs
                options: List[EDNSOption] = []
                rdata = getattr(ar, "rdata", None)
                if isinstance(rdata, list):
                    for o in rdata:
                        options.append(EDNSOption(o.code, bytes(o.data)))
                elif hasattr(rdata, "data"):
                    buf = bytes(rdata.data)
                    while len(buf) >= 4:
                        try:
                            opt, buf = EDNSOption.parse(buf)
                            options.append(opt)
                        except Exception:
                            break

                return cls(
                    udp_payload_size=udp_size,
                    ext_rcode=ext_rcode,
                    version=version,
                    dnssec_ok=dnssec_ok,
                    options=options,
                )
        return None

    def attach_to_dnslib_record(self, reply: DNSRecord):
        """Appends the formatted OPT pseudo-RR to the Additional section of a DNSRecord."""
        from dnslib import EDNS0 as DnslibEDNS0, EDNSOption as DnslibEDNSOption
        dnslib_opts = [DnslibEDNSOption(opt.code, opt.data) for opt in self.options]
        flags = "do" if self.dnssec_ok else ""

        opt_rr = DnslibEDNS0(
            flags=flags,
            ext_rcode=self.ext_rcode,
            version=self.version,
            udp_len=self.udp_payload_size,
            opts=dnslib_opts,
        )
        reply.add_ar(opt_rr)


class EDNSProcessor:
    """
    Core engine service for processing incoming EDNS options,
    evaluating privacy policy (ECS anonymization / stripping),
    verifying DNS Cookies, and attaching Extended DNS Errors.
    """

    def __init__(self, cookie_secret: Optional[bytes] = None):
        # Rotate or generate 256-bit server cookie key
        self.cookie_secret = cookie_secret or os.urandom(32)

    def process_incoming_query(
        self,
        req: DNSRecord,
        client_ip: str,
        strip_ecs: bool = True,
    ) -> Tuple[Optional[EDNSMessage], Dict[str, Any]]:
        """
        Inspects incoming query for EDNS0 options.
        Returns (EDNSMessage_to_echo_in_reply, telemetry_info).
        """
        edns = EDNSMessage.from_dnslib_record(req)
        telemetry = {
            "has_edns": edns is not None,
            "dnssec_ok": False,
            "ecs_client_subnet": None,
            "cookie_valid": None,
        }

        if not edns:
            return None, telemetry

        telemetry["dnssec_ok"] = edns.dnssec_ok

        # 1. Process RFC 7871 ECS
        ecs = edns.get_ecs()
        if ecs:
            if strip_ecs:
                edns.remove_option(OPT_CODE_ECS)
                telemetry["ecs_client_subnet"] = "STRIPPED"
            else:
                anonymized = ecs.anonymize()
                edns.set_ecs(anonymized)
                telemetry["ecs_client_subnet"] = f"{anonymized.address}/{anonymized.source_netmask}"

        # 2. Process RFC 7873 DNS Cookies
        cookie = edns.get_cookie()
        if cookie:
            server_cookie = DNSCookie.generate_server_cookie(client_ip, cookie.client_cookie, self.cookie_secret)
            is_valid = False
            if cookie.server_cookie:
                is_valid = DNSCookie.verify_server_cookie(
                    cookie.server_cookie, client_ip, cookie.client_cookie, self.cookie_secret
                )
            telemetry["cookie_valid"] = is_valid
            # Attach generated server cookie to response
            edns.set_cookie(DNSCookie(cookie.client_cookie, server_cookie))

        return edns, telemetry

    def attach_error_diagnostics(
        self,
        reply: DNSRecord,
        edns: Optional[EDNSMessage],
        ede_code: int,
        extra_text: str = "",
    ):
        """Attaches RFC 8914 Extended DNS Error code and text to a response."""
        if edns is None:
            edns = EDNSMessage(udp_payload_size=DEFAULT_EDNS_UDP_PAYLOAD_SIZE)
        edns.set_ede(ExtendedDNSError(ede_code, extra_text))
        edns.attach_to_dnslib_record(reply)


# Helper utility to strip ECS directly from a raw DNS wire packet
def strip_ecs_from_wire(query_bytes: bytes) -> bytes:
    """Parses raw wire DNS query, strips any ECS option (code 8), and repacks packet."""
    try:
        rec = DNSRecord.parse(query_bytes)
        edns = EDNSMessage.from_dnslib_record(rec)
        if edns and edns.get_ecs():
            edns.remove_option(OPT_CODE_ECS)
            # Reconstruct AR without old OPT
            rec.ar = [ar for ar in rec.ar if ar.rtype != 41]
            edns.attach_to_dnslib_record(rec)
            return bytes(rec.pack())
    except Exception:
        pass
    return query_bytes
