"""
FocusDNS AI Engine - Zero-Day SNI & TLS Threat Detector.

Performs zero-latency deep packet inspection on TLS 1.2 and TLS 1.3 ClientHello
records to extract Server Name Indication (SNI), detect domain fronting evasions,
brand impersonation in TLS extensions, and covert exfiltration channels.

Key Security Capabilities:
  1. Zero-Copy TLS ClientHello Parser:
     - Extracts SNI (extension 0x0000), ALPN (0x0010), supported versions (0x002b),
       and padding (0x0015) directly from raw byte streams with zero external dependencies.
  2. Domain Fronting & SNI Mismatch Defense:
     - Detects when the TLS handshake SNI diverges from the pre-resolved DNS query apex,
       flagging high-risk CDN fronting, C2 proxying, and firewall bypass attempts.
  3. TLS Brand Impersonation & Punycode Homograph Detection:
     - Scans SNI hostnames for deceptive brand hijacking, nested subdomains,
       and internationalized punycode ('xn--') obfuscations.
  4. TLS Covert Channel & Entropy Analysis:
     - Flags high-entropy SNI hostnames (DGA/tunneling over TLS) and abnormal
       extension padding (> 512 bytes) used for covert data staging.
  5. Inviolable Life Safety Exemption:
     - Hardcoded unconditional bypass for emergency services (911.gov, 112.gov)
       and OS infrastructure (push.apple.com, update.microsoft.com, play.googleapis.com).
"""

import math
import struct
import collections
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.brand_dictionary import BrandDictionary, PROTECTED_BRANDS, DECEPTIVE_KEYWORDS
from server.ai.zero_hour_phishing import LIFE_SAFETY_EXEMPTIONS, HIGH_ABUSE_TLDS


TLS_RECORD_HANDSHAKE = 0x16
TLS_HANDSHAKE_CLIENT_HELLO = 0x01
EXTENSION_SERVER_NAME = 0x0000
EXTENSION_ALPN = 0x0010
EXTENSION_PADDING = 0x0015
EXTENSION_SUPPORTED_VERSIONS = 0x002B
SNI_TYPE_HOST_NAME = 0x00


class ClientHelloInfo:
    """Parsed representation of a TLS ClientHello packet."""
    __slots__ = (
        "is_valid", "sni_hostname", "alpn_protocols", "cipher_suites",
        "extensions", "client_version", "session_id", "padding_length", "raw_length"
    )

    def __init__(
        self,
        is_valid: bool = False,
        sni_hostname: Optional[str] = None,
        alpn_protocols: Optional[List[str]] = None,
        cipher_suites: Optional[List[int]] = None,
        extensions: Optional[Dict[int, bytes]] = None,
        client_version: int = 0x0303,
        session_id: bytes = b"",
        padding_length: int = 0,
        raw_length: int = 0
    ):
        self.is_valid = is_valid
        self.sni_hostname = sni_hostname
        self.alpn_protocols = alpn_protocols or []
        self.cipher_suites = cipher_suites or []
        self.extensions = extensions or {}
        self.client_version = client_version
        self.session_id = session_id
        self.padding_length = padding_length
        self.raw_length = raw_length

    @property
    def has_sni(self) -> bool:
        return bool(self.sni_hostname)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_valid": self.is_valid,
            "sni_hostname": self.sni_hostname,
            "alpn_protocols": self.alpn_protocols,
            "cipher_suite_count": len(self.cipher_suites),
            "extension_types": list(self.extensions.keys()),
            "client_version": hex(self.client_version),
            "padding_length": self.padding_length,
            "raw_length": self.raw_length,
        }


