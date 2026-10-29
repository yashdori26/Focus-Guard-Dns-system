"""
FocusDNS AI Engine - Protected Brand Registry & Deceptive Lexicon.

Maintains high-value brand profiles vulnerable to homograph spoofing,
zero-hour phishing, and typosquatting attacks, along with deceptive keyword
lexicons commonly abused in social engineering campaigns.
"""

from typing import Dict, List, Set, Optional, Tuple, Any


class BrandProfile:
    """Represents a protected high-value brand identity."""
    __slots__ = ("name", "category", "risk_weight", "legitimate_domains", "aliases")

    def __init__(
        self,
        name: str,
        category: str,
        risk_weight: float,
        legitimate_domains: Set[str],
        aliases: Optional[Set[str]] = None
    ):
        self.name = name.lower()
        self.category = category.upper()
        self.risk_weight = min(1.0, max(0.1, risk_weight))
        self.legitimate_domains = {d.lower() for d in legitimate_domains}
        self.aliases = {a.lower() for a in (aliases or set())}

    @property
    def brand_name(self) -> str:
        return self.name


# High-Risk Deceptive Keywords frequently prepended/appended in phishing attacks
DECEPTIVE_KEYWORDS: Set[str] = {
    # Authentication & Access
    "login", "signin", "sign-in", "log-in", "auth", "authenticate", "sso",
    "portal", "access", "oauth", "session", "passcode", "password", "credential",
    # Verification & Security
    "verify", "verification", "security", "secure", "checkpoint", "validate",
    "validation", "confirm", "confirmation", "protect", "protection", "safe",
    # Account & Profile Management
    "account", "myaccount", "profile", "user", "member", "customer", "client",
    "update", "upgrade", "recovery", "recover", "restore", "unlock", "activation",
    # Financial & Transactions
    "billing", "payment", "invoice", "wallet", "banking", "finance", "deposit",
    "withdraw", "transfer", "refund", "payout", "checkout", "kyc", "card",
    # Support & Resolution
    "support", "helpdesk", "service", "resolution", "alert", "notification", "notice",
    "dispute", "appeal", "claim", "urgent", "action-required", "suspended",
}

