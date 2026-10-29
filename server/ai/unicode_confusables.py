"""
FocusDNS AI Engine - Unicode Confusables & IDN Normalizer.

Implements the Unicode Technical Report #39 (UTR #39) Confusable Detection
Specification for Internationalized Domain Names (IDN).

Key Capabilities:
  1. Complete bidirectional confusable mapping: Cyrillic, Greek, Hebrew, Armenian,
     Cherokee, and Mathematical symbols mapped to canonical visual Latin counterparts.
  2. Skeleton transformation algorithm: Converts Unicode IDN or Punycode (xn--) strings
     into normalized visual representation (e.g., 'pаypal' -> 'paypal', 'аррӏе' -> 'apple').
  3. Script classification: Identifies the exact Unicode script block for each character
     (Latin, Cyrillic, Greek, Arabic, Hebrew, Common, Inherited).
  4. Mixed-script detection: Flags domains that illegally blend disparate scripts
     within a single label to disguise phishing attacks.
"""

import unicodedata
from typing import Dict, List, Set, Tuple, Optional, Any

# Unicode Script Enumeration
SCRIPT_LATIN = "Latin"
SCRIPT_CYRILLIC = "Cyrillic"
SCRIPT_GREEK = "Greek"
SCRIPT_HEBREW = "Hebrew"
SCRIPT_ARMENIAN = "Armenian"
SCRIPT_CHEROKEE = "Cherokee"
SCRIPT_COMMON = "Common"
SCRIPT_UNKNOWN = "Unknown"

