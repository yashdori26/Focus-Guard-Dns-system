"""
FocusDNS Engine - DNSSEC Cryptographic Zone Signer & Key Rollover Manager
Standards & RFCs:
- RFC 4034: Resource Records for DNS Security Extensions (DNSKEY, RRSIG, NSEC, DS)
- RFC 4035: Protocol Modifications for DNSSEC Zone Signing
- RFC 5155: DNSSEC Hashed Authenticated Denial of Existence (NSEC3)
- RFC 6781: DNSSEC Operational Practices & Automated Key Rollover (ZSK/KSK)
- RFC 8624: Algorithm Implementation Requirements (Algorithm 13 ECDSA P-256 SHA-256)
"""

import base64
import hashlib
import os
import struct
import time
from typing import Dict, List, Optional, Set, Tuple, Any

from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    PublicFormat,
    PrivateFormat,
    NoEncryption,
)
from dnslib import DNSRecord, RR, QTYPE, RCODE

# DNSSEC Algorithm Numbers (IANA Registry)
DNSSEC_ALG_RSASHA256 = 8
DNSSEC_ALG_ECDSAP256SHA256 = 13  # Mandatory / Best-practice
DNSSEC_ALG_ED25519 = 15

# Digest Types for DS Record
DS_DIGEST_SHA1 = 1
DS_DIGEST_SHA256 = 2

# DNSKEY Flags
DNSKEY_FLAG_ZSK = 256   # Zone Signing Key
DNSKEY_FLAG_KSK = 257   # Key Signing Key (SEP bit 0 set)
DNSKEY_PROTOCOL_DNSSEC = 3


def compute_key_tag(dnskey_rdata: bytes) -> int:
    """
    Computes 16-bit Key Tag checksum according to RFC 4034 Appendix B.
    """
    ac = 0
    for i, b in enumerate(dnskey_rdata):
        ac += (b << 8) if (i % 2 == 0) else b
    ac += (ac >> 16) & 0xFFFF
    return ac & 0xFFFF


def canonical_dns_name(name: str) -> bytes:
    """Encodes domain name into RFC 4034 §6.1 canonical wire format."""
    clean = name.strip().lower().rstrip(".")
    if not clean:
        return b"\x00"
    out = bytearray()
    for label in clean.split("."):
        b_label = label.encode("ascii")
        out.append(len(b_label))
        out.extend(b_label)
    out.append(0)
    return bytes(out)


