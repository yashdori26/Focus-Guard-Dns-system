"""
FocusDNS Engine - RFC 9460 §6.1 & draft-ietf-tls-esni Encrypted Client Hello (ECH) Subsystem
Standards & Specifications:
- RFC 9460 Section 6.1: ECH SvcParam for SVCB/HTTPS Resource Records
- draft-ietf-tls-esni-22: Encrypted Client Hello (ECH) for TLS 1.3
- RFC 9180: Hybrid Public Key Encryption (HPKE)
"""

import base64
import os
import struct
from enum import IntEnum
from typing import Any, Dict, List, Optional, Tuple, Union


# Standard ECH TLS Extension Version
ECH_VERSION_DRAFT13 = 0xFE0D


class HPKEKemId(IntEnum):
    """Registered HPKE KEM identifiers (RFC 9180)."""
    DHKEM_P256_HKDF_SHA256 = 0x0010
    DHKEM_X25519_HKDF_SHA256 = 0x0020
    DHKEM_X448_HKDF_SHA512 = 0x0021


class HPKEKdfId(IntEnum):
    """Registered HPKE KDF identifiers (RFC 9180)."""
    HKDF_SHA256 = 0x0001
    HKDF_SHA384 = 0x0002
    HKDF_SHA512 = 0x0003


class HPKEAeadId(IntEnum):
    """Registered HPKE AEAD identifiers (RFC 9180)."""
    AES_128_GCM = 0x0001
    AES_256_GCM = 0x0002
    CHACHA20_POLY1305 = 0x0003


class HPKECipherSuite:
    """Represents a combined HPKE KDF and AEAD ciphersuite."""

    def __init__(self, kdf_id: Union[int, HPKEKdfId], aead_id: Union[int, HPKEAeadId]):
        self.kdf_id: int = int(kdf_id)
        self.aead_id: int = int(aead_id)

    def to_wire(self) -> bytes:
        return struct.pack("!HH", self.kdf_id, self.aead_id)

    @classmethod
    def from_wire(cls, data: bytes, offset: int = 0) -> Tuple["HPKECipherSuite", int]:
        if len(data) - offset < 4:
            raise ValueError("Malformed HPKECipherSuite wire data")
        kdf, aead = struct.unpack("!HH", data[offset : offset + 4])
        return cls(kdf, aead), offset + 4

    def to_dict(self) -> Dict[str, Any]:
        return {"kdf_id": self.kdf_id, "aead_id": self.aead_id}