class SniThreatVerdict:
    """Structured security evaluation of a TLS SNI handshake."""
    __slots__ = (
        "is_threat", "risk_score", "threat_type", "sni_hostname",
        "expected_dns_domain", "targeted_brand", "indicators",
        "explanation", "latency_us"
    )

    def __init__(
        self,
        is_threat: bool,
        risk_score: float,
        threat_type: str,
        sni_hostname: Optional[str],
        expected_dns_domain: Optional[str],
        targeted_brand: Optional[str],
        indicators: List[str],
        explanation: str,
        latency_us: float = 0.0
    ):
        self.is_threat = is_threat
        self.risk_score = round(min(100.0, max(0.0, risk_score)), 2)
        self.threat_type = threat_type
        self.sni_hostname = sni_hostname
        self.expected_dns_domain = expected_dns_domain
        self.targeted_brand = targeted_brand
        self.indicators = indicators
        self.explanation = explanation
        self.latency_us = round(latency_us, 2)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_threat": self.is_threat,
            "risk_score": self.risk_score,
            "threat_type": self.threat_type,
            "sni_hostname": self.sni_hostname,
            "expected_dns_domain": self.expected_dns_domain,
            "targeted_brand": self.targeted_brand,
            "indicators": self.indicators,
            "explanation": self.explanation,
            "latency_us": self.latency_us
        }


