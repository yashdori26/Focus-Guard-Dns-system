"""
FocusDNS GeoIP & Phone Country Discovery Engine
================================================
Provides client IP geolocation, ISO-3166 country detection,
Unicode flag rendering, and international dialing codes.
"""

import json
import logging
import time
import urllib.request
from typing import Dict, Any, List, Optional

from .engine.geodns_data import GLOBAL_COUNTRY_DATABASE

logger = logging.getLogger("focus_dns.geo_ip")

# Country alpha2 to international calling dial code
DIAL_CODES: Dict[str, str] = {
    "AF": "+93", "AL": "+355", "DZ": "+213", "AD": "+376", "AO": "+244",
    "AR": "+54", "AM": "+374", "AU": "+61", "AT": "+43", "AZ": "+994",
    "BH": "+973", "BD": "+880", "BY": "+375", "BE": "+32", "BZ": "+501",
    "BJ": "+229", "BT": "+975", "BO": "+591", "BA": "+387", "BW": "+267",
    "BR": "+55", "BN": "+673", "BG": "+359", "BF": "+226", "BI": "+257",
    "KH": "+855", "CM": "+237", "CA": "+1", "CL": "+56", "CN": "+86",
    "CO": "+57", "CR": "+506", "HR": "+385", "CU": "+53", "CY": "+357",
    "CZ": "+420", "DK": "+45", "DO": "+1", "EC": "+593", "EG": "+20",
    "SV": "+503", "EE": "+372", "ET": "+251", "FI": "+358", "FR": "+33",
    "GE": "+995", "DE": "+49", "GH": "+233", "GR": "+30", "GT": "+502",
    "HK": "+852", "HU": "+36", "IS": "+354", "IN": "+91", "ID": "+62",
    "IR": "+98", "IQ": "+964", "IE": "+353", "IL": "+972", "IT": "+39",
    "JM": "+1", "JP": "+81", "JO": "+962", "KZ": "+7", "KE": "+254",
    "KR": "+82", "KW": "+965", "LV": "+371", "LB": "+961", "LT": "+370",
    "LU": "+352", "MY": "+60", "MV": "+960", "MT": "+356", "MX": "+52",
    "MA": "+212", "NP": "+977", "NL": "+31", "NZ": "+64", "NG": "+234",
    "NO": "+47", "OM": "+968", "PK": "+92", "PA": "+507", "PE": "+51",
    "PH": "+63", "PL": "+48", "PT": "+351", "QA": "+974", "RO": "+40",
    "RU": "+7", "SA": "+966", "SG": "+65", "SK": "+421", "SI": "+386",
    "ZA": "+27", "ES": "+34", "LK": "+94", "SE": "+46", "CH": "+41",
    "TW": "+886", "TH": "+66", "TR": "+90", "UA": "+380", "AE": "+971",
    "GB": "+44", "US": "+1", "UY": "+598", "UZ": "+998", "VN": "+84",
}


def country_code_to_flag(code: str) -> str:
    """Converts a two-letter ISO country code into a Unicode flag emoji."""
    if not code or len(code) != 2:
        return "🌐"
    code = code.upper()
    if all('A' <= c <= 'Z' for c in code):
        return "".join(chr(0x1F1E6 + ord(c) - 65) for c in code)
    return "🌐"


_GEO_CACHE: Dict[str, Any] = {"data": None, "ts": 0.0}


def get_geo_info(client_ip: str, headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """
    Detects user's geographic location, country flag, and dialing code.
    Checks:
    1. Proxy/Cloudflare headers (CF-IPCountry, X-Country-Code)
    2. Accept-Language country hint
    3. Fast country detection API with caching
    4. Local environment timezone / system fallback
    """
    headers = headers or {}
    h_lower = {k.lower(): str(v) for k, v in headers.items()}
    cc = h_lower.get("cf-ipcountry") or h_lower.get("x-country-code")
    
    if not cc:
        accept_lang = h_lower.get("accept-language", "")
        for token in accept_lang.split(","):
            part = token.split(";")[0].strip()
            if "-" in part:
                candidate = part.split("-")[1].upper()
                if len(candidate) == 2 and candidate in DIAL_CODES:
                    cc = candidate
                    break

    now = time.time()
    if not cc and _GEO_CACHE["data"] and (now - _GEO_CACHE["ts"] < 3600):
        # Return cached result if available
        cached = dict(_GEO_CACHE["data"])
        cached["ip"] = client_ip
        return cached

    detected_ip = client_ip
    if not cc:
        try:
            req = urllib.request.Request("https://api.country.is/", headers={"User-Agent": "FocusDNS/2.0"})
            with urllib.request.urlopen(req, timeout=1.2) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                cc = data.get("country")
                if data.get("ip"):
                    detected_ip = data.get("ip")
        except Exception:
            pass

    if not cc:
        # Host timezone fallback
        tz = time.tzname[0].upper() if time.tzname else ""
        if "IST" in tz:
            cc = "IN"
        elif any(k in tz for k in ("PST", "EST", "CST", "MST")):
            cc = "US"
        elif "GMT" in tz or "BST" in tz:
            cc = "GB"
        elif "CET" in tz:
            cc = "DE"
        else:
            cc = "IN"

    cc = (cc or "IN").upper()
    flag = country_code_to_flag(cc)
    dial_code = DIAL_CODES.get(cc, "+1")

    country_profile = GLOBAL_COUNTRY_DATABASE.get(cc)
    country_name = country_profile.name if country_profile else cc

    result = {
        "ip": detected_ip,
        "country_code": cc,
        "dial_code": dial_code,
        "flag": flag,
        "country_name": country_name,
        "success": True,
        "timestamp": now,
    }

    _GEO_CACHE["data"] = result
    _GEO_CACHE["ts"] = now
    return result


def get_all_country_options() -> List[Dict[str, str]]:
    """Returns sorted list of all supported countries with dial codes and flags."""
    options = []
    for code, dial in DIAL_CODES.items():
        profile = GLOBAL_COUNTRY_DATABASE.get(code)
        name = profile.name if profile else code
        options.append({
            "country_code": code,
            "country_name": name,
            "dial_code": dial,
            "flag": country_code_to_flag(code),
        })
    options.sort(key=lambda x: x["country_name"])
    return options
