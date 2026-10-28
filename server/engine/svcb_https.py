"""
FocusDNS Engine - RFC 9460 SVCB and HTTPS Resource Records Subsystem
Standards & RFCs:
- RFC 9460: Service Binding and Parameter Specification via the DNS (SVCB and HTTPS Resource Records)
- draft-ietf-tls-esni / RFC 9460 §6.1: Encrypted Client Hello (ECH) parameter
"""

import io
import socket
import struct
from enum import IntEnum
from typing import Any, Dict, List, Optional, Set, Tuple, Union

TYPE_SVCB = 64
TYPE_HTTPS = 65


class SvcParamKey(IntEnum):
    """Registered SvcParamKeys defined in RFC 9460 Section 14.3.2."""
    MANDATORY = 0
    ALPN = 1
    NO_DEFAULT_ALPN = 2
    PORT = 3
    IPV4HINT = 4
    ECH = 5
    IPV6HINT = 6
    DOHPATH = 7


KEY_NAME_MAP = {
    "mandatory": SvcParamKey.MANDATORY,
    "alpn": SvcParamKey.ALPN,
    "no-default-alpn": SvcParamKey.NO_DEFAULT_ALPN,
    "port": SvcParamKey.PORT,
    "ipv4hint": SvcParamKey.IPV4HINT,
    "ech": SvcParamKey.ECH,
    "ipv6hint": SvcParamKey.IPV6HINT,
    "dohpath": SvcParamKey.DOHPATH,
}

KEY_CODE_MAP = {v: k for k, v in KEY_NAME_MAP.items()}


