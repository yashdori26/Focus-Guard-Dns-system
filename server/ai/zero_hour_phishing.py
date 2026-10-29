"""
FocusDNS AI Engine - Zero-Hour Phishing & Brand Impersonation Detector.

Analyzes domain names in real-time to detect zero-day phishing portals,
credential harvesters, and deceptive subdomain brand impersonation
before threats are indexed by conventional threat intelligence feeds.

Key Capabilities:
  1. Subdomain Brand Impersonation: Detects brand tokens embedded in deep subdomains
     (e.g., 'paypal.com.verify-account.security-update.xyz').
  2. Deceptive Keyword Chaining: Analyzes multi-token credential harvesting patterns
     ('login', 'security', 'verify', 'update', 'banking', 'wallet').
  3. Structural Shannon Entropy & Lexical Depth Analysis.
  4. High-Abuse TLD Risk Weighting.
  5. Life Safety Exemption: Emergency calling, DHCP, Apple APNs, and system update
     domains are permanently hardcoded exempt from phishing verdicts.
"""

import math
import collections
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.brand_dictionary import BrandDictionary, BrandProfile, DECEPTIVE_KEYWORDS


# High-Abuse TLDs frequently utilized by ephemeral zero-hour phishing kits
HIGH_ABUSE_TLDS: Dict[str, float] = {
    "xyz": 1.4, "top": 1.5, "buzz": 1.5, "click": 1.4, "rest": 1.4,
    "monster": 1.4, "cfd": 1.5, "sbs": 1.5, "icu": 1.5, "fun": 1.3,
    "work": 1.3, "loan": 1.5, "men": 1.5, "stream": 1.4, "gq": 1.5,
    "cf": 1.5, "ml": 1.5, "ga": 1.5, "tk": 1.5, "live": 1.2, "club": 1.2
}

# Life Safety and Core System Update Domains (Hardcoded Exemption)
LIFE_SAFETY_EXEMPTIONS: Set[str] = {
    "emergency.gov", "911.gov", "112.gov",
    "push.apple.com", "swscan.apple.com", "mesu.apple.com", "gateway.push.apple.com",
    "update.microsoft.com", "windowsupdate.com", "download.windowsupdate.com",
    "play.googleapis.com", "android.clients.google.com", "connectivitycheck.gstatic.com"
}


class PhishingVerdict:
    """Structured result returned by the Zero-Hour Phishing Detector."""
    __slots__ = (
        "is_phishing", "phishing_score", "targeted_brand", "deceptive_keywords",
        "risk_level", "indicators", "original_domain", "explanation"
    )

    def __init__(
        self,
        is_phishing: bool,
        phishing_score: float,
        targeted_brand: Optional[str],
        deceptive_keywords: List[str],
        risk_level: str,
        indicators: List[str],
        original_domain: str,
        explanation: str
    ):
        self.is_phishing = is_phishing
        self.phishing_score = round(min(100.0, max(0.0, phishing_score)), 2)
        self.targeted_brand = targeted_brand
        self.deceptive_keywords = deceptive_keywords
        self.risk_level = risk_level
        self.indicators = indicators
        self.original_domain = original_domain
        self.explanation = explanation

    @property
    def spoofed_brand(self) -> Optional[str]:
        return self.targeted_brand

    @property
    def primary_threat_vector(self) -> str:
        return self.explanation

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_phishing": self.is_phishing,
            "phishing_score": self.phishing_score,
            "targeted_brand": self.targeted_brand,
            "deceptive_keywords": self.deceptive_keywords,
            "risk_level": self.risk_level,
            "indicators": self.indicators,
            "original_domain": self.original_domain,
            "explanation": self.explanation
        }