# Protected Global Brand Profiles
PROTECTED_BRANDS: Dict[str, BrandProfile] = {
    # Banking & Financial Services (Priority 1.0)
    "paypal": BrandProfile("paypal", "FINANCE", 1.0, {"paypal.com", "paypal.me", "paypal-community.com"}),
    "chase": BrandProfile("chase", "FINANCE", 1.0, {"chase.com", "jpmorganchase.com"}),
    "bankofamerica": BrandProfile("bankofamerica", "FINANCE", 1.0, {"bankofamerica.com", "bofa.com"}, {"bofa"}),
    "wellsfargo": BrandProfile("wellsfargo", "FINANCE", 1.0, {"wellsfargo.com"}),
    "citibank": BrandProfile("citibank", "FINANCE", 1.0, {"citi.com", "citibank.com"}, {"citi"}),
    "stripe": BrandProfile("stripe", "FINANCE", 0.95, {"stripe.com"}),
    "revolut": BrandProfile("revolut", "FINANCE", 0.95, {"revolut.com"}),
    "venmo": BrandProfile("venmo", "FINANCE", 0.95, {"venmo.com"}),

    # Cryptocurrency & Web3 (Priority 1.0)
    "binance": BrandProfile("binance", "CRYPTO", 1.0, {"binance.com", "binance.us", "bnbchain.org"}),
    "coinbase": BrandProfile("coinbase", "CRYPTO", 1.0, {"coinbase.com", "pro.coinbase.com"}),
    "metamask": BrandProfile("metamask", "CRYPTO", 1.0, {"metamask.io"}),
    "kraken": BrandProfile("kraken", "CRYPTO", 1.0, {"kraken.com"}),
    "ledger": BrandProfile("ledger", "CRYPTO", 0.95, {"ledger.com"}),
    "uniswap": BrandProfile("uniswap", "CRYPTO", 0.95, {"uniswap.org"}),

    # Tech Giants & Cloud (Priority 0.95)
    "apple": BrandProfile("apple", "TECH", 0.95, {"apple.com", "icloud.com", "me.com", "appleid.apple.com"}, {"icloud", "appleid"}),
    "google": BrandProfile("google", "TECH", 0.95, {"google.com", "gmail.com", "youtube.com", "google.co.uk"}, {"gmail"}),
    "microsoft": BrandProfile("microsoft", "TECH", 0.95, {"microsoft.com", "live.com", "office.com", "outlook.com"}, {"office365", "outlook"}),
    "amazon": BrandProfile("amazon", "TECH", 0.95, {"amazon.com", "aws.amazon.com", "amazon.co.uk", "primevideo.com"}, {"aws"}),
    "netflix": BrandProfile("netflix", "TECH", 0.90, {"netflix.com"}),
    "meta": BrandProfile("meta", "TECH", 0.90, {"meta.com", "facebook.com", "instagram.com", "whatsapp.com"}, {"facebook", "instagram", "whatsapp"}),
    "github": BrandProfile("github", "TECH", 0.90, {"github.com", "github.io"}),
    "discord": BrandProfile("discord", "TECH", 0.90, {"discord.com", "discord.gg"}),
    "steam": BrandProfile("steam", "TECH", 0.90, {"steampowered.com", "steamcommunity.com"}, {"steampowered"}),
    "spotify": BrandProfile("spotify", "TECH", 0.85, {"spotify.com"}),
    "openai": BrandProfile("openai", "TECH", 0.95, {"openai.com", "chatgpt.com"}, {"chatgpt"}),

    # Telecom, Logistics & Government (Priority 0.90)
    "usps": BrandProfile("usps", "LOGISTICS", 0.90, {"usps.com"}),
    "fedex": BrandProfile("fedex", "LOGISTICS", 0.90, {"fedex.com"}),
    "dhl": BrandProfile("dhl", "LOGISTICS", 0.90, {"dhl.com"}),
    "verizon": BrandProfile("verizon", "TELECOM", 0.85, {"verizon.com"}),
    "att": BrandProfile("att", "TELECOM", 0.85, {"att.com"}),
}


class BrandDictionary:
    """
    High-performance brand lookup and target matching heuristics.
    """

    @classmethod
    def find_matched_brand(cls, token: str) -> Optional[BrandProfile]:
        """
        Directly matches a domain token against protected brands and their aliases.
        """
        clean = token.lower().strip()
        if clean in PROTECTED_BRANDS:
            return PROTECTED_BRANDS[clean]

        # Check aliases
        for profile in PROTECTED_BRANDS.values():
            if clean in profile.aliases:
                return profile

        return None

    @classmethod
    def is_legitimate_brand_apex(cls, apex_domain: str, brand_name: str) -> bool:
        """
        Checks if the provided apex domain belongs to the official legitimate domains for the brand.
        """
        clean_apex = apex_domain.lower().strip()
        profile = cls.find_matched_brand(brand_name)
        if not profile:
            return False

        for legit in profile.legitimate_domains:
            if clean_apex == legit or clean_apex.endswith("." + legit):
                return True
        return False

    @classmethod
    def extract_deceptive_keywords(cls, domain: str) -> List[str]:
        """
        Extracts all deceptive keywords found anywhere in the domain name.
        Handles hyphenated, underscored, and dot-separated terms.
        """
        clean = domain.lower()
        # Replace non-alphanumeric with spaces to tokenize
        tokens = [t for t in "".join(c if c.isalnum() else " " for c in clean).split() if len(t) >= 3]
        found: List[str] = []
        for kw in DECEPTIVE_KEYWORDS:
            if kw in tokens:
                found.append(kw)
        return sorted(found)

    @classmethod
    def get_all_brands(cls) -> List[str]:
        """Returns list of all registered brand names and aliases."""
        brands: List[str] = list(PROTECTED_BRANDS.keys())
        for p in PROTECTED_BRANDS.values():
            brands.extend(p.aliases)
        return sorted(list(set(brands)))