class SvcParam:
    """Represents a single SvcParam key-value pair in wire and presentation formats."""

    def __init__(self, key: Union[int, SvcParamKey], value: Any = None, raw_value: Optional[bytes] = None):
        self.key: int = int(key)
        self.value: Any = value
        self.raw_value: bytes = raw_value if raw_value is not None else b""

        if value is not None:
            self.value = value
            if raw_value is None:
                self.raw_value = self._encode_value(self.key, value)
        elif raw_value is not None:
            self.raw_value = raw_value
            self.value = self._decode_value(self.key, raw_value)

    @property
    def key_name(self) -> str:
        try:
            return KEY_CODE_MAP.get(SvcParamKey(self.key), f"key{self.key}")
        except ValueError:
            return f"key{self.key}"

    @staticmethod
    def _encode_value(key: int, val: Any) -> bytes:
        """Encodes native Python values into wire format octets per RFC 9460."""
        if key == SvcParamKey.MANDATORY:
            # List of 2-octet SvcParamKey values in ascending order
            keys = sorted(int(k) for k in val)
            return struct.pack(f"!{len(keys)}H", *keys)

        elif key == SvcParamKey.ALPN:
            # Wire format: sequence of length-prefixed octet strings
            # Each ALPN protocol ID is prefixed by its 1-octet length
            buf = io.BytesIO()
            if isinstance(val, str):
                val = [item.strip() for item in val.split(",")]
            for proto in val:
                proto_bytes = proto.encode("utf-8") if isinstance(proto, str) else bytes(proto)
                if len(proto_bytes) > 255:
                    raise ValueError(f"ALPN protocol identifier exceeds 255 octets: {proto}")
                buf.write(struct.pack("!B", len(proto_bytes)))
                buf.write(proto_bytes)
            return buf.getvalue()

        elif key == SvcParamKey.NO_DEFAULT_ALPN:
            # Valueless flag parameter; MUST have length 0
            return b""

        elif key == SvcParamKey.PORT:
            port_num = int(val)
            if not (0 <= port_num <= 65535):
                raise ValueError(f"Port number out of range: {port_num}")
            return struct.pack("!H", port_num)

        elif key == SvcParamKey.IPV4HINT:
            if isinstance(val, str):
                val = [ip.strip() for ip in val.split(",")]
            buf = bytearray()
            for ip_str in val:
                buf.extend(socket.inet_aton(ip_str))
            return bytes(buf)

        elif key == SvcParamKey.IPV6HINT:
            if isinstance(val, str):
                val = [ip.strip() for ip in val.split(",")]
            buf = bytearray()
            for ip_str in val:
                buf.extend(socket.inet_pton(socket.AF_INET6, ip_str))
            return bytes(buf)

        elif key == SvcParamKey.DOHPATH:
            return val.encode("utf-8") if isinstance(val, str) else bytes(val)

        elif key == SvcParamKey.ECH:
            if isinstance(val, str):
                import base64
                return base64.b64decode(val)
            return bytes(val)

        else:
            # Generic/private parameter keys: binary data
            if isinstance(val, bytes):
                return val
            elif isinstance(val, str):
                return val.encode("utf-8")
            return bytes(val)

    @staticmethod
    def _decode_value(key: int, data: bytes) -> Any:
        """Decodes wire format octets into native Python objects per RFC 9460."""
        if key == SvcParamKey.MANDATORY:
            if len(data) % 2 != 0:
                raise ValueError("Malformed mandatory SvcParam wire data: odd length")
            count = len(data) // 2
            keys = struct.unpack(f"!{count}H", data)
            return list(keys)

        elif key == SvcParamKey.ALPN:
            protos: List[str] = []
            idx = 0
            while idx < len(data):
                length = data[idx]
                idx += 1
                if idx + length > len(data):
                    raise ValueError("Malformed ALPN wire data: length overflow")
                proto_bytes = data[idx : idx + length]
                protos.append(proto_bytes.decode("utf-8", errors="replace"))
                idx += length
            return protos

        elif key == SvcParamKey.NO_DEFAULT_ALPN:
            if len(data) != 0:
                raise ValueError("no-default-alpn MUST have length 0")
            return True

        elif key == SvcParamKey.PORT:
            if len(data) != 2:
                raise ValueError("Malformed port SvcParam wire data: expected 2 octets")
            return struct.unpack("!H", data)[0]

        elif key == SvcParamKey.IPV4HINT:
            if len(data) % 4 != 0:
                raise ValueError("Malformed ipv4hint wire data: length not multiple of 4")
            ips = []
            for i in range(0, len(data), 4):
                ips.append(socket.inet_ntoa(data[i : i + 4]))
            return ips

        elif key == SvcParamKey.IPV6HINT:
            if len(data) % 16 != 0:
                raise ValueError("Malformed ipv6hint wire data: length not multiple of 16")
            ips = []
            for i in range(0, len(data), 16):
                ips.append(socket.inet_ntop(socket.AF_INET6, data[i : i + 16]))
            return ips

        elif key == SvcParamKey.DOHPATH:
            return data.decode("utf-8", errors="replace")

        elif key == SvcParamKey.ECH:
            import base64
            return base64.b64encode(data).decode("ascii")

        else:
            return data

    def to_wire(self) -> bytes:
        """Serializes param to wire format: [key: 2 octets][length: 2 octets][value: N octets]."""
        return struct.pack("!HH", self.key, len(self.raw_value)) + self.raw_value

    def to_presentation(self) -> str:
        """Outputs presentation text for master zone files per RFC 9460 Section 2.1."""
        name = self.key_name
        if self.key == SvcParamKey.NO_DEFAULT_ALPN:
            return name
        elif self.key == SvcParamKey.ALPN:
            if isinstance(self.value, list):
                return f'{name}="{",".join(self.value)}"'
            return f'{name}="{self.value}"'
        elif self.key in (SvcParamKey.IPV4HINT, SvcParamKey.IPV6HINT):
            if isinstance(self.value, list):
                return f'{name}={",".join(self.value)}'
            return f'{name}={self.value}'
        elif self.key == SvcParamKey.PORT:
            return f"{name}={self.value}"
        elif self.key == SvcParamKey.DOHPATH:
            return f'{name}="{self.value}"'
        elif self.key == SvcParamKey.ECH:
            return f"{name}={self.value}"
        elif self.key == SvcParamKey.MANDATORY:
            if isinstance(self.value, list):
                names = [KEY_CODE_MAP.get(SvcParamKey(k), f"key{k}") for k in self.value]
                return f'{name}={",".join(names)}'
            return f"{name}={self.value}"
        else:
            import base64
            return f'{name}="{base64.b64encode(self.raw_value).decode("ascii")}"'

    def to_dict(self) -> Dict[str, Any]:
        return {
            "key": self.key,
            "key_name": self.key_name,
            "value": self.value,
            "raw_len": len(self.raw_value),
        }