class SniThreatDetector:
    """
    On-device, zero-dependency TLS SNI inspection engine.
    Parses ClientHello frames in microsecond latency and correlates against DNS query intent.
    """

    def __init__(self, high_risk_threshold: float = 65.0):
        self.high_risk_threshold = high_risk_threshold

    @staticmethod
    def calculate_entropy(text: str) -> float:
        """Computes mathematical Shannon entropy for an SNI label: -sum(p * log2(p))."""
        if not text:
            return 0.0
        length = len(text)
        freq = collections.Counter(text)
        return -sum((count / length) * math.log2(count / length) for count in freq.values())

    @staticmethod
    def extract_apex_domain(domain: str) -> str:
        """Extracts the registered apex domain (e.g. 'sub.example.com' -> 'example.com')."""
        if not domain:
            return ""
        clean = domain.lower().strip().strip(".")
        parts = clean.split(".")
        if len(parts) <= 2:
            return clean

        second_level_tlds = {"co.uk", "com.au", "gov.uk", "org.uk", "ac.uk", "co.jp", "com.br", "gov.au"}
        candidate_2 = f"{parts[-2]}.{parts[-1]}"
        if candidate_2 in second_level_tlds and len(parts) >= 3:
            return f"{parts[-3]}.{candidate_2}"
        return f"{parts[-2]}.{parts[-1]}"

    def parse_client_hello(self, data: bytes) -> ClientHelloInfo:
        """
        Parses a raw TLS ClientHello byte frame without external dependencies.
        Returns a populated ClientHelloInfo object or an invalid instance if malformed.
        """
        if not data or len(data) < 44:
            return ClientHelloInfo(is_valid=False)

        try:
            offset = 0

            # 1. TLS Record Header (5 bytes)
            record_type, rec_ver_major, rec_ver_minor, rec_len = struct.unpack_from(">BBBH", data, offset)
            if record_type != TLS_RECORD_HANDSHAKE:
                return ClientHelloInfo(is_valid=False)

            offset += 5
            if len(data) < offset + rec_len:
                # Truncated record
                return ClientHelloInfo(is_valid=False)

            # 2. Handshake Header (4 bytes)
            hs_type = data[offset]
            if hs_type != TLS_HANDSHAKE_CLIENT_HELLO:
                return ClientHelloInfo(is_valid=False)

            hs_len = (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]
            offset += 4

            if len(data) < offset + hs_len:
                return ClientHelloInfo(is_valid=False)

            # 3. Client Version (2 bytes)
            client_version = struct.unpack_from(">H", data, offset)[0]
            offset += 2

            # 4. Random (32 bytes)
            offset += 32

            # 5. Session ID
            session_id_len = data[offset]
            offset += 1
            session_id = data[offset:offset + session_id_len]
            offset += session_id_len

            # 6. Cipher Suites
            cs_len = struct.unpack_from(">H", data, offset)[0]
            offset += 2
            cipher_suites = []
            for i in range(0, cs_len, 2):
                cipher_suites.append(struct.unpack_from(">H", data, offset + i)[0])
            offset += cs_len

            # 7. Compression Methods
            comp_len = data[offset]
            offset += 1 + comp_len

            # 8. Extensions
            extensions: Dict[int, bytes] = {}
            sni_hostname: Optional[str] = None
            alpn_protocols: List[str] = []
            padding_len = 0

            if offset + 2 <= len(data):
                ext_total_len = struct.unpack_from(">H", data, offset)[0]
                offset += 2
                ext_end = offset + ext_total_len

                while offset + 4 <= ext_end and offset + 4 <= len(data):
                    ext_type, ext_data_len = struct.unpack_from(">HH", data, offset)
                    offset += 4
                    ext_data = data[offset:offset + ext_data_len]
                    offset += ext_data_len
                    extensions[ext_type] = ext_data

                    # Extension 0x0000: Server Name Indication (SNI)
                    if ext_type == EXTENSION_SERVER_NAME and len(ext_data) >= 5:
                        sni_list_len = struct.unpack_from(">H", ext_data, 0)[0]
                        sni_offset = 2
                        while sni_offset + 3 <= len(ext_data):
                            name_type = ext_data[sni_offset]
                            name_len = struct.unpack_from(">H", ext_data, sni_offset + 1)[0]
                            sni_offset += 3
                            if name_type == SNI_TYPE_HOST_NAME and sni_offset + name_len <= len(ext_data):
                                raw_host = ext_data[sni_offset:sni_offset + name_len]
                                try:
                                    sni_hostname = raw_host.decode("ascii").lower()
                                except UnicodeDecodeError:
                                    sni_hostname = raw_host.decode("latin1", errors="replace").lower()
                                break
                            sni_offset += name_len

                    # Extension 0x0010: ALPN
                    elif ext_type == EXTENSION_ALPN and len(ext_data) >= 2:
                        alpn_list_len = struct.unpack_from(">H", ext_data, 0)[0]
                        a_offset = 2
                        while a_offset < len(ext_data):
                            proto_len = ext_data[a_offset]
                            a_offset += 1
                            if a_offset + proto_len <= len(ext_data):
                                proto_bytes = ext_data[a_offset:a_offset + proto_len]
                                alpn_protocols.append(proto_bytes.decode("ascii", errors="replace"))
                                a_offset += proto_len

                    # Extension 0x0015: Padding
                    elif ext_type == EXTENSION_PADDING:
                        padding_len = ext_data_len

            return ClientHelloInfo(
                is_valid=True,
                sni_hostname=sni_hostname,
                alpn_protocols=alpn_protocols,
                cipher_suites=cipher_suites,
                extensions=extensions,
                client_version=client_version,
                session_id=session_id,
                padding_length=padding_len,
                raw_length=len(data)
            )

        except Exception:
            return ClientHelloInfo(is_valid=False)

    def evaluate_threat(
        self,
        client_hello: ClientHelloInfo,
        expected_dns_domain: Optional[str] = None
    ) -> SniThreatVerdict:
        """
        Evaluates security posture of a TLS ClientHello against zero-day phishing,
        domain fronting, covert channels, and punycode obfuscation.
        """
        # Step 0: Malformed packet handling
        if not client_hello.is_valid:
            return SniThreatVerdict(
                is_threat=False,
                risk_score=10.0,
                threat_type="MALFORMED_NON_TLS",
                sni_hostname=None,
                expected_dns_domain=expected_dns_domain,
                targeted_brand=None,
                indicators=["malformed_record_or_truncated"],
                explanation="Non-TLS packet or truncated TLS ClientHello frame."
            )

        sni = client_hello.sni_hostname
        indicators: List[str] = []
        score = 0.0

        # Step 1: Inviolable Life Safety Exemption Check
        if sni:
            sni_clean = sni.lower().strip(".")
            for exempt in LIFE_SAFETY_EXEMPTIONS:
                if sni_clean == exempt or sni_clean.endswith(f".{exempt}"):
                    return SniThreatVerdict(
                        is_threat=False,
                        risk_score=0.0,
                        threat_type="LIFE_SAFETY_EXEMPT",
                        sni_hostname=sni,
                        expected_dns_domain=expected_dns_domain,
                        targeted_brand=None,
                        indicators=["life_safety_hardcoded_exemption"],
                        explanation=f"Exempt infrastructure/emergency service: {exempt}"
                    )

        if expected_dns_domain:
            dns_clean = expected_dns_domain.lower().strip(".")
            for exempt in LIFE_SAFETY_EXEMPTIONS:
                if dns_clean == exempt or dns_clean.endswith(f".{exempt}"):
                    return SniThreatVerdict(
                        is_threat=False,
                        risk_score=0.0,
                        threat_type="LIFE_SAFETY_EXEMPT",
                        sni_hostname=sni,
                        expected_dns_domain=expected_dns_domain,
                        targeted_brand=None,
                        indicators=["life_safety_hardcoded_exemption"],
                        explanation=f"Exempt DNS pre-resolution: {exempt}"
                    )

        # Step 2: Missing SNI on Modern TLS Connection
        if not sni:
            indicators.append("missing_sni_extension")
            score += 25.0

            # Covert channel / anomaly check on extensions
            if client_hello.padding_length > 512:
                indicators.append(f"oversized_padding_{client_hello.padding_length}_bytes")
                score += 40.0

            is_threat = score >= self.high_risk_threshold
            return SniThreatVerdict(
                is_threat=is_threat,
                risk_score=score,
                threat_type="ANONYMOUS_TLS_NO_SNI" if is_threat else "CLEAN",
                sni_hostname=None,
                expected_dns_domain=expected_dns_domain,
                targeted_brand=None,
                indicators=indicators,
                explanation="TLS handshake omitted SNI header; potential direct-IP C2 or evasion."
            )

        # Step 3: Domain Fronting / Mismatch Detection
        sni_apex = self.extract_apex_domain(sni)
        targeted_brand: Optional[str] = None

        if expected_dns_domain:
            expected_apex = self.extract_apex_domain(expected_dns_domain)
            if sni_apex != expected_apex:
                # Apex discrepancy indicates domain fronting evasion
                indicators.append(f"domain_fronting_mismatch:dns={expected_apex},sni={sni_apex}")
                score += 55.0

        # Step 4: Punycode / IDN Homograph in SNI
        if "xn--" in sni:
            indicators.append("punycode_idn_sni")
            score += 35.0
            try:
                decoded = sni.encode("ascii").decode("idna")
                indicators.append(f"decoded_punycode:{decoded}")
            except Exception:
                indicators.append("malformed_punycode")
                score += 20.0

        # Step 5: Brand Impersonation in SNI
        sni_labels = sni.split(".")
        tld = sni_labels[-1] if sni_labels else ""

        for profile in PROTECTED_BRANDS.values():
            brand_token = profile.name.lower()
            if brand_token in sni.lower():
                is_legit = BrandDictionary.is_legitimate_brand_apex(sni_apex, profile.name)
                if not is_legit:
                    targeted_brand = profile.name
                    indicators.append(f"impersonated_brand:{profile.name}")
                    score += 45.0
                    break

        # Check deceptive keywords in SNI subdomains
        deceptive_matches = [kw for kw in DECEPTIVE_KEYWORDS if kw in sni.lower()]
        if deceptive_matches:
            indicators.append(f"deceptive_keywords:{','.join(deceptive_matches[:3])}")
            score += min(30.0, len(deceptive_matches) * 12.0)

        # Step 6: High-Abuse TLD Weighting
        if tld in HIGH_ABUSE_TLDS:
            multiplier = HIGH_ABUSE_TLDS[tld]
            indicators.append(f"high_abuse_tld:{tld}")
            score += (multiplier - 1.0) * 25.0

        # Step 7: Shannon Entropy of SNI Hostname Subdomain
        if len(sni_labels) > 2:
            subdomain_part = ".".join(sni_labels[:-2])
            entropy = self.calculate_entropy(subdomain_part)
            if entropy > 3.8 and len(subdomain_part) > 12:
                indicators.append(f"high_entropy_sni_subdomain:{entropy:.2f}")
                score += 30.0

        # Step 8: Covert Channel Padding Check
        if client_hello.padding_length > 512:
            indicators.append(f"covert_padding_{client_hello.padding_length}_bytes")
            score += 35.0

        is_threat = score >= self.high_risk_threshold

        threat_type = "CLEAN"
        explanation = "SNI certificate request is benign and consistent."
        if is_threat:
            if "domain_fronting_mismatch" in str(indicators):
                threat_type = "DOMAIN_FRONTING"
                explanation = f"Domain fronting detected: SNI '{sni}' diverges from DNS query."
            elif targeted_brand:
                threat_type = "BRAND_IMPERSONATION"
                explanation = f"Zero-hour phishing SNI spoofing {targeted_brand}."
            elif "punycode_idn_sni" in indicators:
                threat_type = "PUNYCODE_HOMOGRAPH"
                explanation = f"Internationalized punycode SNI obfuscation: {sni}"
            elif client_hello.padding_length > 512:
                threat_type = "COVERT_CHANNEL_PADDING"
                explanation = f"TLS extension padding exfiltration anomaly ({client_hello.padding_length} bytes)."
            else:
                threat_type = "SUSPICIOUS_SNI_HEURISTIC"
                explanation = f"Suspicious SNI composition with high threat indicators: {', '.join(indicators[:2])}"

        return SniThreatVerdict(
            is_threat=is_threat,
            risk_score=score,
            threat_type=threat_type,
            sni_hostname=sni,
            expected_dns_domain=expected_dns_domain,
            targeted_brand=targeted_brand,
            indicators=indicators,
            explanation=explanation
        )

    def analyze_packet(
        self,
        packet_bytes: bytes,
        expected_dns_domain: Optional[str] = None
    ) -> SniThreatVerdict:
        """One-shot helper: parses packet and evaluates threat posture."""
        client_hello = self.parse_client_hello(packet_bytes)
        return self.evaluate_threat(client_hello, expected_dns_domain=expected_dns_domain)

    @staticmethod
    def build_client_hello(
        sni_hostname: Optional[str] = None,
        alpn_protocols: Optional[List[str]] = None,
        padding_len: int = 0,
        cipher_suites: Optional[List[int]] = None
    ) -> bytes:
        """
        Builds a compliant synthetic TLS 1.2/1.3 ClientHello packet for testing,
        fuzzing, and router simulation without requiring network sockets.
        """
        # Default cipher suites (e.g. TLS_AES_128_GCM_SHA256, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256)
        if cipher_suites is None:
            cipher_suites = [0x1301, 0x1302, 0xc02f, 0xc030]

        # 1. Build extensions
        ext_bytes = bytearray()

        # SNI Extension
        if sni_hostname:
            sni_ascii = sni_hostname.encode("ascii")
            sni_entry = struct.pack(">BH", SNI_TYPE_HOST_NAME, len(sni_ascii)) + sni_ascii
            sni_list = struct.pack(">H", len(sni_entry)) + sni_entry
            ext_bytes += struct.pack(">HH", EXTENSION_SERVER_NAME, len(sni_list)) + sni_list

        # ALPN Extension
        if alpn_protocols:
            alpn_inner = bytearray()
            for proto in alpn_protocols:
                p_bytes = proto.encode("ascii")
                alpn_inner += struct.pack(">B", len(p_bytes)) + p_bytes
            alpn_data = struct.pack(">H", len(alpn_inner)) + alpn_inner
            ext_bytes += struct.pack(">HH", EXTENSION_ALPN, len(alpn_data)) + alpn_data

        # Padding Extension
        if padding_len > 0:
            pad_data = b"\x00" * padding_len
            ext_bytes += struct.pack(">HH", EXTENSION_PADDING, len(pad_data)) + pad_data

        # Extensions block
        extensions_block = struct.pack(">H", len(ext_bytes)) + ext_bytes

        # 2. Handshake Body (ClientHello)
        client_version = 0x0303  # TLS 1.2
        random_bytes = b"\x42" * 32
        session_id = b"\x01\x02\x03\x04"
        session_id_block = struct.pack(">B", len(session_id)) + session_id

        # Cipher suites block
        cs_block = struct.pack(">H", len(cipher_suites) * 2)
        for cs in cipher_suites:
            cs_block += struct.pack(">H", cs)

        # Compression methods (0 = null)
        comp_block = b"\x01\x00"

        client_hello_body = (
            struct.pack(">H", client_version)
            + random_bytes
            + session_id_block
            + cs_block
            + comp_block
            + extensions_block
        )

        # 3. Handshake Header
        hs_len = len(client_hello_body)
        hs_header = struct.pack(">B", TLS_HANDSHAKE_CLIENT_HELLO) + bytes([
            (hs_len >> 16) & 0xFF,
            (hs_len >> 8) & 0xFF,
            hs_len & 0xFF
        ])
        handshake_packet = hs_header + client_hello_body

        # 4. TLS Record Layer
        record_len = len(handshake_packet)
        record_header = struct.pack(">BBBH", TLS_RECORD_HANDSHAKE, 0x03, 0x01, record_len)

        return record_header + handshake_packet
