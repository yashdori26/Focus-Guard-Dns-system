"""
FocusDNS Outbound Email Dispatcher (SMTP - Option 1B)
Delivers real 4-digit verification codes and security alerts via standard SMTP.
Supports STARTTLS (port 587) and SSL (port 465) with Gmail, SendGrid, Amazon SES, or custom SMTP servers.
Configuration is resolved dynamically from environment variables or SQLite system_settings.
"""

import logging
import os
import smtplib
import ssl
from email.header import Header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Dict, Any, Tuple, Optional

from . import db

logger = logging.getLogger("focus_dns.email_service")


def get_active_smtp_config() -> Dict[str, Any]:
    """
    Resolves SMTP configuration.
    Environment variables take precedence over SQLite system_settings.
    """
    db_cfg = db.get_smtp_config()

    host = os.environ.get("SMTP_HOST", db_cfg.get("host", "")).strip()
    port_env = os.environ.get("SMTP_PORT")
    port = int(port_env) if port_env and port_env.isdigit() else db_cfg.get("port", 587)
    user = os.environ.get("SMTP_USER", db_cfg.get("user", "")).strip()
    password = os.environ.get("SMTP_PASS", db_cfg.get("pass", "")).strip()
    sender = os.environ.get("SMTP_FROM", db_cfg.get("from", "FocusDNS Security <noreply@focusdns.net>")).strip()
    
    use_tls_env = os.environ.get("SMTP_USE_TLS")
    use_tls = use_tls_env.lower() in ("1", "true", "yes") if use_tls_env else db_cfg.get("use_tls", True)

    use_ssl_env = os.environ.get("SMTP_USE_SSL")
    use_ssl = use_ssl_env.lower() in ("1", "true", "yes") if use_ssl_env else db_cfg.get("use_ssl", False)

    enabled = bool(host and (db_cfg.get("enabled") or bool(host)))

    return {
        "host": host,
        "port": port,
        "user": user,
        "pass": password,
        "from": sender,
        "use_tls": use_tls,
        "use_ssl": use_ssl,
        "enabled": enabled,
    }


def is_smtp_configured() -> bool:
    """Checks if the minimum required SMTP parameters are present."""
    cfg = get_active_smtp_config()
    return bool(cfg["host"] and cfg["port"])


def build_verification_email_html(code: str, profile_name: str = "") -> str:
    """Builds a high-polish, dark-themed responsive HTML email for FocusDNS verification."""
    display_name = profile_name.strip() if profile_name.strip() else "FocusDNS User"
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your FocusDNS Verification Code</title>
  <style>
    body {{
      margin: 0;
      padding: 0;
      background-color: #0b0f19;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      color: #e2e8f0;
    }}
    .email-container {{
      max-width: 540px;
      margin: 40px auto;
      background: #111827;
      border: 1px solid #1f2937;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.5);
    }}
    .header {{
      background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%);
      padding: 32px 24px;
      text-align: center;
    }}
    .shield-icon {{
      font-size: 42px;
      margin-bottom: 8px;
    }}
    .brand-title {{
      color: #ffffff;
      font-size: 22px;
      font-weight: 800;
      letter-spacing: -0.5px;
      margin: 0;
    }}
    .brand-subtitle {{
      color: #bfdbfe;
      font-size: 13px;
      margin-top: 4px;
      text-transform: uppercase;
      letter-spacing: 1px;
    }}
    .content {{
      padding: 36px 32px;
      text-align: center;
    }}
    .greeting {{
      font-size: 18px;
      font-weight: 600;
      color: #f8fafc;
      margin-bottom: 12px;
    }}
    .instructions {{
      font-size: 14px;
      color: #94a3b8;
      line-height: 1.6;
      margin-bottom: 28px;
    }}
    .code-box {{
      background: #1e293b;
      border: 2px dashed #3b82f6;
      border-radius: 12px;
      padding: 20px 24px;
      display: inline-block;
      margin: 0 auto 28px auto;
    }}
    .code-text {{
      font-family: 'Courier New', Courier, monospace;
      font-size: 38px;
      font-weight: 800;
      letter-spacing: 12px;
      color: #60a5fa;
      margin-left: 12px;
    }}
    .expiry-badge {{
      display: inline-block;
      background: rgba(239, 68, 68, 0.15);
      color: #f87171;
      font-size: 12px;
      font-weight: 600;
      padding: 6px 14px;
      border-radius: 9999px;
      border: 1px solid rgba(239, 68, 68, 0.3);
      margin-bottom: 24px;
    }}
    .warning {{
      font-size: 12px;
      color: #64748b;
      line-height: 1.5;
      border-top: 1px solid #1f2937;
      padding-top: 20px;
    }}
    .footer {{
      background: #0d131f;
      padding: 18px;
      text-align: center;
      font-size: 11px;
      color: #475569;
      border-top: 1px solid #1a2234;
    }}
  </style>