class SVCBRecord:
    """
    RFC 9460 Service Binding (SVCB) Resource Record implementation.
    Operates in either:
    1. AliasMode: SvcPriority == 0, provides authoritative alias redirection.
    2. ServiceMode: SvcPriority > 0, provides endpoint configuration parameters.
    """

    def __init__(
        self,
        priority: int = 1,
        target_name: str = ".",
        params: Optional[List[SvcParam]] = None,
        is_https: bool = False,
    ):
        self.priority: int = priority
        self.target_name: str = target_name.strip().lower()
        if not self.target_name.endswith("."):
            self.target_name += "."

        self.is_https: bool = is_https
        self._params: Dict[int, SvcParam] = {}
        if params:
            for p in params:
                self._params[p.key] = p

    @property
    def is_alias_mode(self) -> bool:
        """AliasMode if SvcPriority is 0; must not contain SvcParams."""
        return self.priority == 0

    @property
    def is_service_mode(self) -> bool:
        """ServiceMode if SvcPriority > 0."""
        return self.priority > 0

    def get_param(self, key: Union[int, SvcParamKey, str]) -> Optional[SvcParam]:
        if isinstance(key, str):
            code = KEY_NAME_MAP.get(key.lower())
            if code is None:
                if key.lower().startswith("key"):
                    try:
                        code = int(key[3:])
                    except ValueError:
                        return None
                else:
                    return None
            return self._params.get(int(code))
        return self._params.get(int(key))

    def set_param(self, param: SvcParam):
        if self.is_alias_mode:
            raise ValueError("AliasMode (priority 0) MUST NOT contain SvcParams per RFC 9460 Section 2.4.2")
        self._params[param.key] = param

    def remove_param(self, key: Union[int, SvcParamKey, str]) -> bool:
        param = self.get_param(key)
        if param and param.key in self._params:
            del self._params[param.key]
            return True
        return False

    def list_params(self) -> List[SvcParam]:
        # MUST be ordered by strictly increasing numeric SvcParamKey (RFC 9460 §2.2)
        return [self._params[k] for k in sorted(self._params.keys())]

    @staticmethod
    def _encode_domain_name(name: str) -> bytes:
        """Encodes an uncompressed domain name into DNS wire format labels."""
        clean = name.strip().rstrip(".")
        if not clean:
            return b"\x00"  # Root apex '.'
        labels = clean.split(".")
        buf = bytearray()
        for label in labels:
            encoded_label = label.encode("utf-8")
            if len(encoded_label) > 63:
                raise ValueError(f"DNS label exceeds 63 octets: {label}")
            buf.append(len(encoded_label))
            buf.extend(encoded_label)
        buf.append(0)  # Null terminator
        return bytes(buf)

    @staticmethod
    def _decode_domain_name(data: bytes, offset: int = 0) -> Tuple[str, int]:
        """Decodes an uncompressed domain name from DNS wire format."""
        labels = []
        curr = offset
        while curr < len(data):
            length = data[curr]
            curr += 1
            if length == 0:
                break
            if length > 63:
                raise ValueError("Malformed domain name: label length exceeds 63")
            if curr + length > len(data):
                raise ValueError("Malformed domain name: buffer overflow reading label")
            label = data[curr : curr + length].decode("utf-8", errors="replace")
            labels.append(label)
            curr += length

        domain = ".".join(labels) + "." if labels else "."
        return domain, curr

    def to_wire(self) -> bytes:
        """
        Serializes SVCB/HTTPS RDATA to wire format per RFC 9460 Section 2.2:
        - SvcPriority: 2 octets (big-endian)
        - TargetName: uncompressed wire domain name
        - SvcParams: list of SvcParam wire TLVs in strictly ascending numerical key order
        """
        buf = bytearray()
        buf.extend(struct.pack("!H", self.priority))
        buf.extend(self._encode_domain_name(self.target_name))

        # Sort SvcParams in strictly ascending SvcParamKey order
        for key in sorted(self._params.keys()):
            buf.extend(self._params[key].to_wire())

        return bytes(buf)

    @classmethod
    def from_wire(cls, data: bytes, is_https: bool = False, offset: int = 0) -> "SVCBRecord":
        """Deserializes SVCB/HTTPS RDATA from wire format octets."""
        if len(data) - offset < 3:
            raise ValueError("Malformed SVCB wire data: too short")

        priority = struct.unpack("!H", data[offset : offset + 2])[0]
        offset += 2

        target_name, offset = cls._decode_domain_name(data, offset)

        params: List[SvcParam] = []
        last_key = -1

        while offset < len(data):
            if len(data) - offset < 4:
                raise ValueError("Truncated SvcParam header in wire data")
            key, val_len = struct.unpack("!HH", data[offset : offset + 4])
            offset += 4

            if key <= last_key:
                raise ValueError(f"SvcParams MUST be in strictly ascending numerical order (got {key} after {last_key})")
            last_key = key

            if offset + val_len > len(data):
                raise ValueError("Truncated SvcParam value in wire data")
            raw_val = data[offset : offset + val_len]
            offset += val_len

            param = SvcParam(key=key, raw_value=raw_val)
            params.append(param)

        return cls(priority=priority, target_name=target_name, params=params, is_https=is_https)

    def to_presentation(self) -> str:
        """Generates RFC 9460 Section 2.1 presentation format text."""
        parts = [str(self.priority), self.target_name]
        for p in self.list_params():
            parts.append(p.to_presentation())
        return " ".join(parts)

    @classmethod
    def parse_presentation(cls, text: str, is_https: bool = False) -> "SVCBRecord":
        """
        Parses master zone file presentation string format:
        e.g., '1 . alpn="h3,h2" port=443 ipv4hint=198.51.100.1 ech=aGVsbG8='
        """
        tokens = cls._tokenize_presentation(text)
        if len(tokens) < 2:
            raise ValueError(f"Invalid SVCB presentation format: '{text}' (requires priority and target)")

        priority = int(tokens[0])
        target_name = tokens[1]
        params: List[SvcParam] = []

        for token in tokens[2:]:
            if "=" in token:
                k_str, v_str = token.split("=", 1)
                k_str = k_str.strip().lower()
                v_str = v_str.strip()
                if v_str.startswith('"') and v_str.endswith('"'):
                    v_str = v_str[1:-1]
            else:
                k_str = token.strip().lower()
                v_str = ""

            key_code = KEY_NAME_MAP.get(k_str)
            if key_code is None:
                if k_str.startswith("key"):
                    key_code = int(k_str[3:])
                else:
                    raise ValueError(f"Unknown SvcParam key: {k_str}")

            if key_code == SvcParamKey.NO_DEFAULT_ALPN:
                param = SvcParam(key=key_code, value=True)
            elif key_code == SvcParamKey.PORT:
                param = SvcParam(key=key_code, value=int(v_str))
            elif key_code == SvcParamKey.ALPN:
                param = SvcParam(key=key_code, value=[s.strip() for s in v_str.split(",")])
            elif key_code in (SvcParamKey.IPV4HINT, SvcParamKey.IPV6HINT):
                param = SvcParam(key=key_code, value=[s.strip() for s in v_str.split(",")])
            elif key_code == SvcParamKey.MANDATORY:
                sub_keys = [KEY_NAME_MAP.get(s.strip().lower(), 0) for s in v_str.split(",")]
                param = SvcParam(key=key_code, value=sub_keys)
            else:
                param = SvcParam(key=key_code, value=v_str)

            params.append(param)

        return cls(priority=priority, target_name=target_name, params=params, is_https=is_https)

    @staticmethod
    def _tokenize_presentation(text: str) -> List[str]:
        """Tokenizes presentation text respecting double quotes."""
        tokens = []
        current = []
        in_quotes = False
        for ch in text.strip():
            if ch == '"':
                in_quotes = not in_quotes
                current.append(ch)
            elif ch.isspace() and not in_quotes:
                if current:
                    tokens.append("".join(current))
                    current = []
            else:
                current.append(ch)
        if current:
            tokens.append("".join(current))
        return tokens

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_https": self.is_https,
            "priority": self.priority,
            "target_name": self.target_name,
            "is_alias_mode": self.is_alias_mode,
            "is_service_mode": self.is_service_mode,
            "presentation": self.to_presentation(),
            "params": [p.to_dict() for p in self.list_params()],
        }