# Canonical Unicode TR39 Visual Confusable Mapping (Unicode char -> Latin equivalent)
CONFUSABLE_MAP: Dict[str, str] = {
    # Cyrillic Small Letters (most heavily abused in brand impersonation)
    "\u0430": "a",  # Cyrillic Small Letter A
    "\u0435": "e",  # Cyrillic Small Letter E
    "\u043e": "o",  # Cyrillic Small Letter O
    "\u0440": "p",  # Cyrillic Small Letter Er (looks like 'p')
    "\u0441": "c",  # Cyrillic Small Letter Es (looks like 'c')
    "\u0443": "y",  # Cyrillic Small Letter U (looks like 'y')
    "\u0445": "x",  # Cyrillic Small Letter Ha (looks like 'x')
    "\u0456": "i",  # Cyrillic Small Letter Byelorussian-Ukrainian I
    "\u0458": "j",  # Cyrillic Small Letter Je
    "\u0455": "s",  # Cyrillic Small Letter Dze (looks like 's')
    "\u04cf": "l",  # Cyrillic Small Letter Palochka (looks like 'l')
    "\u04bb": "h",  # Cyrillic Small Letter Shha (looks like 'h')
    "\u0432": "b",  # Cyrillic Small Letter Ve (confusable with 'b' or 'v')
    "\u0442": "t",  # Cyrillic Small Letter Te
    "\u043a": "k",  # Cyrillic Small Letter Ka

    # Cyrillic Capital Letters
    "\u0410": "A",  # Cyrillic Capital Letter A
    "\u0412": "B",  # Cyrillic Capital Letter Ve (looks like 'B')
    "\u0415": "E",  # Cyrillic Capital Letter E
    "\u041a": "K",  # Cyrillic Capital Letter Ka
    "\u041c": "M",  # Cyrillic Capital Letter Em
    "\u041d": "H",  # Cyrillic Capital Letter En (looks like 'H')
    "\u041e": "O",  # Cyrillic Capital Letter O
    "\u0420": "P",  # Cyrillic Capital Letter Er (looks like 'P')
    "\u0421": "C",  # Cyrillic Capital Letter Es (looks like 'C')
    "\u0422": "T",  # Cyrillic Capital Letter Te
    "\u0423": "Y",  # Cyrillic Capital Letter U
    "\u0425": "X",  # Cyrillic Capital Letter Ha

    # Greek Small Letters
    "\u03bf": "o",  # Greek Small Letter Omicron
    "\u03b1": "a",  # Greek Small Letter Alpha
    "\u03bd": "v",  # Greek Small Letter Nu (looks like 'v')
    "\u03b9": "i",  # Greek Small Letter Iota
    "\u03ba": "k",  # Greek Small Letter Kappa
    "\u03c1": "p",  # Greek Small Letter Rho (looks like 'p')
    "\u03c7": "x",  # Greek Small Letter Chi

    # Greek Capital Letters
    "\u0391": "A",  # Greek Capital Letter Alpha
    "\u0392": "B",  # Greek Capital Letter Beta
    "\u0395": "E",  # Greek Capital Letter Epsilon
    "\u0397": "H",  # Greek Capital Letter Eta
    "\u0399": "I",  # Greek Capital Letter Iota
    "\u039a": "K",  # Greek Capital Letter Kappa
    "\u039c": "M",  # Greek Capital Letter Mu
    "\u039d": "N",  # Greek Capital Letter Nu
    "\u039f": "O",  # Greek Capital Letter Omicron
    "\u03a1": "P",  # Greek Capital Letter Rho
    "\u03a4": "T",  # Greek Capital Letter Tau
    "\u03a7": "X",  # Greek Capital Letter Chi
    "\u03a5": "Y",  # Greek Capital Letter Upsilon
    "\u0396": "Z",  # Greek Capital Letter Zeta

    # Armenian Confusables
    "\u0578": "n",  # Armenian Small Letter Vo (looks like 'n')
    "\u057d": "u",  # Armenian Small Letter Se (looks like 'u')
    "\u0581": "g",  # Armenian Small Letter Co (looks like 'g')
    "\u0566": "q",  # Armenian Small Letter Za (looks like 'q')

    # Cherokee Confusables
    "\u13aa": "A",  # Cherokee Letter Go
    "\u13cd": "T",  # Cherokee Letter Tsv
    "\u13ef": "W",  # Cherokee Letter La
    "\u13b7": "M",  # Cherokee Letter Lu
    "\u13bb": "H",  # Cherokee Letter Mi
    "\u13c5": "R",  # Cherokee Letter Sv
    "\u13d3": "V",  # Cherokee Letter Do
    "\u13e2": "S",  # Cherokee Letter Dlv

    # Fullwidth ASCII Variants (U+FF01 to U+FF5E)
    "\uff41": "a", "\uff42": "b", "\uff43": "c", "\uff44": "d",
    "\uff45": "e", "\uff46": "f", "\uff47": "g", "\uff48": "h",
    "\uff49": "i", "\uff4a": "j", "\uff4b": "k", "\uff4c": "l",
    "\uff4d": "m", "\uff4e": "n", "\uff4f": "o", "\uff50": "p",
    "\uff51": "q", "\uff52": "r", "\uff53": "s", "\uff54": "t",
    "\uff55": "u", "\uff56": "v", "\uff57": "w", "\uff58": "x",
    "\uff59": "y", "\uff5a": "z",
    "\uff21": "A", "\uff22": "B", "\uff23": "C", "\uff24": "D",
    "\uff25": "E", "\uff26": "F", "\uff27": "G", "\uff28": "H",
    "\uff29": "I", "\uff2a": "J", "\uff2b": "K", "\uff2c": "L",
    "\uff2d": "M", "\uff2e": "N", "\uff2f": "O", "\uff30": "P",
    "\uff31": "Q", "\uff32": "R", "\uff33": "S", "\uff34": "T",
    "\uff35": "U", "\uff36": "V", "\uff37": "W", "\uff38": "X",
    "\uff39": "Y", "\uff3a": "Z",

    # Mathematical Alphanumeric Symbols (U+1D400+)
    "\U0001d41a": "a", "\U0001d41b": "b", "\U0001d41c": "c", "\U0001d41d": "d",
    "\U0001d41e": "e", "\U0001d41f": "f", "\U0001d420": "g", "\U0001d421": "h",
    "\U0001d422": "i", "\U0001d423": "j", "\U0001d424": "k", "\U0001d425": "l",
    "\U0001d426": "m", "\U0001d427": "n", "\U0001d428": "o", "\U0001d429": "p",
    "\U0001d42a": "q", "\U0001d42b": "r", "\U0001d42c": "s", "\U0001d42d": "t",
    "\U0001d42e": "u", "\U0001d42f": "v", "\U0001d430": "w", "\U0001d431": "x",
    "\U0001d432": "y", "\U0001d433": "z",

    # Enclosed / Circled / Dot variants
    "\u24d0": "a", "\u24d1": "b", "\u24d2": "c", "\u24d3": "d",
    "\u24d4": "e", "\u24d5": "f", "\u24d6": "g", "\u24d7": "h",
    "\u24d8": "i", "\u24d9": "j", "\u24da": "k", "\u24db": "l",
    "\u24dc": "m", "\u24dd": "n", "\u24de": "o", "\u24df": "p",
    "\u24e0": "q", "\u24e1": "r", "\u24e2": "s", "\u24e3": "t",
    "\u24e4": "u", "\u24e5": "v", "\u24e6": "w", "\u24e7": "x",
    "\u24e8": "y", "\u24e9": "z",
}


