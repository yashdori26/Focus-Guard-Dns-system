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
import threading
from typing import Tuple
from http.server import HTTPServer
from socketserver import ThreadingMixIn

from . import db
from . import resolver
from .api_router import FocusDNSApiHandler

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

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
            profile_id = 'a1b2c3'
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

def main():
    # Default to loopback for security. To bind to all LAN interfaces, explicitly set FOCUS_DNS_HOST=0.0.0.0
    host = os.environ.get('FOCUS_DNS_HOST', '127.0.0.1')
    http_port = int(os.environ.get('FOCUS_DNS_HTTP_PORT', '8080'))
    udp_port = int(os.environ.get('FOCUS_DNS_UDP_PORT', '5354'))

    print("=" * 60)
    print("      FOCUS-DNS HARDENED BACKEND & DOH SERVER      ")
    print("=" * 60)

    # 1. Initialize SQLite Database & System Settings
    db.init_db()
    token = db.get_or_create_api_token()
    print("📦 SQLite Database initialized: server/focus_dns.db")
    print(f"🔑 API Security Token: {token[:8]}... (Auth Protected)")

    # 2. Start Background Log Purge Scheduler
    db.start_scheduled_purge(interval_seconds=3600)
    print("🧹 Background Log Retention Purge Scheduler started (Interval: 1h)")

    # 3. Launch Multi-Threaded UDP DNS Server
    udp_thread = threading.Thread(target=start_udp_dns_server, args=(host, udp_port), daemon=True)
    udp_thread.start()

    # 4. Launch HTTP REST API & DoH Server
    try:
        start_http_api_server(host=host, port=http_port)
    except KeyboardInterrupt:
        print("\n🛑 Shutting down FocusDNS server gracefully...")

if __name__ == '__main__':
    main()