class HTTPSRecord(SVCBRecord):
    """
    RFC 9460 HTTPS Resource Record (Type 65).
    Syntactic specialization of SVCB specifically for HTTP and HTTPS schemas.
    """

    def __init__(
        self,
        priority: int = 1,
        target_name: str = ".",
        params: Optional[List[SvcParam]] = None,
        is_https: bool = True,
    ):
        super().__init__(priority=priority, target_name=target_name, params=params, is_https=is_https)


class SVCBResolver:
    """
    Advanced Service Binding resolution engine.
    Resolves AliasMode redirects, negotiates client protocol capabilities (ALPN),
    and synthesizes hint endpoints.
    """

    def __init__(self):
        # zone -> qname -> List[SVCBRecord]
        self._records: Dict[str, List[SVCBRecord]] = {}

    def add_record(self, domain: str, record: SVCBRecord):
        clean = domain.strip().lower().rstrip(".")
        if clean not in self._records:
            self._records[clean] = []
        self._records[clean].append(record)

    def resolve(
        self,
        domain: str,
        supported_alpns: Optional[List[str]] = None,
        max_alias_depth: int = 5,
    ) -> Dict[str, Any]:
        """
        Resolves the optimal SVCB/HTTPS service configuration for a domain.
        Follows AliasMode targets up to max_alias_depth to prevent infinite loops.
        """
        clean = domain.strip().lower().rstrip(".")
        current_name = clean
        alias_chain: List[str] = [current_name]

        depth = 0
        while depth < max_alias_depth:
            recs = self._records.get(current_name, [])
            if not recs:
                return {
                    "found": False,
                    "qname": domain,
                    "target": current_name,
                    "alias_chain": alias_chain,
                    "selected_record": None,
                }

            # Check if there is an AliasMode record (priority == 0)
            alias_rec = next((r for r in recs if r.is_alias_mode), None)
            if alias_rec:
                target = alias_rec.target_name.rstrip(".")
                if target in alias_chain:
                    return {
                        "error": "Cyclic AliasMode redirection loop detected",
                        "alias_chain": alias_chain + [target],
                    }
                alias_chain.append(target)
                current_name = target
                depth += 1
                continue
            else:
                # ServiceMode records found
                service_records = [r for r in recs if r.is_service_mode]
                # Sort by priority ascending (lowest numerical priority = highest preference)
                service_records.sort(key=lambda r: r.priority)

                selected = None
                if supported_alpns:
                    # Filter for records matching client's supported ALPN
                    for cand in service_records:
                        alpn_param = cand.get_param(SvcParamKey.ALPN)
                        if alpn_param and isinstance(alpn_param.value, list):
                            if any(proto in supported_alpns for proto in alpn_param.value):
                                selected = cand
                                break
                if not selected and service_records:
                    selected = service_records[0]

                return {
                    "found": True,
                    "qname": domain,
                    "target": current_name,
                    "alias_chain": alias_chain,
                    "all_candidates": [r.to_dict() for r in service_records],
                    "selected_record": selected.to_dict() if selected else None,
                }

        return {
            "error": "Exceeded maximum AliasMode resolution depth",
            "alias_chain": alias_chain,
        }

    def synthesize_a_records(self, record: SVCBRecord) -> List[str]:
        """Extracts IPv4 address hints from record parameters."""
        p = record.get_param(SvcParamKey.IPV4HINT)
        if p and isinstance(p.value, list):
            return list(p.value)
        return []

    def synthesize_aaaa_records(self, record: SVCBRecord) -> List[str]:
        """Extracts IPv6 address hints from record parameters."""
        p = record.get_param(SvcParamKey.IPV6HINT)
        if p and isinstance(p.value, list):
            return list(p.value)
        return []