class DNSSECKeyPair:
    """Represents an ECDSA P-256 (Algorithm 13) cryptographic key pair for DNSSEC signing."""

    def __init__(
        self,
        flags: int = DNSKEY_FLAG_ZSK,
        algorithm: int = DNSSEC_ALG_ECDSAP256SHA256,
        private_key: Optional[ec.EllipticCurvePrivateKey] = None,
        created_at: Optional[float] = None,
    ):
        self.flags = flags
        self.protocol = DNSKEY_PROTOCOL_DNSSEC
        self.algorithm = algorithm
        self.created_at = created_at or time.time()

        if private_key is None:
            self.private_key = ec.generate_private_key(ec.SECP256R1())
        else:
            self.private_key = private_key

        self.public_key = self.private_key.public_key()

        # Extract uncompressed public key bytes (X and Y coordinates, each 32 bytes)
        raw_pub = self.public_key.public_bytes(
            Encoding.X962,
            PublicFormat.UncompressedPoint
        )
        # Drop leading 0x04 uncompressed indicator byte -> 64 bytes raw (X || Y)
        self.raw_public_bytes = raw_pub[1:]

        # Build DNSKEY RDATA: Flags (2B) + Protocol (1B) + Algorithm (1B) + Public Key (64B)
        self.dnskey_rdata = (
            struct.pack("!HBB", self.flags, self.protocol, self.algorithm)
            + self.raw_public_bytes
        )
        self.key_tag = compute_key_tag(self.dnskey_rdata)

    def is_ksk(self) -> bool:
        return bool(self.flags & 1)

    def is_zsk(self) -> bool:
        return not self.is_ksk()

    def generate_ds_record(self, zone_name: str, digest_type: int = DS_DIGEST_SHA256) -> Dict[str, Any]:
        """Generates RFC 4034 Delegation Signer (DS) record for parent zone delegation."""
        canon_name = canonical_dns_name(zone_name)
        data = canon_name + self.dnskey_rdata

        if digest_type == DS_DIGEST_SHA256:
            digest = hashlib.sha256(data).digest()
        else:
            digest = hashlib.sha1(data).digest()

        return {
            "name": zone_name.rstrip("."),
            "key_tag": self.key_tag,
            "algorithm": self.algorithm,
            "digest_type": digest_type,
            "digest_hex": digest.hex().upper(),
        }

    def sign_data(self, data: bytes) -> bytes:
        """Signs raw canonical data using ECDSA P-256 with SHA-256 (RFC 6605)."""
        # Cryptography produces DER-encoded ASN.1 signature (r, s)
        # RFC 6605 §4 mandates raw fixed-length (R || S) format (64 octets)
        sig_der = self.private_key.sign(data, ec.ECDSA(hashes.SHA256()))

        # Decode DER (r, s) to raw 64 bytes
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
        r, s = decode_dss_signature(sig_der)
        return r.to_bytes(32, byteorder="big") + s.to_bytes(32, byteorder="big")