class ZeroHourPhishingDetector:
    """
    On-device lexical and structural zero-hour phishing detection engine.
    """

    @staticmethod
    def calculate_entropy(text: str) -> float:
        """Computes mathematical Shannon Entropy: -sum(p * log2(p))."""
        if not text:
            return 0.0
        counts = collections.Counter(text)
        length = len(text)
        return -sum((c / length) * math.log2(c / length) for c in counts.values())

    @classmethod
    def is_life_safety_exempt(cls, domain: str) -> bool:
        """Verifies if domain belongs to exempt emergency or OS update infrastructure."""
        clean = domain.lower().strip()
        for exempt in LIFE_SAFETY_EXEMPTIONS:
            if clean == exempt or clean.endswith("." + exempt):
                return True
        return False

    @classmethod
    def parse_domain_parts(cls, domain: str) -> Tuple[str, str, List[str]]:
        """
        Splits domain into (apex_domain, tld, subdomains).
        Example: 'login.paypal.com.verify.xyz' -> apex: 'verify.xyz', tld: 'xyz', subdomains: ['login', 'paypal', 'com']
        """
        parts = domain.lower().strip().split(".")
        if len(parts) <= 2:
            apex = ".".join(parts)
            tld = parts[-1] if parts else ""
            return apex, tld, []

        tld = parts[-1]
        apex = ".".join(parts[-2:])
        subdomains = parts[:-2]
        return apex, tld, subdomains

    @classmethod
    def analyze_domain(cls, domain: str) -> PhishingVerdict:
        """
        Executes zero-hour phishing inspection combining brand impersonation,
        deceptive keywords, entropy, subdomain depth, and TLD abuse multipliers.
        """
        clean_domain = domain.lower().strip().rstrip(".")

        # 1. Life Safety Exemption Check
        if cls.is_life_safety_exempt(clean_domain):
            return PhishingVerdict(
                is_phishing=False,
                phishing_score=0.0,
                targeted_brand=None,
                deceptive_keywords=[],
                risk_level="CLEAN_EXEMPT",
                indicators=["LIFE_SAFETY_EXEMPTION_ACTIVE"],
                original_domain=domain,
                explanation="Domain belongs to verified emergency calling or critical OS update infrastructure."
            )

        apex, tld, subdomains = cls.parse_domain_parts(clean_domain)
        indicators: List[str] = []
        raw_score = 0.0
        targeted_brand: Optional[str] = None

        # 2. Extract deceptive keywords
        keywords = BrandDictionary.extract_deceptive_keywords(clean_domain)
        if keywords:
            kw_points = min(40.0, len(keywords) * 14.0)
            raw_score += kw_points
            indicators.append(f"DECEPTIVE_KEYWORDS_PRESENT({','.join(keywords[:4])})")

        # 3. Subdomain Brand Impersonation Check
        # Check if a protected brand name exists anywhere in subdomains while apex is NOT legitimate
        for brand_name in BrandDictionary.get_all_brands():
            # Check if brand appears as a standalone subdomain token or hyphenated segment
            for sub in subdomains:
                sub_tokens = [t for t in "".join(c if c.isalnum() else " " for c in sub).split()]
                if brand_name in sub_tokens or sub == brand_name or sub == f"{brand_name}-security":
                    if not BrandDictionary.is_legitimate_brand_apex(apex, brand_name):
                        profile = BrandDictionary.find_matched_brand(brand_name)
                        targeted_brand = profile.brand_name if profile else brand_name
                        raw_score += 55.0
                        indicators.append(f"BRAND_IMPERSONATION_IN_SUBDOMAIN({targeted_brand}->{apex})")
                        break
            if targeted_brand:
                break

        # Check if brand is in the apex registered domain label alongside deceptive keywords
        # e.g. 'paypal-security-update.com'
        apex_label = apex.split(".")[0] if "." in apex else apex
        if not targeted_brand:
            for brand_name in BrandDictionary.get_all_brands():
                if brand_name in apex_label and not BrandDictionary.is_legitimate_brand_apex(apex, brand_name):
                    # Check if brand token is attached to deceptive keyword
                    if any(kw in apex_label for kw in keywords) or "-" in apex_label:
                        profile = BrandDictionary.find_matched_brand(brand_name)
                        targeted_brand = profile.brand_name if profile else brand_name
                        raw_score += 48.0
                        indicators.append(f"BRAND_DECEPTIVE_APEX_LABEL({targeted_brand} in {apex_label})")
                        break

        # If brand was legitimate apex, zero out brand impersonation
        if targeted_brand and BrandDictionary.is_legitimate_brand_apex(apex, targeted_brand):
            targeted_brand = None
            raw_score = max(0.0, raw_score - 50.0)

        # 4. Structural Lexical Heuristics
        # Subdomain depth: 3+ subdomains is rare for benign apex sites
        if len(subdomains) >= 3:
            raw_score += 15.0
            indicators.append(f"EXCESSIVE_SUBDOMAIN_DEPTH({len(subdomains)})")

        # Hyphen count: Phishing sites frequently use multiple hyphens
        hyphen_count = clean_domain.count("-")
        if hyphen_count >= 3:
            raw_score += 12.0
            indicators.append(f"HIGH_HYPHEN_COUNT({hyphen_count})")
        elif hyphen_count == 2:
            raw_score += 6.0

        # Digit count in domain
        digits = sum(1 for c in clean_domain if c.isdigit())
        if digits >= 5:
            raw_score += 10.0
            indicators.append(f"HIGH_DIGIT_DENSITY({digits})")

        # Shannon Entropy check on registered label
        entropy = cls.calculate_entropy(apex_label)
        if entropy > 3.8 and len(apex_label) >= 12:
            raw_score += 12.0
            indicators.append(f"HIGH_LEXICAL_ENTROPY({entropy:.2f})")

        # 5. TLD Risk Multiplier
        tld_mult = HIGH_ABUSE_TLDS.get(tld, 1.0)
        if tld_mult > 1.0 and raw_score > 15.0:
            raw_score = raw_score * tld_mult
            indicators.append(f"HIGH_ABUSE_TLD_WEIGHT({tld} x{tld_mult})")

        # 6. Final Score & Risk Level Classification
        final_score = min(100.0, max(0.0, raw_score))

        if final_score >= 75.0:
            risk_level = "CRITICAL_CREDENTIAL_HARVESTER" if targeted_brand else "HIGH_RISK_PHISHING"
            is_phishing = True
        elif final_score >= 50.0:
            risk_level = "SUSPICIOUS_PHISHING_CANDIDATE"
            is_phishing = True
        elif final_score >= 30.0:
            risk_level = "ELEVATED_RISK"
            is_phishing = False
        else:
            risk_level = "CLEAN"
            is_phishing = False

        if is_phishing:
            if targeted_brand:
                explanation = (
                    f"Identified zero-hour credential phishing portal targeting '{targeted_brand}' "
                    f"with confidence {final_score:.1f}/100. Triggers: {', '.join(indicators)}."
                )
            else:
                explanation = (
                    f"Identified suspicious deceptive domain with phishing confidence {final_score:.1f}/100. "
                    f"Triggers: {', '.join(indicators)}."
                )
        else:
            explanation = "Domain exhibits legitimate structural patterns with low phishing risk."

        return PhishingVerdict(
            is_phishing=is_phishing,
            phishing_score=final_score,
            targeted_brand=targeted_brand,
            deceptive_keywords=keywords,
            risk_level=risk_level,
            indicators=indicators,
            original_domain=domain,
            explanation=explanation
        )

    analyze = analyze_domain
