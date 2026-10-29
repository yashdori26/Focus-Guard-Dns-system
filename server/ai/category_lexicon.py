"""
FocusDNS AI Engine - Standardized Category Lexicon & Weighted Feature Vocabulary.

Defines the multi-class taxonomy, keyword dictionaries, and lexical n-gram priors
for dynamic on-device classification into 8 core internet traffic categories:
  1. GAMING
  2. SOCIAL_MEDIA
  3. ADULT_CONTENT
  4. PRODUCTIVITY_WORK
  5. SHOPPING_ECOMMERCE
  6. STREAMING_ENTERTAINMENT
  7. CRYPTO_GAMBLING
  8. MALWARE_THREAT
"""

from typing import Dict, List, Set, Optional, Tuple, Any

# Primary Category Identifiers
CAT_GAMING = "GAMING"
CAT_SOCIAL = "SOCIAL_MEDIA"
CAT_ADULT = "ADULT_CONTENT"
CAT_PRODUCTIVITY = "PRODUCTIVITY_WORK"
CAT_SHOPPING = "SHOPPING_ECOMMERCE"
CAT_STREAMING = "STREAMING_ENTERTAINMENT"
CAT_CRYPTO_GAMBLING = "CRYPTO_GAMBLING"
CAT_MALWARE = "MALWARE_THREAT"
CAT_UNCATEGORIZED = "UNCATEGORIZED"

ALL_CATEGORIES = [
    CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_PRODUCTIVITY,
    CAT_SHOPPING, CAT_STREAMING, CAT_CRYPTO_GAMBLING, CAT_MALWARE
]

# TLD Priors: TLDs that strongly indicate specific categories
TLD_CATEGORY_PRIORS: Dict[str, str] = {
    # Gaming
    "game": CAT_GAMING, "games": CAT_GAMING, "gg": CAT_GAMING, "quest": CAT_GAMING,
    # Adult
    "xxx": CAT_ADULT, "porn": CAT_ADULT, "adult": CAT_ADULT, "sexy": CAT_ADULT, "cam": CAT_ADULT,
    # Shopping
    "shop": CAT_SHOPPING, "store": CAT_SHOPPING, "deals": CAT_SHOPPING, "market": CAT_SHOPPING,
    # Crypto & Gambling
    "casino": CAT_CRYPTO_GAMBLING, "bet": CAT_CRYPTO_GAMBLING, "poker": CAT_CRYPTO_GAMBLING,
    "crypto": CAT_CRYPTO_GAMBLING,
    # Productivity
    "dev": CAT_PRODUCTIVITY, "io": CAT_PRODUCTIVITY, "app": CAT_PRODUCTIVITY
}