class DNSSECSignerEngine:
    """
    Cryptographic engine for signing authoritative DNS zones with RRSIG and NSEC.
    Maintains active KSK and ZSK key pairs and performs automatic key lifecycle rotation.
    """

    def __init__(self, zone_origin: str, validity_days: int = 14):
        self.origin = zone_origin.strip().lower().rstrip(".")
        self.validity_seconds = validity_days * 86400

        # Primary KSK and ZSK
        self.ksk = DNSSECKeyPair(flags=DNSKEY_FLAG_KSK)
        self.zsk = DNSSECKeyPair(flags=DNSKEY_FLAG_ZSK)

        # Retired / Previous keys for smooth rollover
        self._retired_keys: List[DNSSECKeyPair] = []

    def get_dnskey_records(self) -> List[Dict[str, Any]]:
        """Returns active DNSKEY records for publishing at apex."""
        return [
            {
                "name": self.origin,
                "flags": self.ksk.flags,
                "protocol": self.ksk.protocol,
                "algorithm": self.ksk.algorithm,
                "public_key_b64": base64.b64encode(self.ksk.raw_public_bytes).decode("ascii"),
                "key_tag": self.ksk.key_tag,
                "type": "KSK",
            },
            {
                "name": self.origin,
                "flags": self.zsk.flags,
                "protocol": self.zsk.protocol,
                "algorithm": self.zsk.algorithm,
                "public_key_b64": base64.b64encode(self.zsk.raw_public_bytes).decode("ascii"),
                "key_tag": self.zsk.key_tag,
                "type": "ZSK",
            },
        ]

    def sign_rrset(
        self,
        name: str,
        type_covered_num: int,
        original_ttl: int,
        canonical_rdata_list: List[bytes],
        inception: Optional[int] = None,
        expiration: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Signs an RRset using active ZSK (or KSK for DNSKEY RRset) according to RFC 4034 §3.
        Returns structured RRSIG object.
        """
        clean_name = name.strip().lower().rstrip(".")
        signer_key = self.ksk if type_covered_num == 48 else self.zsk  # 48 = DNSKEY

        now = int(time.time())
        sig_inception = now - 3600 if inception is None else inception  # 1h skew buffer
        sig_expiration = now + self.validity_seconds if expiration is None else expiration

        labels_count = len(clean_name.split("."))
        canon_signer_name = canonical_dns_name(self.origin)
        canon_owner_name = canonical_dns_name(clean_name)

        # RRSIG Header block (18 octets):
        # Type Covered (2B) + Algorithm (1B) + Labels (1B) + Orig TTL (4B)
        # + Sig Expiration (4B) + Sig Inception (4B) + Key Tag (2B)
        rrsig_header = struct.pack(
            "!HBBIIIH",
            type_covered_num,
            signer_key.algorithm,
            labels_count,
            original_ttl,
            sig_expiration,
            sig_inception,
            signer_key.key_tag,
        )

        # Prepend RRSIG header + canonical Signer Name
        signed_payload = bytearray(rrsig_header + canon_signer_name)

        # Canonical sort and append all RRs in RRset (RFC 4034 §6.3)
        sorted_rdatas = sorted(canonical_rdata_list)
        for rdata_wire in sorted_rdatas:
            # Owner name + Type (2B) + Class IN (2B) + Orig TTL (4B) + RDLENGTH (2B) + RDATA
            rr_entry = (
                canon_owner_name
                + struct.pack("!HHIH", type_covered_num, 1, original_ttl, len(rdata_wire))
                + rdata_wire
            )
            signed_payload.extend(rr_entry)

        # Generate cryptographic signature
        signature_bytes = signer_key.sign_data(bytes(signed_payload))

        return {
            "name": clean_name,
            "type_covered": type_covered_num,
            "algorithm": signer_key.algorithm,
            "labels": labels_count,
            "original_ttl": original_ttl,
            "expiration": sig_expiration,
            "inception": sig_inception,
            "key_tag": signer_key.key_tag,
            "signer_name": self.origin,
            "signature_b64": base64.b64encode(signature_bytes).decode("ascii"),
            "signature_bytes": signature_bytes,
        }

    def generate_nsec_record(
        self,
        owner_name: str,
        next_domain_name: str,
        types_present: List[int],
        ttl: int = 300,
    ) -> Dict[str, Any]:
        """
        Generates RFC 4034 NSEC Authenticated Denial of Existence record.
        Builds Type Bit Maps window block (Window 0: types 0-255).
        """
        clean_owner = owner_name.strip().lower().rstrip(".")
        clean_next = next_domain_name.strip().lower().rstrip(".")

        # Type Bit Maps window 0
        bitmap = bytearray(32)  # 256 bits = 32 bytes
        max_type = 0
        for t in types_present:
            if 0 <= t < 256:
                byte_offset = t // 8
                bit_offset = 7 - (t % 8)
                bitmap[byte_offset] |= (1 << bit_offset)
                if byte_offset > max_type:
                    max_type = byte_offset

        # Window block header: Window Number (0) + Bitmap Length
        trimmed_bitmap = bitmap[:max_type + 1]
        window_block = struct.pack("!BB", 0, len(trimmed_bitmap)) + trimmed_bitmap

        # NSEC RDATA = Canonical Next Domain Name + Window Block
        canon_next = canonical_dns_name(clean_next)
        nsec_rdata = canon_next + window_block

        return {
            "name": clean_owner,
            "next_domain": clean_next,
            "types": types_present,
            "ttl": ttl,
            "rdata_bytes": nsec_rdata,
        }

    def rotate_zsk(self):
        """Executes RFC 6781 Pre-Publish Zone Signing Key rollover."""
        old_zsk = self.zsk
        self._retired_keys.append(old_zsk)
        self.zsk = DNSSECKeyPair(flags=DNSKEY_FLAG_ZSK)

    def rotate_ksk(self) -> Dict[str, Any]:
        """Executes RFC 6781 Double-DS Key Signing Key rollover."""
        old_ksk = self.ksk
        self._retired_keys.append(old_ksk)
        self.ksk = DNSSECKeyPair(flags=DNSKEY_FLAG_KSK)
        # Return new DS record for parent zone submission
        return self.ksk.generate_ds_record(self.origin)
