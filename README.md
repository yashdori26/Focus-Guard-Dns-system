# focus-dns (2): UI + fully local backend (no server)

Run once:  ./apply_native.sh   (needs Flutter; generates the Android project, then copies the native code in)
Then:      flutter run

Native (Kotlin, android/app/src/main): local SQLite DB, DNS-only VPN (blocked names -> NXDOMAIN, rest forwarded to 1.1.1.1/8.8.8.8/9.9.9.9),
bundled blocklists (porn/gambling/social) + keyword heuristics, Accessibility service (app blocking, Reels/Shorts), strict-mode timer, boot restart.
On the phone: allow VPN, enable the FocusDNS accessibility service, set Private DNS to Off, turn off Chrome Secure DNS.