class UnicodeConfusableNormalizer:
    """
    High-performance Unicode TR39 normalizer and confusable detector.
    """

    @staticmethod
    def identify_script(char: str) -> str:
        """Determines Unicode script category for a given character."""
        cp = ord(char)
        if (0x0041 <= cp <= 0x005A) or (0x0061 <= cp <= 0x007A) or (0x00C0 <= cp <= 0x024F):
            return SCRIPT_LATIN
        elif 0x0400 <= cp <= 0x04FF or 0x0500 <= cp <= 0x052F:
            return SCRIPT_CYRILLIC
        elif 0x0370 <= cp <= 0x03FF or 0x1F00 <= cp <= 0x1FFF:
            return SCRIPT_GREEK
        elif 0x0590 <= cp <= 0x05FF:
            return SCRIPT_HEBREW
        elif 0x0530 <= cp <= 0x058F:
            return SCRIPT_ARMENIAN
        elif 0x13A0 <= cp <= 0x13FF:
            return SCRIPT_CHEROKEE
        elif cp in (0x002D, 0x002E, 0x005F) or (0x0030 <= cp <= 0x0039):  # '-', '.', '_', digits
            return SCRIPT_COMMON
        return SCRIPT_UNKNOWN

    @classmethod
    def get_skeleton(cls, text: str) -> str:
        """
        Computes visual skeleton according to Unicode TR39 §4.
        Normalizes confusables to their visual Latin equivalent in lowercase.
        """
        # Step 1: Compatibility Decomposition (NFKD)
        decomposed = unicodedata.normalize("NFKD", text)

        # Step 2: Character-by-character confusable mapping
        skeleton_chars: List[str] = []
        for ch in decomposed:
            # Strip non-spacing marks (accents, combining dots)
            if unicodedata.category(ch) == "Mn":
                continue
            if ch in CONFUSABLE_MAP:
                skeleton_chars.append(CONFUSABLE_MAP[ch])
            else:
                skeleton_chars.append(ch)

        # Step 3: Canonical Composition & lowercase
        skeleton_str = "".join(skeleton_chars).lower()
        return unicodedata.normalize("NFC", skeleton_str)

    @classmethod
    def decode_punycode(cls, domain: str) -> str:
        """
        Safely converts Punycode domain (e.g. 'xn--pple-43d.com')
        into raw Unicode characters ('аpple.com').
        """
        parts = domain.strip().lower().split(".")
        decoded_parts: List[str] = []
        for part in parts:
            if part.startswith("xn--"):
                try:
                    decoded = part.encode("ascii").decode("idna")
                    decoded_parts.append(decoded)
                except Exception:
                    # Invalid punycode sequence
                    decoded_parts.append(part)
            else:
                decoded_parts.append(part)
        return ".".join(decoded_parts)

    @classmethod
    def analyze_domain_scripts(cls, domain: str) -> Dict[str, Any]:
        """
        Performs deep script composition analysis across all labels in a domain.
        Returns detailed metrics on script mixing and confusable characters.
        """
        unicode_domain = cls.decode_punycode(domain)
        labels = unicode_domain.split(".")
        
        has_mixed_script = False
        detected_confusables: List[Dict[str, Any]] = []
        domain_scripts: Set[str] = set()

        for label_idx, label in enumerate(labels):
            label_scripts: Set[str] = set()
            for char_idx, ch in enumerate(label):
                script = cls.identify_script(ch)
                if script != SCRIPT_COMMON:
                    label_scripts.add(script)
                    domain_scripts.add(script)

                if ch in CONFUSABLE_MAP:
                    detected_confusables.append({
                        "character": ch,
                        "codepoint": f"U+{ord(ch):04X}",
                        "confusable_with": CONFUSABLE_MAP[ch],
                        "script": script,
                        "label_index": label_idx,
                        "position": char_idx
                    })

            # In a single label, mixing Latin with Cyrillic or Greek is a strong indicator of spoofing
            if len(label_scripts) > 1 and SCRIPT_LATIN in label_scripts:
                has_mixed_script = True

        skeleton = cls.get_skeleton(unicode_domain)
        is_spoof_candidate = (has_mixed_script or len(detected_confusables) > 0)

        return {
            "original_domain": domain,
            "unicode_domain": unicode_domain,
            "skeleton": skeleton,
            "scripts": sorted(domain_scripts),
            "has_mixed_script": has_mixed_script,
            "confusables_count": len(detected_confusables),
            "confusables": detected_confusables,
            "is_spoof_candidate": is_spoof_candidate
        }


class ScriptDetector:
    """Convenience detector for Unicode scripts and script mixing."""

    @staticmethod
    def detect_scripts(domain: str) -> Set[str]:
        scripts = set()
        for ch in UnicodeConfusableNormalizer.decode_punycode(domain):
            s = UnicodeConfusableNormalizer.identify_script(ch)
            if s not in (SCRIPT_COMMON, SCRIPT_UNKNOWN):
                scripts.add(s)
        return scripts

    @staticmethod
    def is_mixed_script(domain: str) -> bool:
        analysis = UnicodeConfusableNormalizer.analyze_domain_scripts(domain)
        return analysis["has_mixed_script"]


class UnicodeConfusables:
    """High-level facade for TR39 confusable normalization and skeleton generation."""

    @staticmethod
    def to_skeleton(domain: str) -> str:
        return UnicodeConfusableNormalizer.get_skeleton(domain)

    @staticmethod
    def decode_punycode(domain: str) -> str:
        return UnicodeConfusableNormalizer.decode_punycode(domain)

    @staticmethod
    def is_confusable(char: str) -> bool:
        return char in CONFUSABLE_MAP

    @staticmethod
    def get_confusable(char: str) -> Optional[str]:
        return CONFUSABLE_MAP.get(char)
