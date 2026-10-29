"""
FocusDNS AI Engine - IDN Homograph, Typosquatting & Bitsquatting Defense.

Detects advanced character-level and encoding-level impersonation attacks:
  1. Mixed-Script Confusables (e.g. Cyrillic 'а' embedded in Latin 'apple.com').
  2. Whole-Script Spoofing (e.g. 'paypal.com' spelled entirely in Cyrillic).
  3. Damerau-Levenshtein Typosquatting (transpositions, omissions, duplications).
  4. QWERTY Keyboard Adjacency (fat-finger mistakes, e.g. 'goolge.com').
  5. Bitsquatting (single-bit memory and network transmission flips).
"""

import math
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.unicode_confusables import (
    UnicodeConfusableNormalizer, SCRIPT_LATIN, SCRIPT_CYRILLIC, SCRIPT_GREEK
)
from server.ai.brand_dictionary import BrandDictionary, BrandProfile


# QWERTY Physical Keyboard Adjacency Map
KEYBOARD_ADJACENCY: Dict[str, Set[str]] = {
    "q": {"w", "a", "s", "1", "2"},
    "w": {"q", "e", "a", "s", "d", "2", "3"},
    "e": {"w", "r", "s", "d", "f", "3", "4"},
    "r": {"e", "t", "d", "f", "g", "4", "5"},
    "t": {"r", "y", "f", "g", "h", "5", "6"},
    "y": {"t", "u", "g", "h", "j", "6", "7"},
    "u": {"y", "i", "h", "j", "k", "7", "8"},
    "i": {"u", "o", "j", "k", "l", "8", "9"},
    "o": {"i", "p", "k", "l", "9", "0"},
    "p": {"o", "l", "0", "-", "["},
    "a": {"q", "w", "s", "z"},
    "s": {"a", "w", "e", "d", "z", "x"},
    "d": {"s", "e", "r", "f", "x", "c"},
    "f": {"d", "r", "t", "g", "c", "v"},
    "g": {"f", "t", "y", "h", "v", "b"},
    "h": {"g", "y", "u", "j", "b", "n"},
    "j": {"h", "u", "i", "k", "n", "m"},
    "k": {"j", "i", "o", "l", "m"},
    "l": {"k", "o", "p"},
    "z": {"a", "s", "x"},
    "x": {"z", "s", "d", "c"},
    "c": {"x", "d", "f", "v"},
    "v": {"c", "f", "g", "b"},
    "b": {"v", "g", "h", "n"},
    "n": {"b", "h", "j", "m"},
    "m": {"n", "j", "k"},
    "1": {"2", "q"}, "2": {"1", "3", "q", "w"}, "3": {"2", "4", "w", "e"},
    "4": {"3", "5", "e", "r"}, "5": {"4", "6", "r", "t"}, "6": {"5", "7", "t", "y"},
    "7": {"6", "8", "y", "u"}, "8": {"7", "9", "u", "i"}, "9": {"8", "0", "i", "o"},
    "0": {"9", "-", "o", "p"}
}


class HomographVerdict:
    """Structured result returned by the IDN Homograph & Typosquatting Engine."""
    __slots__ = (
        "is_threat", "attack_type", "risk_score", "spoofed_brand",
        "original_domain", "unicode_domain", "skeleton",
        "confusable_details", "explanation"
    )

    def __init__(
        self,
        is_threat: bool,
        attack_type: str,
        risk_score: float,
        spoofed_brand: Optional[str],
        original_domain: str,
        unicode_domain: str,
        skeleton: str,
        confusable_details: List[Dict[str, Any]],
        explanation: str
    ):
        self.is_threat = is_threat
        self.attack_type = attack_type
        self.risk_score = round(min(100.0, max(0.0, risk_score)), 2)
        self.spoofed_brand = spoofed_brand
        self.original_domain = original_domain
        self.unicode_domain = unicode_domain
        self.skeleton = skeleton
        self.confusable_details = confusable_details
        self.explanation = explanation

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_threat": self.is_threat,
            "attack_type": self.attack_type,
            "risk_score": self.risk_score,
            "spoofed_brand": self.spoofed_brand,
            "original_domain": self.original_domain,
            "unicode_domain": self.unicode_domain,
            "skeleton": self.skeleton,
            "confusable_count": len(self.confusable_details),
            "confusable_details": self.confusable_details,
            "explanation": self.explanation
        }


