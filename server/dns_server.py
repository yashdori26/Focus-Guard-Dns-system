"""
FocusDNS Master Server Launcher - Cycle 3 Hardened
Runs:
- HTTP REST API & RFC 8484 DoH Server (Default: 127.0.0.1:8080)
- Multi-Threaded UDP DNS RFC 1035 Server (Default: 127.0.0.1:5354) with ThreadPoolExecutor
- Automated background log retention purge scheduler
"""

import concurrent.futures
import os
import socket
import ssl
import threading
from typing import Tuple
from http.server import HTTPServer
from socketserver import ThreadingMixIn

from . import db
from . import resolver
from .api_router import FocusDNSApiHandler
from .engine import DotServerThread, DoqServerThread, Doh3ServerThread

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class ThreadedHTTPSServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    def __init__(self, server_address, RequestHandlerClass, ssl_context=None):
        super().__init__(server_address, RequestHandlerClass)
        self.ssl_context = ssl_context

    def get_request(self):
        sock, addr = super().get_request()
        if self.ssl_context:
            try:
                ssl_sock = self.ssl_context.wrap_socket(sock, server_side=True)
                return ssl_sock, addr
            except Exception:
                try:
                    sock.close()
                except Exception:
                    pass
                raise
        return sock, addr


def start_udp_dns_server(host: str = '127.0.0.1', port: int = 5354, max_workers: int = 20):
    """
    Listens for raw DNS UDP packets on 127.0.0.1:5354.
    Dispatches resolution to a thread pool so slow lookups never stall other clients.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind((host, port))
    except Exception as e:
        print(f"⚠️ Could not bind UDP DNS on {host}:{port}: {e}")
        return

    print(f"🛡️  FocusDNS Thread-Pooled UDP RFC Resolver active on {host}:{port}")
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="DNS-UDP")

    def _handle_packet(data: bytes, addr: Tuple[str, int]):
        try:
            # Client IP multi-profile lookup (fallback to default 'a1b2c3')
            profile_id = db.get_profile_by_linked_ip(addr[0]) or 'a1b2c3'
            reply_bytes, _ = resolver.resolve_wire_packet(data, profile_id, addr[0])
            if reply_bytes:
                sock.sendto(reply_bytes, addr)
        except Exception:
            pass

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            pool.submit(_handle_packet, data, addr)
        except Exception:
            pass

def start_http_api_server(host: str = '127.0.0.1', port: int = 8080):
    """Starts the multi-threaded HTTP REST API & DoH server on 127.0.0.1:8080."""
    server = ThreadedHTTPServer((host, port), FocusDNSApiHandler)
    print(f"🚀 FocusDNS REST API & DoH Server active on http://{host}:{port}")
    server.serve_forever()

def start_https_api_server(host: str = '127.0.0.1', port: int = 8443):
    """Starts the multi-threaded HTTPS REST API & DoH server on 127.0.0.1:8443."""
    cert_path = os.path.join(os.path.dirname(__file__), 'certs', 'focus_dns.crt')
    key_path = os.path.join(os.path.dirname(__file__), 'certs', 'focus_dns.key')
    if not (os.path.exists(cert_path) and os.path.exists(key_path)):
        return
    try:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert_path, key_path)
        server = ThreadedHTTPSServer((host, port), FocusDNSApiHandler, ssl_context=context)
        print(f"🔒 FocusDNS HTTPS REST API & DoH Server active on https://{host}:{port}")
        server.serve_forever()
    except Exception as e:
        print(f"⚠️ Could not start HTTPS DoH server on {host}:{port}: {e}")

def main():
    # Default to 0.0.0.0 to enable LAN multi-device protection (other laptops, phones)
    host = os.environ.get('DNS_HOST', os.environ.get('FOCUS_DNS_HOST', '0.0.0.0'))
    http_port = int(os.environ.get('HTTP_PORT', os.environ.get('FOCUS_DNS_HTTP_PORT', '8080')))
    udp_port = int(os.environ.get('DNS_PORT', os.environ.get('FOCUS_DNS_UDP_PORT', '5354')))
    dot_port = int(os.environ.get('DOT_PORT', os.environ.get('FOCUS_DNS_DOT_PORT', '8853')))
    doq_port = int(os.environ.get('DOQ_PORT', os.environ.get('FOCUS_DNS_DOQ_PORT', '8854')))
    doh3_port = int(os.environ.get('DOH3_PORT', os.environ.get('FOCUS_DNS_DOH3_PORT', '8443')))

    print("=" * 60)
    print("      FOCUS-DNS HARDENED MULTI-PROTOCOL SERVER      ")
    print("=" * 60)

    # 1. Initialize SQLite Database & System Settings
    db.init_db()
    token = db.get_or_create_api_token()
    print("📦 SQLite Database initialized: server/focus_dns.db")
    print(f"🔑 API Security Token: {token[:8]}... (Auth Protected)")

    # 2. Start Background Log Purge Scheduler
    db.start_scheduled_purge(interval_seconds=3600)
    print("🧹 Background Log Retention Purge Scheduler started (Interval: 1h)")

    # 3. Launch Multi-Threaded UDP DNS Server (RFC 1035)
    udp_thread = threading.Thread(target=start_udp_dns_server, args=(host, udp_port), daemon=True)
    udp_thread.start()

    # 4. Launch RFC 7858 DNS-over-TLS (DoT) Server
    dot_thread = DotServerThread(
        host=host,
        port=dot_port,
        handler=lambda data, client_ip: resolver.resolve_wire_packet(data, 'a1b2c3', client_ip)
    )
    dot_thread.start()

    # 5. Launch RFC 9250 DNS-over-QUIC (DoQ) Server
    doq_thread = DoqServerThread(
        host=host,
        port=doq_port,
        handler=lambda data, client_ip: resolver.resolve_wire_packet(data, 'a1b2c3', client_ip)
    )
    doq_thread.start()

    https_port = int(os.environ.get('HTTPS_PORT', os.environ.get('FOCUS_DNS_HTTPS_PORT', '8443')))

    # 6. Launch RFC 9114 / RFC 8484 DNS-over-HTTP/3 (DoH3) Server
    doh3_thread = Doh3ServerThread(
        host=host,
        port=doh3_port,
        handler=lambda data, client_ip: resolver.resolve_wire_packet(data, 'a1b2c3', client_ip)
    )
    doh3_thread.start()

    # 6b. Launch HTTPS REST API & RFC 8484 DoH Server (Port 8443)
    https_thread = threading.Thread(target=start_https_api_server, args=(host, https_port), daemon=True)
    https_thread.start()

    # 7. Launch HTTP REST API & DoH Server
    try:
        start_http_api_server(host=host, port=http_port)
    except KeyboardInterrupt:
        print("\n🛑 Shutting down FocusDNS server gracefully...")
        dot_thread.stop()
        doq_thread.stop()
        doh3_thread.stop()


if __name__ == '__main__':
    main()
