"""
FocusDNS Multi-Device Setup Portal & Client Installer Distributor
Renders responsive setup page for other laptops (Windows, macOS, Linux, Android)
and manages 1-click download packages.
"""

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def get_windows_setup_zip_path() -> str:
    return str(BASE_DIR / "setup" / "windows" / "focus_dns_windows_setup.zip")


def get_mac_profile_path() -> str:
    return str(BASE_DIR / "setup" / "mac" / "FocusDNS_Yash.mobileconfig")


def get_root_ca_path() -> str:
    return str(BASE_DIR / "server" / "certs" / "focus_dns.crt")


def get_linux_setup_path() -> str:
    return str(BASE_DIR / "setup" / "linux" / "setup_focus_dns.sh")


def render_setup_html(server_ip: str = "192.168.0.102", profile_id: str = "dce22d", profile_name: str = "Yash") -> str:
    doh_url = f"https://{server_ip}:8443/dns-query/{profile_id}"
    dot_endpoint = f"{server_ip}:8853"
    
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>FocusDNS Shield — Multi-Device Setup Portal</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    :root {{
      --bg: #0B0F19;
      --card-bg: #111827;
      --card-border: #1F2937;
      --primary: #38BDF8;
      --primary-hover: #0EA5E9;
      --accent: #10B981;
      --text: #F3F4F6;
      --text-muted: #9CA3AF;
      --code-bg: #030712;
    }}
    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }}
    body {{
      background: var(--bg);
      color: var(--text);
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      line-height: 1.6;
      padding: 2rem 1rem;
    }}
    .container {{
      max-width: 960px;
      margin: 0 auto;
    }}
    header {{
      text-align: center;
      margin-bottom: 2.5rem;
    }}
    .shield-badge {{
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      background: rgba(56, 189, 248, 0.1);
      border: 1px solid rgba(56, 189, 248, 0.3);
      color: var(--primary);
      padding: 0.35rem 0.9rem;
      border-radius: 9999px;
      font-size: 0.85rem;
      font-weight: 600;
      margin-bottom: 1rem;
    }}
    h1 {{
      font-size: 2.2rem;
      font-weight: 800;
      letter-spacing: -0.03em;
      margin-bottom: 0.5rem;
      background: linear-gradient(135deg, #FFFFFF 0%, #94A3B8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }}
    p.lead {{
      color: var(--text-muted);
      font-size: 1.1rem;
      max-width: 600px;
      margin: 0 auto;
    }}
    .status-banner {{
      background: rgba(16, 185, 129, 0.08);
      border: 1px solid rgba(16, 185, 129, 0.25);
      border-radius: 12px;
      padding: 1.25rem;
      margin-bottom: 2rem;
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
    }}
    .status-item {{
      display: flex;
      flex-direction: column;
    }}
    .status-label {{
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--text-muted);
    }}
    .status-val {{
      font-size: 1rem;
      font-weight: 700;
      color: #FFF;
      font-family: 'JetBrains Mono', monospace;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 1.5rem;
      margin-bottom: 2.5rem;
    }}
    .card {{
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 1.75rem;
      display: flex;
      flex-direction: column;
      transition: transform 0.2s, border-color 0.2s;
    }}
    .card:hover {{
      transform: translateY(-2px);
      border-color: rgba(56, 189, 248, 0.4);
    }}
    .card-icon {{
      font-size: 2rem;
      margin-bottom: 0.75rem;
    }}
    .card-title {{
      font-size: 1.25rem;
      font-weight: 700;
      margin-bottom: 0.5rem;
    }}
    .card-desc {{
      color: var(--text-muted);
      font-size: 0.9rem;
      margin-bottom: 1.25rem;
      flex-grow: 1;
    }}
    .steps {{
      background: var(--code-bg);
      border-radius: 8px;
      padding: 0.75rem 1rem;
      font-size: 0.85rem;
      color: #E2E8F0;
      margin-bottom: 1.25rem;
    }}
    .steps ol {{
      padding-left: 1.2rem;
    }}
    .steps li {{
      margin-bottom: 0.35rem;
    }}
    .btn {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
      padding: 0.75rem 1.25rem;
      border-radius: 10px;
      font-weight: 600;
      font-size: 0.95rem;
      text-decoration: none;
      cursor: pointer;
      border: none;
      transition: background 0.15s, opacity 0.15s;
    }}
    .btn-primary {{
      background: var(--primary);
      color: #030712;
    }}
    .btn-primary:hover {{
      background: var(--primary-hover);
    }}
    .btn-apple {{
      background: #FFFFFF;
      color: #000000;
    }}
    .btn-apple:hover {{
      background: #E2E8F0;
    }}
    .btn-secondary {{
      background: #1F2937;
      color: #F3F4F6;
      border: 1px solid #374151;
    }}
    .btn-secondary:hover {{
      background: #374151;
    }}
    .code-box {{
      background: var(--code-bg);
      border: 1px solid #1E293B;
      border-radius: 8px;
      padding: 0.6rem 0.8rem;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.8rem;
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 1rem;
      color: #38BDF8;
      overflow-x: auto;
    }}
    .copy-btn {{
      background: #1E293B;
      color: #F3F4F6;
      border: 1px solid #334155;
      padding: 0.25rem 0.6rem;
      border-radius: 6px;
      font-size: 0.75rem;
      cursor: pointer;
      flex-shrink: 0;
      margin-left: 0.5rem;
    }}
    .copy-btn:hover {{
      background: #334155;
    }}
    .guarantee-box {{
      background: rgba(56, 189, 248, 0.05);
      border: 1px solid rgba(56, 189, 248, 0.2);
      border-radius: 14px;
      padding: 1.5rem;
      display: flex;
      gap: 1rem;
      align-items: flex-start;
    }}
    .guarantee-icon {{
      font-size: 1.8rem;
    }}
    .guarantee-text h4 {{
      font-size: 1.05rem;
      color: #FFF;
      margin-bottom: 0.35rem;
    }}
    .guarantee-text p {{
      color: var(--text-muted);
      font-size: 0.9rem;
    }}
    footer {{
      margin-top: 3rem;
      text-align: center;
      color: #4B5563;
      font-size: 0.85rem;
    }}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="shield-badge">🛡️ FocusDNS Security Engine Active</div>
      <h1>Multi-Device Setup Portal</h1>
      <p class="lead">Protect family laptops, second computers, and phones with 1-click system-wide shields.</p>
    </header>

    <div class="status-banner">
      <div class="status-item">
        <span class="status-label">Active Profile</span>
        <span class="status-val">{profile_name} ({profile_id})</span>
      </div>
      <div class="status-item">
        <span class="status-label">Server LAN IP</span>
        <span class="status-val">{server_ip}</span>
      </div>
      <div class="status-item">
        <span class="status-label">Encrypted DoH URL</span>
        <span class="status-val">{doh_url}</span>
      </div>
      <div class="status-item">
        <span class="status-label">Status</span>
        <span class="status-val" style="color: #10B981;">● Online & Shielding</span>
      </div>
    </div>

    <div class="grid">
      <!-- Android Card -->
      <div class="card" style="border-color: rgba(16, 185, 129, 0.4);">
        <div class="card-icon">📱</div>
        <h2 class="card-title">Android Phone / Tablet</h2>
        <p class="card-desc">Native FocusDNS Android App with on-device DNS VPN engine. Intercepts and shields every browser (Chrome, Brave, Samsung Internet) and native apps automatically.</p>
        <div class="steps">
          <ol>
            <li>Tap below to download <strong>FocusDNS.apk</strong>.</li>
            <li>Install & open the app.</li>
            <li>Sign in: <code>yashdori26@gmail.com</code> / <code>YashDori</code> and tap <strong>Protect</strong>!</li>
          </ol>
        </div>
        <a href="/focusdns.apk" class="btn" style="background: #10B981; color: #030712; font-weight: 700;">
          ⬇️ Download Android App (.apk)
        </a>
      </div>

      <!-- Windows Card -->
      <div class="card">
        <div class="card-icon">🪟</div>
        <h2 class="card-title">Windows 11 / 10 Laptop</h2>
        <p class="card-desc">1-Click batch installer that configures Windows DoH, installs the Root CA, and enforces anti-tamper policies on Chrome, Edge, and Brave.</p>
        <div class="steps">
          <ol>
            <li>Download and extract the <strong>.zip</strong> package.</li>
            <li>Right-click <code>setup_focus_dns.bat</code> & select <strong>"Run as administrator"</strong>.</li>
            <li>All browsers & apps are protected system-wide!</li>
          </ol>
        </div>
        <a href="/api/download/windows-setup" class="btn btn-primary">
          ⬇️ Download Windows Setup (.zip)
        </a>
      </div>

      <!-- iPhone / iPad Card -->
      <div class="card" style="border-color: rgba(56, 189, 248, 0.4);">
        <div class="card-icon">🍎</div>
        <h2 class="card-title">iPhone / iPad (iOS)</h2>
        <p class="card-desc">Zero-App Apple Encrypted DNS Profile. Shields Safari, Chrome, YouTube, Instagram, and all apps system-wide across both <strong>Wi-Fi &amp; Cellular 4G/5G</strong>.</p>
        <div class="steps">
          <ol>
            <li>Open this page in <strong>Safari</strong> on iPhone and tap below.</li>
            <li>Tap <strong>Allow</strong> when prompted to download.</li>
            <li>Open iPhone <strong>Settings → Profile Downloaded → Install</strong>!</li>
          </ol>
          <div style="margin-top: 0.6rem; padding: 0.5rem 0.75rem; background: rgba(59, 130, 246, 0.1); border: 1px solid rgba(59, 130, 246, 0.3); border-radius: 8px; font-size: 0.8rem; color: #93C5FD;">
            🔒 <strong>Dynamic Removal Passcode:</strong> Generated dynamically per device or customized via <code>?passcode=YOUR_PIN</code> to protect profile from unauthorized removal.
          </div>
        </div>
        <a href="/apple.mobileconfig?profile_id={profile_id}" class="btn btn-apple" style="font-weight: 700; margin-top: 0.8rem;">
          📲 Download iOS Profile (.mobileconfig)
        </a>
      </div>

      <!-- Mac Card -->
      <div class="card">
        <div class="card-icon">💻</div>
        <h2 class="card-title">Apple Mac (macOS)</h2>
        <p class="card-desc">Apple native Encrypted DNS Profile with embedded Root CA for seamless 1-click installation in macOS System Settings.</p>
        <div class="steps">
          <ol>
            <li>Download the <code>.mobileconfig</code> profile.</li>
            <li>Double-click the file &amp; open <strong>System Settings → Profiles</strong>.</li>
            <li>Click <strong>Install</strong> and enter your Mac passcode.</li>
          </ol>
        </div>
        <a href="/api/download/mac-profile" class="btn btn-secondary">
          ⬇️ Download macOS Profile (.mobileconfig)
        </a>
      </div>

      <!-- Linux Card -->
      <div class="card">
        <div class="card-icon">🐧</div>
        <h2 class="card-title">Linux Laptop</h2>
        <p class="card-desc">One-line terminal command configuring <code>systemd-resolved</code>, system CA trust anchors, and Chromium enterprise policies.</p>
        <div class="code-box">
          <span id="linuxCmd">curl -sSL http://{server_ip}:8080/api/download/linux-setup | sudo bash</span>
          <button class="copy-btn" onclick="copyText('linuxCmd')">Copy</button>
        </div>
        <a href="/api/download/root-ca" class="btn btn-secondary">
          📜 Download Root CA (focus_dns.crt)
        </a>
      </div>
    </div>

    <div class="guarantee-box">
      <div class="guarantee-icon">⚡</div>
      <div class="guarantee-text">
        <h4>Zero Internet Interruption Guarantee</h4>
        <p>Normal websites (Google, Wikipedia, Steam, Microsoft updates, online banking) resolve at maximum speed via Cloudflare (<code>1.1.1.1</code>) and Google DNS (<code>8.8.8.8</code>). If this host computer is ever powered off or sleeping, client laptops automatically fall back to standard DNS so you are never left without an internet connection.</p>
      </div>
    </div>

    <footer>
      FocusDNS Multi-Protocol Shield Engine &bull; Profile: {profile_name} ({profile_id}) &bull; Active on {server_ip}
    </footer>
  </div>

  <script>
    function copyText(elemId) {{
      const text = document.getElementById(elemId).innerText;
      navigator.clipboard.writeText(text).then(() => {{
        alert("Command copied to clipboard!");
      }});
    }}
  </script>
</body>
</html>"""