class HomographEngine:
    """
    On-device detector for IDN Homographs, Typosquatting, and Bitsquatting.
    """

    @staticmethod
    def damerau_levenshtein_distance(s1: str, s2: str) -> int:
        """
        Calculates optimal string alignment distance including transpositions.
        """
        len1, len2 = len(s1), len(s2)
        d = [[0] * (len2 + 1) for _ in range(len1 + 1)]

        for i in range(len1 + 1):
            d[i][0] = i
        for j in range(len2 + 1):
            d[0][j] = j

        for i in range(1, len1 + 1):
            for j in range(1, len2 + 1):
                cost = 0 if s1[i - 1] == s2[j - 1] else 1
                d[i][j] = min(
                    d[i - 1][j] + 1,        # deletion
                    d[i][j - 1] + 1,        # insertion
                    d[i - 1][j - 1] + cost  # substitution
                )
                if i > 1 and j > 1 and s1[i - 1] == s2[j - 2] and s1[i - 2] == s2[j - 1]:
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + cost)  # transposition

        return d[len1][len2]

    @staticmethod
    def is_bitsquat(candidate: str, target: str) -> bool:
        """
        Checks if candidate differs from target by exactly ONE flipped bit in ASCII.
        """
        if len(candidate) != len(target):
            return False

        diff_count = 0
        for c1, c2 in zip(candidate, target):
            xor_val = ord(c1) ^ ord(c2)
            if xor_val != 0:
                # Count number of set bits
                set_bits = bin(xor_val).count("1")
                diff_count += set_bits
                if diff_count > 1:
                    return False

        return diff_count == 1

    @staticmethod
    def is_keyboard_adjacent_typo(candidate: str, target: str) -> bool:
        """
        Checks if candidate has exactly 1 character replaced by an adjacent physical keyboard key.
        """
        if len(candidate) != len(target):
            return False

        diffs = []
        for i, (c1, c2) in enumerate(zip(candidate, target)):
            if c1 != c2:
                diffs.append((c1, c2))

        if len(diffs) == 1:
            c1, c2 = diffs[0]
            adjacent_keys = KEYBOARD_ADJACENCY.get(c2, set())
            return c1 in adjacent_keys

        return False

    @classmethod
    def evaluate_domain(cls, domain: str) -> HomographVerdict:
        """
        Comprehensive evaluation of a domain for homograph, typo, and bit-flip spoofing.
        """
        script_analysis = UnicodeConfusableNormalizer.analyze_domain_scripts(domain)
        unicode_domain = script_analysis["unicode_domain"]
        skeleton = script_analysis["skeleton"]
        confusables = script_analysis["confusables"]
        has_mixed = script_analysis["has_mixed_script"]

        # Parse apex and main label
        skeleton_parts = skeleton.split(".")
        skeleton_apex = ".".join(skeleton_parts[-2:]) if len(skeleton_parts) >= 2 else skeleton
        main_label = skeleton_parts[0] if skeleton_parts else ""

        # 1. Evaluate Unicode Confusables (Mixed-Script or Whole-Script)
        if script_analysis["is_spoof_candidate"]:
            for brand_name in BrandDictionary.get_all_brands():
                # Check if skeleton matches protected brand apex (e.g. 'paypal.com' or 'apple.com')
                if BrandDictionary.is_legitimate_brand_apex(skeleton_apex, brand_name):
                    # If skeleton matches brand apex, but original domain is NOT legitimate apex,
                    # this is an active homograph impersonation attack!
                    orig_apex = ".".join(unicode_domain.split(".")[-2:])
                    if not BrandDictionary.is_legitimate_brand_apex(orig_apex, brand_name):
                        attack_type = "MIXED_SCRIPT_CONFUSABLE" if has_mixed else "WHOLE_SCRIPT_CONFUSABLE"
                        profile = BrandDictionary.find_matched_brand(brand_name)
                        canonical_brand = profile.brand_name if profile else brand_name
                        skel_main = skeleton_apex.split(".")[0]
                        if skel_main in BrandDictionary.get_all_brands():
                            matched_p = BrandDictionary.find_matched_brand(skel_main)
                            if matched_p:
                                canonical_brand = matched_p.brand_name
                                profile = matched_p

                        risk = 98.0 * (profile.risk_weight if profile else 1.0)

                        explanation = (
                            f"Detected high-confidence {attack_type} spoofing brand '{canonical_brand}'. "
                            f"Domain '{domain}' resolves to visual skeleton '{skeleton}' with {len(confusables)} confusable character(s)."
                        )
                        return HomographVerdict(
                            is_threat=True,
                            attack_type=attack_type,
                            risk_score=risk,
                            spoofed_brand=canonical_brand,
                            original_domain=domain,
                            unicode_domain=unicode_domain,
                            skeleton=skeleton,
                            confusable_details=confusables,
                            explanation=explanation
                        )

        # 2. Evaluate Typo-Squatting, Keyboard Adjacency, and Bit-Squatting
        # Extract registered domain label (e.g. 'paypaal' from 'paypaal.com')
        unicode_labels = unicode_domain.split(".")
        if len(unicode_labels) >= 2:
            reg_label = unicode_labels[-2]
            tld = unicode_labels[-1]
            reg_apex = f"{reg_label}.{tld}"

            for brand_name in BrandDictionary.get_all_brands():
                # Skip if domain is the legitimate brand apex itself
                if BrandDictionary.is_legitimate_brand_apex(reg_apex, brand_name):
                    continue

                profile = BrandDictionary.find_matched_brand(brand_name)
                weight = profile.risk_weight if profile else 0.9

                # Check Bitsquatting (1-bit hardware/network flip)
                if cls.is_bitsquat(reg_label, brand_name):
                    return HomographVerdict(
                        is_threat=True,
                        attack_type="BIT_SQUATTING",
                        risk_score=85.0 * weight,
                        spoofed_brand=brand_name,
                        original_domain=domain,
                        unicode_domain=unicode_domain,
                        skeleton=skeleton,
                        confusable_details=[],
                        explanation=f"Detected Bit-Squatting flip targeting brand '{brand_name}' ({reg_label} vs {brand_name})."
                    )

                # Check Physical Keyboard Adjacency (Fat-finger typo)
                if cls.is_keyboard_adjacent_typo(reg_label, brand_name):
                    return HomographVerdict(
                        is_threat=True,
                        attack_type="KEYBOARD_ADJACENCY",
                        risk_score=80.0 * weight,
                        spoofed_brand=brand_name,
                        original_domain=domain,
                        unicode_domain=unicode_domain,
                        skeleton=skeleton,
                        confusable_details=[],
                        explanation=f"Detected QWERTY keyboard adjacency typo-squatting targeting '{brand_name}'."
                    )

                # Check Damerau-Levenshtein distance (distance == 1 or 2 with close length)
                dist = cls.damerau_levenshtein_distance(reg_label, brand_name)
                if dist == 1 and len(reg_label) >= 4:
                    return HomographVerdict(
                        is_threat=True,
                        attack_type="TYPO_SQUATTING",
                        risk_score=78.0 * weight,
                        spoofed_brand=brand_name,
                        original_domain=domain,
                        unicode_domain=unicode_domain,
                        skeleton=skeleton,
                        confusable_details=[],
                        explanation=f"Detected 1-edit distance typosquatting targeting brand '{brand_name}' (distance=1)."
                    )
                elif dist == 2 and len(brand_name) >= 6 and len(reg_label) >= 6:
                    return HomographVerdict(
                        is_threat=True,
                        attack_type="TYPO_SQUATTING",
                        risk_score=65.0 * weight,
                        spoofed_brand=brand_name,
                        original_domain=domain,
                        unicode_domain=unicode_domain,
                        skeleton=skeleton,
                        confusable_details=[],
                        explanation=f"Detected 2-edit distance typosquatting targeting brand '{brand_name}'."
                    )

        # 3. Clean Domain Verdict
        return HomographVerdict(
            is_threat=False,
            attack_type="NONE",
            risk_score=0.0,
            spoofed_brand=None,
            original_domain=domain,
            unicode_domain=unicode_domain,
            skeleton=skeleton,
            confusable_details=confusables,
            explanation="Domain shows no homograph, typosquatting, or bitsquatting characteristics."
        )

    analyze = evaluate_domain


HomographResult = HomographVerdict
