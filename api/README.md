# FocusDNS Cloud API & Analytics (`/api`)

Production-grade, high-throughput backend service written in Go 1.22+ for FocusDNS, backed by PostgreSQL 16 and Redis 7.

## Architecture Overview

```
                      +-----------------------------------+
                      |   Client Engines (Android / iOS)  |
                      |   Browser Extension / Web Admin   |
                      +-----------------+-----------------+
                                        |
     +----------------------------------+----------------------------------+
     |                                  |                                  |
     v                                  v                                  v
+------------------------+  +------------------------+  +------------------------+
| Auth Service           |  | RFC 8484 DoH Handler   |  | Session Sync Service   |
| - Argon2id Password    |  | - DNS Wire Parser      |  | - Absolute Timelines   |
| - RFC 6238 TOTP 2FA    |  | - In-Memory Blocklist  |  | - Option B Lockout     |
| - Ed25519 Device Bind  |  | - NXDOMAIN (RCODE 3)   |  | - Event Journal        |
+-----------+------------+  +-----------+------------+  +-----------+------------+
            |                           |                           |
            +---------------------------+---------------------------+
                                        |
                                        v
     +----------------------------------+----------------------------------+
     |                                  |                                  |
     v                                  v                                  v
+------------------------+  +------------------------+  +------------------------+
| Privacy Analytics      |  | Ed25519 Rule CDN       |  | Realtime WS Hub        |
| - Hourly Rollups       |  | - Signed Delta Packs   |  | - Phase Transitions    |
| - ZERO Domain Logs     |  | - Emergency Killswitch |  | - Lockout Broadcasts   |
+-----------+------------+  +-----------+------------+  +-----------+------------+
            |                           |                           |
            v                           v                           v
+--------------------------------------------------------------------------------+
| Storage Layer: PostgreSQL 16 (Relational DDL) + Redis 7 (In-Memory Pub/Sub)    |
+--------------------------------------------------------------------------------+
```

## Key Capabilities & Confirmed Decisions

1. **Authentication (Option C)**:
   - **Argon2id**: Memory: 64MB, Iterations: 3, Parallelism: 4 threads, Salt: 16 bytes. Constant-time timing-attack safe comparison.
   - **TOTP 2FA (RFC 6238)**: 30-second time interval, 6-digit codes, $\pm 1$ interval clock drift tolerance. Standard `otpauth://` QR URI generation.
   - **Device Binding**: Hardware-backed Ed25519 challenge-response handshake preventing credential replaying across unauthorized devices.

2. **Privacy-First Hourly Analytics (Option A)**:
   - **Zero Domain Logging**: The database schema strictly forbids saving raw URLs, FQDNs, or domain names.
   - Stores aggregated count buckets (`hour_bucket_epoch_ms`, `category`, `total_queries`, `blocked_queries`, `allowed_queries`).
   - Retained at 1-hour resolution for 30 days, aggregated to 2-year monthly rollups.

3. **Session Synchronization & Option B Ironclad Lockout**:
   - Synchronizes precomputed absolute timelines (`[PhaseInterval]`) and append-only event journals.
   - Rejects abort or premature termination requests when strict mode is active (`ERR_STRICT_LOCKOUT_ACTIVE`).

4. **Dynamic Rule Pack Delivery (Option A)**:
   - Signs delta rule packs using master Ed25519 private keys.
   - Embeds emergency kill-switch flag to revert clients to base safety rules immediately if an error occurs.

5. **DNS-over-HTTPS (RFC 8484)**:
   - Accepts wire-format DNS packets via POST and GET (`application/dns-message`).
   - Synthesizes instant RFC 1035 NXDOMAIN (0x8183) for denied domains.
   - Forwards allowed lookups upstream.

6. **Realtime WebSocket Hub**:
   - Manages user sessions, broadcasting phase transitions and lockout alerts to mobile, extension, and web clients.

## Deployment & Verification

### Running with Docker Compose
```bash
cd api
docker-compose up -d
```
Spins up PostgreSQL 16 on `:5432`, Redis 7 on `:6379`, and the compiled FocusDNS API service on `:8080`.

### Automated Verification
```bash
python3 api/verify_api.py
```
Validates source integrity, Argon2id parameters, RFC 6238 TOTP math, Ed25519 signatures, zero-domain schema privacy, and runs all 10 shared state machine vectors (42 assertions).