</head>
<body>
  <div class="email-container">
    <div class="header">
      <div class="shield-icon">🛡️</div>
      <h1 class="brand-title">FocusDNS Security</h1>
      <div class="brand-subtitle">Private DNS &amp; Threat Defense</div>
    </div>
    <div class="content">
      <div class="greeting">Hello {display_name},</div>
      <div class="instructions">
        Use the 4-digit verification code below to verify your email address and link your FocusDNS profile.
      </div>
      <div class="code-box">
        <div class="code-text">{code}</div>
      </div>
      <div>
        <span class="expiry-badge">⏱ Expires in 15 minutes</span>
      </div>
      <div class="warning">
        If you did not request this verification code, you can safely ignore this email. No changes will be made to your FocusDNS account without this code.
      </div>
    </div>
    <div class="footer">
      FocusDNS Daemon Engine &bull; Zero-Leak Regional Defense &bull; Universal App Blocker
    </div>
  </div>
</body>
</html>"""


def send_verification_email(to_email: str, code: str, profile_name: str = "") -> Tuple[bool, str]:
    """
    Dispatches a verification code email to `to_email` using real SMTP.
    Returns (True, success_message) or (False, error_message).
    """
    clean_email = to_email.strip().lower()
    if not clean_email or "@" not in clean_email:
        return False, "Invalid destination email address."

    cfg = get_active_smtp_config()
    host = cfg["host"]
    port = cfg["port"]
    user = cfg["user"]
    password = cfg["pass"]
    sender = cfg["from"]
    use_tls = cfg["use_tls"]
    use_ssl = cfg["use_ssl"]

    if not host:
        logger.warning(
            f"SMTP dispatch skipped for {clean_email}: SMTP_HOST not configured. "
            f"Generated code is {code}."
        )
        return False, (
            "SMTP server is not configured. Please set SMTP_HOST, SMTP_PORT, "
            "SMTP_USER, and SMTP_PASS in environment variables or via admin settings."
        )

    # Construct Email Message
    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"{code} is your FocusDNS verification code"
    msg["From"] = sender
    msg["To"] = clean_email

    # Plain text version
    text_content = (
        f"FocusDNS Security Verification\n\n"
        f"Your 4-digit verification code is: {code}\n\n"
        f"This code will expire in 15 minutes.\n"
        f"If you did not request this verification, please disregard this email."
    )
    part_text = MIMEText(text_content, "plain", "utf-8")
    msg.attach(part_text)

    # HTML version
    html_content = build_verification_email_html(code, profile_name)
    part_html = MIMEText(html_content, "html", "utf-8")
    msg.attach(part_html)

    # Deliver via SMTP
    try:
        if use_ssl or port == 465:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(host, port, context=context, timeout=12) as server:
                if user and password:
                    server.login(user, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=12) as server:
                server.ehlo()
                if use_tls or port == 587:
                    context = ssl.create_default_context()
                    server.starttls(context=context)
                    server.ehlo()
                if user and password:
                    server.login(user, password)
                server.send_message(msg)

        logger.info(f"Successfully sent verification email to {clean_email} via SMTP ({host}:{port})")
        return True, f"Verification code sent to {clean_email}"

    except smtplib.SMTPAuthenticationError as e:
        err_msg = f"SMTP Authentication failed for user '{user}': check username and password/app-password."
        logger.error(f"{err_msg} Details: {e}")
        return False, err_msg
    except smtplib.SMTPConnectError as e:
        err_msg = f"Failed to connect to SMTP server at {host}:{port}. Details: {e}"
        logger.error(err_msg)
        return False, err_msg
    except smtplib.SMTPServerDisconnected as e:
        err_msg = f"SMTP server disconnected prematurely ({host}:{port}). Details: {e}"
        logger.error(err_msg)
        return False, err_msg
    except Exception as e:
        err_msg = f"SMTP delivery error to {clean_email}: {str(e)}"
        logger.error(err_msg)
        return False, err_msg


def test_smtp_connection(custom_config: Optional[Dict[str, Any]] = None) -> Tuple[bool, str]:
    """Tests the SMTP connection and authentication with the given or active config."""
    cfg = custom_config or get_active_smtp_config()
    host = cfg.get("host", "").strip()
    port = int(cfg.get("port", 587))
    user = cfg.get("user", "").strip()
    password = cfg.get("pass", "").strip()
    use_tls = cfg.get("use_tls", True)
    use_ssl = cfg.get("use_ssl", False)

    if not host:
        return False, "SMTP Host is required"

    try:
        if use_ssl or port == 465:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(host, port, context=context, timeout=8) as server:
                if user and password:
                    server.login(user, password)
        else:
            with smtplib.SMTP(host, port, timeout=8) as server:
                server.ehlo()
                if use_tls or port == 587:
                    context = ssl.create_default_context()
                    server.starttls(context=context)
                    server.ehlo()
                if user and password:
                    server.login(user, password)

        return True, f"Successfully connected to SMTP server at {host}:{port}"
    except smtplib.SMTPAuthenticationError as e:
        return False, f"SMTP Authentication failed: {e}"
    except Exception as e:
        return False, f"SMTP Connection failed: {e}"
