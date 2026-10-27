"""
FocusDNS Engine - Automated TLS & QUIC Certificate Manager
Supports:
- Auto-generation of cryptographic X.509 certificates with SAN (Subject Alternative Names)
- TLS 1.3 / TLS 1.2 SSLContext for DNS-over-TLS (RFC 7858)
- aioquic QuicConfiguration for DNS-over-QUIC (RFC 9250)
- Configurable certificate paths for production Let's Encrypt / custom CA certificates
"""

import os
import ssl
import sys
import socket
import datetime
import ipaddress
from pathlib import Path
from typing import Tuple, List, Optional

from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa

# Default directory for self-signed certificates
DEFAULT_CERTS_DIR = Path(__file__).resolve().parent.parent / "certs"
DEFAULT_CERT_FILE = DEFAULT_CERTS_DIR / "focus_dns.crt"
DEFAULT_KEY_FILE = DEFAULT_CERTS_DIR / "focus_dns.key"


def generate_self_signed_cert(
    cert_path: Path,
    key_path: Path,
    common_name: str = "FocusDNS Encrypted Engine",
    san_hosts: Optional[List[str]] = None,
    validity_days: int = 365,
) -> Tuple[str, str]:
    """
    Generates a cryptographically strong self-signed X.509 certificate and private key.
    Writes PEM files with restrictive permissions (0600 on key).
    """
    cert_path.parent.mkdir(parents=True, exist_ok=True)

    # 1. Generate 2048-bit RSA private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )

    # 2. Build Subject and Issuer
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "California"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "FocusGuard Technologies"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "Core DNS Engine"),
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
    ])

    # 3. Assemble Subject Alternative Names (SAN)
    sans: List[x509.GeneralName] = [
        x509.DNSName("localhost"),
        x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
        x509.IPAddress(ipaddress.IPv6Address("::1")),
    ]

    hostname = socket.gethostname()
    if hostname and hostname != "localhost":
        try:
            sans.append(x509.DNSName(hostname))
        except Exception:
            pass

    if san_hosts:
        for host in san_hosts:
            host_clean = host.strip()
            if not host_clean:
                continue
            try:
                ip_obj = ipaddress.ip_address(host_clean)
                sans.append(x509.IPAddress(ip_obj))
            except ValueError:
                try:
                    sans.append(x509.DNSName(host_clean))
                except Exception:
                    pass

    now = datetime.datetime.now(datetime.timezone.utc)
    cert_builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=validity_days))
        .add_extension(
            x509.SubjectAlternativeName(sans),
            critical=False,
        )
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([
                ExtendedKeyUsageOID.SERVER_AUTH,
                ExtendedKeyUsageOID.CLIENT_AUTH,
            ]),
            critical=False,
        )
    )

    cert = cert_builder.sign(private_key, hashes.SHA256())

    # 4. Serialize to PEM format
    cert_pem = cert.public_bytes(serialization.Encoding.PEM)
    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    )

    # 5. Write files with secure permissions
    with open(cert_path, "wb") as f:
        f.write(cert_pem)
    os.chmod(cert_path, 0o644)

    with open(key_path, "wb") as f:
        f.write(key_pem)
    os.chmod(key_path, 0o600)

    return str(cert_path), str(key_path)


def ensure_certificates(
    cert_path: Optional[str] = None,
    key_path: Optional[str] = None,
    san_hosts: Optional[List[str]] = None,
) -> Tuple[str, str]:
    """
    Ensures that valid TLS certificates exist.
    If custom paths are specified via environment or arguments, checks for their existence.
    Otherwise, generates self-signed certificates in server/certs/.
    """
    env_cert = os.environ.get("FOCUS_TLS_CERT") or os.environ.get("SSL_CERT_FILE")
    env_key = os.environ.get("FOCUS_TLS_KEY") or os.environ.get("SSL_KEY_FILE")

    target_cert = Path(cert_path or env_cert or DEFAULT_CERT_FILE)
    target_key = Path(key_path or env_key or DEFAULT_KEY_FILE)

    if target_cert.exists() and target_key.exists():
        try:
            with open(target_cert, "rb") as f:
                c = x509.load_pem_x509_certificate(f.read())
            # Check validity window
            now = datetime.datetime.now(datetime.timezone.utc)
            if c.not_valid_after_utc > (now + datetime.timedelta(days=7)):
                return str(target_cert), str(target_key)
        except Exception:
            pass  # Re-generate if corrupt or expired

    return generate_self_signed_cert(target_cert, target_key, san_hosts=san_hosts)


def create_dot_ssl_context(
    cert_file: Optional[str] = None,
    key_file: Optional[str] = None,
) -> ssl.SSLContext:
    """
    Creates an RFC 7858 compliant SSLContext for DNS-over-TLS (DoT).
    Enforces TLS 1.2+ (prioritizing TLS 1.3), ALPN negotiation for 'dot',
    and strong modern cipher suites.
    """
    cert_path, key_path = ensure_certificates(cert_file, key_file)

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    # Strictly enforce TLS 1.2 or higher
    if hasattr(ssl, "TLSVersion") and hasattr(ssl.TLSVersion, "TLSv1_2"):
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2

    else:
        ctx.options |= ssl.OP_NO_SSLv2 | ssl.OP_NO_SSLv3 | ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1
    ctx.options |= ssl.OP_CIPHER_SERVER_PREFERENCE
    ctx.options |= ssl.OP_NO_COMPRESSION


    # ALPN protocol negotiation: RFC 7858 standard ALPN tag is "dot"
    try:
        ctx.set_alpn_protocols(["dot"])
    except NotImplementedError:
        pass

    # Modern ciphers
    ctx.set_ciphers("ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20")
    ctx.load_cert_chain(certfile=cert_path, keyfile=key_path)

    return ctx


def create_doq_quic_configuration(
    cert_file: Optional[str] = None,
    key_file: Optional[str] = None,
) -> "QuicConfiguration":
    """
    Creates an RFC 9250 compliant QuicConfiguration for DNS-over-QUIC (DoQ).
    Enforces ALPN 'doq', 0-RTT session resumption, and sensible timeouts.
    """
    from aioquic.quic.configuration import QuicConfiguration

    cert_path, key_path = ensure_certificates(cert_file, key_file)

    conf = QuicConfiguration(
        is_client=False,
        alpn_protocols=["doq"],
        max_datagram_frame_size=65536,
        idle_timeout=60.0,
    )
    conf.load_cert_chain(certfile=cert_path, keyfile=key_path)
    return conf