class ECHConfig:
    """
    Encapsulates an RFC 9460 §6.1 / draft-ietf-tls-esni ECHConfig structure:
    struct {
        uint16 version;
        uint16 length;
        select (ECHConfig.version) {
            case 0xfe0d: ECHConfigContents contents;
        }
    } ECHConfig;
    """

    def __init__(
        self,
        public_name: str,
        public_key: bytes,
        kem_id: Union[int, HPKEKemId] = HPKEKemId.DHKEM_X25519_HKDF_SHA256,
        cipher_suites: Optional[List[HPKECipherSuite]] = None,
        config_id: int = 1,
        maximum_name_length: int = 64,
        version: int = ECH_VERSION_DRAFT13,
        extensions: bytes = b"",
    ):
        self.version: int = version
        self.config_id: int = config_id
        self.kem_id: int = int(kem_id)
        self.public_key: bytes = public_key
        self.cipher_suites: List[HPKECipherSuite] = cipher_suites or [
            HPKECipherSuite(HPKEKdfId.HKDF_SHA256, HPKEAeadId.AES_128_GCM),
            HPKECipherSuite(HPKEKdfId.HKDF_SHA256, HPKEAeadId.CHACHA20_POLY1305),
        ]
        self.maximum_name_length: int = maximum_name_length
        self.public_name: str = public_name.strip().lower().rstrip(".")
        self.extensions: bytes = extensions

    def _encode_contents(self) -> bytes:
        """Serializes the inner ECHConfigContents."""
        buf = bytearray()
        buf.append(self.config_id)
        buf.extend(struct.pack("!H", self.kem_id))

        # Public key: 2-byte length + key octets
        buf.extend(struct.pack("!H", len(self.public_key)))
        buf.extend(self.public_key)

        # Cipher suites: 2-byte total length + list of 4-byte suites
        cs_bytes = bytearray()
        for cs in self.cipher_suites:
            cs_bytes.extend(cs.to_wire())
        buf.extend(struct.pack("!H", len(cs_bytes)))
        buf.extend(cs_bytes)

        # Maximum name length
        buf.append(self.maximum_name_length)

        # Public name: DNS domain wire format
        name_bytes = self.public_name.encode("utf-8")
        buf.extend(struct.pack("!B", len(name_bytes)))
        buf.extend(name_bytes)

        # Extensions: 2-byte length + octets
        buf.extend(struct.pack("!H", len(self.extensions)))
        buf.extend(self.extensions)

        return bytes(buf)

    def to_wire(self) -> bytes:
        """Serializes full outer ECHConfig [version: 2][length: 2][contents]."""
        contents = self._encode_contents()
        return struct.pack("!HH", self.version, len(contents)) + contents

    @classmethod
    def from_wire(cls, data: bytes, offset: int = 0) -> Tuple["ECHConfig", int]:
        if len(data) - offset < 4:
            raise ValueError("Truncated ECHConfig wire header")
        version, contents_len = struct.unpack("!HH", data[offset : offset + 4])
        offset += 4

        if len(data) - offset < contents_len:
            raise ValueError("Truncated ECHConfig contents payload")

        end_offset = offset + contents_len
        config_id = data[offset]
        offset += 1

        kem_id = struct.unpack("!H", data[offset : offset + 2])[0]
        offset += 2

        pk_len = struct.unpack("!H", data[offset : offset + 2])[0]
        offset += 2
        public_key = data[offset : offset + pk_len]
        offset += pk_len

        cs_total_len = struct.unpack("!H", data[offset : offset + 2])[0]
        offset += 2
        cs_end = offset + cs_total_len
        cipher_suites = []
        while offset < cs_end:
            cs, offset = HPKECipherSuite.from_wire(data, offset)
            cipher_suites.append(cs)

        max_name_len = data[offset]
        offset += 1

        name_len = data[offset]
        offset += 1
        public_name = data[offset : offset + name_len].decode("utf-8", errors="replace")
        offset += name_len

        ext_len = struct.unpack("!H", data[offset : offset + 2])[0]
        offset += 2
        extensions = data[offset : offset + ext_len]
        offset += ext_len

        config = cls(
            public_name=public_name,
            public_key=public_key,
            kem_id=kem_id,
            cipher_suites=cipher_suites,
            config_id=config_id,
            maximum_name_length=max_name_len,
            version=version,
            extensions=extensions,
        )
        return config, end_offset

    def to_dict(self) -> Dict[str, Any]:
        return {
            "version": hex(self.version),
            "config_id": self.config_id,
            "public_name": self.public_name,
            "kem_id": self.kem_id,
            "public_key_b64": base64.b64encode(self.public_key).decode("ascii"),
            "cipher_suites": [cs.to_dict() for cs in self.cipher_suites],
            "maximum_name_length": self.maximum_name_length,
        }


class ECHConfigList:
    """
    RFC 9460 Encrypted Client Hello ConfigList.
    Wire format: 2-octet length prefix followed by one or more ECHConfig structures.
    """

    def __init__(self, configs: Optional[List[ECHConfig]] = None):
        self.configs: List[ECHConfig] = configs or []

    def to_wire(self) -> bytes:
        buf = bytearray()
        for cfg in self.configs:
            buf.extend(cfg.to_wire())
        return struct.pack("!H", len(buf)) + bytes(buf)

    @classmethod
    def from_wire(cls, data: bytes) -> "ECHConfigList":
        if len(data) < 2:
            raise ValueError("Malformed ECHConfigList: wire buffer too short")
        total_len = struct.unpack("!H", data[:2])[0]
        if len(data) - 2 < total_len:
            raise ValueError("Truncated ECHConfigList buffer")

        configs = []
        offset = 2
        end = 2 + total_len
        while offset < end:
            cfg, offset = ECHConfig.from_wire(data, offset)
            configs.append(cfg)

        return cls(configs)

    def to_base64(self) -> str:
        """Encodes to standard DNS HTTPS presentation format string."""
        return base64.b64encode(self.to_wire()).decode("ascii")

    @classmethod
    def from_base64(cls, b64_str: str) -> "ECHConfigList":
        """Decodes from standard DNS HTTPS presentation format string."""
        raw_bytes = base64.b64decode(b64_str.strip())
        return cls.from_wire(raw_bytes)

    @classmethod
    def generate_carrier_config(
        cls,
        public_name: str = "cloudflare-ech.com",
        public_key: Optional[bytes] = None,
    ) -> "ECHConfigList":
        """Generates an RFC-compliant test/production ECHConfigList."""
        pk = public_key or os.urandom(32)  # 32-byte X25519 public key
        cfg = ECHConfig(public_name=public_name, public_key=pk)
        return cls([cfg])

    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_configs": len(self.configs),
            "configs": [c.to_dict() for c in self.configs],
            "base64_representation": self.to_base64(),
        }