# Weighted Category Vocabularies (token -> weight between 1.0 and 5.0)
CATEGORY_VOCABULARY: Dict[str, Dict[str, float]] = {
    CAT_GAMING: {
        "steam": 5.0, "steampowered": 5.0, "epicgames": 5.0, "roblox": 5.0, "twitch": 4.5,
        "riotgames": 5.0, "blizzard": 5.0, "playstation": 5.0, "xbox": 5.0, "nintendo": 5.0,
        "minecraft": 5.0, "pubg": 5.0, "valorant": 5.0, "csgo": 5.0, "discord": 4.0,
        "ea": 4.0, "ubisoft": 4.5, "garena": 5.0, "genshin": 5.0, "hoyoverse": 5.0,
        "game": 3.5, "games": 3.5, "gaming": 4.0, "gamer": 4.0, "play": 2.5,
        "arcade": 4.0, "quest": 3.0, "rpg": 4.0, "mmo": 4.5, "esports": 4.5,
        "server": 2.0, "craft": 3.5, "mod": 3.0, "battlenet": 5.0, "chess": 4.0
    },

    CAT_SOCIAL: {
        "instagram": 5.0, "tiktok": 5.0, "facebook": 5.0, "twitter": 5.0, "reddit": 5.0,
        "snapchat": 5.0, "linkedin": 4.5, "pinterest": 4.5, "tumblr": 4.5, "threads": 4.0,
        "bsky": 4.5, "mastodon": 4.5, "social": 4.0, "chat": 3.5, "feed": 3.0,
        "share": 2.5, "follow": 3.0, "post": 2.5, "tweet": 4.5, "insta": 4.0,
        "pin": 3.0, "blog": 3.0, "forum": 3.5, "community": 3.0, "messenger": 4.5,
        "whatsapp": 4.5, "telegram": 4.5, "weibo": 5.0, "vk": 5.0, "line": 4.0
    },

    CAT_ADULT: {
        "porn": 5.0, "xxx": 5.0, "sex": 5.0, "tube": 3.5, "adult": 4.5,
        "cam": 4.0, "erotic": 5.0, "nsfw": 5.0, "dating": 3.5, "hookup": 4.5,
        "strip": 4.5, "escort": 5.0, "mature": 3.5, "sensual": 4.0, "webcam": 4.0,
        "livecam": 4.5, "fetish": 5.0, "kink": 4.5, "bdsm": 5.0, "nudist": 4.5,
        "onlyfans": 5.0, "fansly": 5.0, "chaturbate": 5.0, "pornhub": 5.0, "xvideos": 5.0
    },

    CAT_PRODUCTIVITY: {
        "github": 5.0, "gitlab": 5.0, "slack": 5.0, "notion": 5.0, "asana": 5.0,
        "jira": 5.0, "atlassian": 5.0, "trello": 5.0, "figma": 5.0, "zoom": 4.5,
        "office365": 5.0, "dropbox": 4.5, "box": 4.0, "salesforce": 5.0, "code": 3.5,
        "dev": 3.5, "api": 3.5, "doc": 3.0, "docs": 3.5, "sheet": 3.0,
        "workspace": 4.0, "project": 3.5, "task": 3.5, "agile": 4.0, "sprint": 3.5,
        "kanban": 4.5, "cloud": 2.5, "infra": 3.5, "console": 3.0, "linear": 4.5,
        "clickup": 4.5, "miro": 4.5, "canva": 4.0, "stack": 3.0, "stackoverflow": 5.0
    },

    CAT_SHOPPING: {
        "amazon": 5.0, "ebay": 5.0, "shopify": 5.0, "aliexpress": 5.0, "walmart": 5.0,
        "target": 4.5, "etsy": 5.0, "bestbuy": 5.0, "costco": 5.0, "ikea": 5.0,
        "shop": 4.0, "store": 4.0, "buy": 3.5, "cart": 4.0, "checkout": 4.0,
        "discount": 4.0, "sale": 3.5, "deal": 3.5, "deals": 4.0, "price": 3.0,
        "order": 3.0, "merchant": 4.0, "retail": 4.0, "mall": 4.0, "coupon": 4.5,
        "zalando": 5.0, "asos": 5.0, "shein": 5.0, "temu": 5.0, "wish": 4.5
    },

    CAT_STREAMING: {
        "netflix": 5.0, "youtube": 5.0, "hulu": 5.0, "disneyplus": 5.0, "hbo": 5.0,
        "max": 4.0, "primevideo": 5.0, "spotify": 5.0, "applemusic": 5.0, "soundcloud": 4.5,
        "deezer": 4.5, "stream": 4.0, "video": 3.5, "movie": 4.0, "movies": 4.0,
        "music": 3.5, "audio": 3.0, "podcast": 4.0, "series": 3.5, "watch": 3.5,
        "listen": 3.0, "tv": 3.5, "flix": 4.0, "cinema": 4.0, "crunchyroll": 5.0,
        "pandora": 4.5, "tidal": 4.5, "vimeo": 4.5, "dailymotion": 4.5, "peacock": 5.0
    },

    CAT_CRYPTO_GAMBLING: {
        "stake": 5.0, "bet365": 5.0, "draftkings": 5.0, "fanduel": 5.0, "pokerstars": 5.0,
        "binance": 5.0, "coinbase": 5.0, "kraken": 5.0, "uniswap": 5.0, "bybit": 5.0,
        "metamask": 5.0, "rollbit": 5.0, "casino": 5.0, "bet": 4.5, "betting": 4.5,
        "poker": 5.0, "slots": 5.0, "roulette": 5.0, "jackpot": 5.0, "wager": 4.5,
        "lotto": 5.0, "lottery": 5.0, "crypto": 4.0, "btc": 4.0, "eth": 4.0,
        "token": 3.5, "swap": 3.5, "dex": 4.0, "defi": 4.0, "nft": 4.0,
        "gamble": 5.0, "sportsbook": 5.0, "1xbet": 5.0, "bovada": 5.0, "pinnacle": 5.0
    },

    CAT_MALWARE: {
        "botnet": 5.0, "ransom": 5.0, "trojan": 5.0, "c2": 4.5, "phish": 5.0,
        "exploit": 5.0, "dropper": 5.0, "keylogger": 5.0, "stealer": 5.0, "infostealer": 5.0,
        "malware": 5.0, "virus": 4.5, "worm": 4.0, "backdoor": 5.0, "payload": 4.5,
        "spy": 4.0, "crack": 4.0, "keygen": 4.5, "hack": 3.5, "rootkit": 5.0,
        "cobaltstrike": 5.0, "metasploit": 5.0, "rat": 4.0, "loader": 4.5
    }
}


class CategoryLexicon:
    """Standardized vocabulary and lexicon helper for multi-class domain categorization."""

    ALL_CATEGORIES = ALL_CATEGORIES
    TLD_PRIORS = TLD_CATEGORY_PRIORS
    CATEGORY_KEYWORDS = CATEGORY_VOCABULARY
    CATEGORY_VOCABULARY = CATEGORY_VOCABULARY

    @classmethod
    def get_categories(cls) -> List[str]:
        return list(cls.ALL_CATEGORIES)

    @classmethod
    def get_tld_prior(cls, tld: str) -> Optional[str]:
        return cls.TLD_PRIORS.get(tld.lower())

    @classmethod
    def get_keywords_for_category(cls, category: str) -> Dict[str, float]:
        return cls.CATEGORY_VOCABULARY.get(category, {})
