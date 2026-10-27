# 🛡️ FocusGuard DNS System (FocusDNS)

A high-performance, tamper-resistant, multi-platform DNS protection system combining a minimal **Wabi-Sabi Charcoal Flutter Client (Android / iOS)**, an RFC 8484 / RFC 1035 **Hardened Core DNS Engine (Python)**, and a zero-bloat browser-based **Operator Web Admin Portal**.

---

## 🏛️ System Architecture

```
                             ┌────────────────────────────────────────────────────────┐
                             │    FocusDNS Cloud / VPS Production (Caddy + Python)     │
                             │                                                        │
  1. Real Android Devices     │   ┌────────────────────────────────────────────────┐   │
 ┌───────────────────────┐   │   │  Core DNS Engine (DoH / UDP 53 / Resolver)     │   │
 │ FocusDNS Android App  │───┼──>│  • Local Tunnel / Profile Tokens (usr_xxx)     │   │
 │ (com.focusdns.app)    │   │   │  • RFC 8484 DNS-over-HTTPS (Wire & Base64url)  │   │
 └───────────────────────┘   │   │  • 273k+ Threat Intel Feed Signatures          │   │
                             │   │  • SafeSearch & YouTube Restricted Rewriting   │   │
  2. Zero-App Apple Devices  │   └────────────────────────────────────────────────┘   │
 ┌───────────────────────┐   │                           ▲                            │
 │ iOS / macOS Native    │───┼───────────────────────────┘                            │
 │ (.mobileconfig profile│   │                           │                            │
 └───────────────────────┘   │   ┌────────────────────────────────────────────────┐   │
                             │   │  FocusDNS Web Operator Portal (/admin)         │   │
  3. Web / Admin Browsers    │   │  • Real-Time Query Telescope (SSE Stream)      │   │
 ┌───────────────────────┐   │   │  • Zero-Restart Global Safe Bypass             │   │
 │ Operator Browser      │───┼──>│  • Upstream Benchmark & Fleet Provisioning     │   │
 └───────────────────────┘   │   └────────────────────────────────────────────────┘   │
                             └────────────────────────────────────────────────────────┘
```

---

## 🌟 Key Features

### 1. 📱 Mobile Client (Flutter & Android Engine)
- **Wabi-Sabi Charcoal Minimalist Design**: Designed in Charcoal Night (Dark) and Warm Stone Paper (Light).
- **Ironclad Timed Strict Mode**: Monotonic timer enforcement preventing pauses, disabling, or filter changes until countdown expiry.
- **Fail-Closed VPN Service**: Local Android loopback tunnel intercepting UDP port 53 and forwarding securely via encrypted RFC 8484 DoH.
- **Accessibility Shield (`FocusAccessibilityService`)**: Instant screen overlay blocking when restricted applications, third-party VPN apps, or Android Settings screens are opened.
- **Dynamic Server & Profile Connection Manager**: In-app latency prober (`PROBE` & `SAVE & CONNECT`), custom domain resolution, and 1-tap profile switching.

### 2. 🍏 Zero-App Apple Deployment (`.mobileconfig`)
- **NextDNS Parity**: Native Apple configuration profiles generated on-the-fly (`/api/profile/{id}/apple.mobileconfig`).
- **No Third-Party App Required**: Enrolls iPhones, iPads, and Macs natively using Apple's encrypted DNS configuration payload.

### 3. 🛡️ Core Resolver & Security Pipeline
- **Enforced SafeSearch**: Virtual IP rewriting for Google SafeSearch, YouTube Restricted Mode, Bing Strict, and DuckDuckGo Safe.
- **Automated Threat Intelligence**: In-memory compilation of 273,000+ signatures across AdGuard, StevenBlack, URLhaus, and NoCoin feeds.
- **DNS Rebinding & DoH Bypass Prevention**: Blocks private IP rebinding attacks and intercepts public DoH provider endpoints (Cloudflare, Quad9, Google DoH) to prevent browser circumvention.
- **RAM Cache**: Zero-millisecond (0ms) in-memory resolution with automatic cache invalidation.

### 4. 🏛️ FocusDNS Operator Web Admin Portal
- **Zero-Bloat Single-File Delivery**: Under 50 KB, pure HTML5/CSS3/Vanilla JS with zero Node.js/npm dependencies.
- **Real-Time Telescope**: Live SSE query stream (`/api/admin/stream`) with optional client IP masking.
- **Global Safe Bypass**: Emergency 100% pass-through `NOERROR` fail-safe switch.
- **Upstream Benchmark Engine**: Live round-trip latency benchmarking across Quad9, Cloudflare, and Google DNS.

---

## 🚀 Quick Start & Deployment

### Run via Docker Compose (Recommended)
```bash
# Clone the repository
git clone https://github.com/yashdori26/Focus-Guard-Dns-system.git
cd Focus-Guard-Dns-system

# Start backend DNS engine and Caddy HTTPS reverse proxy
docker compose up -d
```

### Run Locally (Development)
```bash
# Set up Python virtual environment
python3 -m venv server/venv
source server/venv/bin/activate
pip install -r server/requirements.txt

# Start backend server (UDP port 5354 & HTTP port 8080)
python -m server.dns_server
```

In a second terminal, launch the Flutter client:
```bash
flutter run
```

---

## 🧪 Verification & Automated Tests

```bash
# Run backend integration & protocol verification suite (19 test suites)
server/venv/bin/python -m server.tests.test_api

# Run operator admin portal verification suite (13 test suites)
server/venv/bin/python -m server.tests.test_admin

# Run Flutter widget & unit tests
flutter test

# Run Flutter static analyzer
flutter analyze
```

---

## 📄 License
This project is licensed under the MIT License.
