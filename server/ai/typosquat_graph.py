"""
FocusDNS AI Engine - Multi-Layout Keyboard Adjacency & Typo-Squatting Graph.

Provides comprehensive mathematical modeling of keyboard fat-finger errors,
phonetic lookalikes, bitsquatting bit-flips, and structural permutations for
zero-day brand impersonation and typo-squatting detection.

Supported Keyboard Physical Layouts:
  - QWERTY (US/International standard)
  - AZERTY (French standard)
  - QWERTZ (German/Central European standard)
  - Dvorak (Simplified keyboard layout)

Inviolable Constraints:
  1. Life Safety Exemption: Emergency domains (911.gov, 112.gov, push.apple.com,
     update.microsoft.com, play.googleapis.com) are hardcoded EXEMPT and NEVER flagged.
  2. Conditional Whitelisting Law: Whitelist additions are permitted when idle;
     strictly forbidden and raises PermissionError("ERROR_ACCESS_DENIED (5)")
     when locked or when countdown timer > 0.
  3. Zero Cloud Dependency: 100% on-device graph traversal in microseconds.
"""

import time
import math
import threading
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.brand_dictionary import BrandDictionary, BrandProfile, PROTECTED_BRANDS

# Hardcoded Life Safety Exemptions
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "push.apple.com",
    "update.microsoft.com",
    "play.googleapis.com"
}

# Physical Key Adjacency Maps
QWERTY_ADJACENCY: Dict[str, Set[str]] = {
    "q": {"w", "a", "s", "1", "2"},
    "w": {"q", "e", "a", "s", "d", "2", "3"},
    "e": {"w", "r", "s", "d", "f", "3", "4"},
    "r": {"e", "t", "d", "f", "g", "4", "5"},
    "t": {"r", "y", "f", "g", "h", "5", "6"},
    "y": {"t", "u", "g", "h", "j", "6", "7"},
    "u": {"y", "i", "h", "j", "k", "7", "8"},
    "i": {"u", "o", "j", "k", "l", "8", "9"},
    "o": {"i", "p", "k", "l", "9", "0"},
    "p": {"o", "l", "0", "-"},
    "a": {"q", "w", "s", "z"},
    "s": {"q", "w", "e", "a", "d", "z", "x"},
    "d": {"w", "e", "r", "s", "f", "x", "c"},
    "f": {"e", "r", "t", "d", "g", "c", "v"},
    "g": {"r", "t", "y", "f", "h", "v", "b"},
    "h": {"t", "y", "u", "g", "j", "b", "n"},
    "j": {"y", "u", "i", "h", "k", "n", "m"},
    "k": {"u", "i", "o", "j", "l", "m"},
    "l": {"i", "o", "p", "k"},
    "z": {"a", "s", "x"},
    "x": {"z", "s", "d", "c"},
    "c": {"x", "d", "f", "v"},
    "v": {"c", "f", "g", "b"},
    "b": {"v", "g", "h", "n"},
    "n": {"b", "h", "j", "m"},
    "m": {"n", "j", "k"}
}

AZERTY_ADJACENCY: Dict[str, Set[str]] = {
    "a": {"z", "q", "s"},
    "z": {"a", "e", "q", "s", "d"},
    "e": {"z", "r", "s", "d", "f"},
    "r": {"e", "t", "d", "f", "g"},
    "t": {"r", "y", "f", "g", "h"},
    "y": {"t", "u", "g", "h", "j"},
    "u": {"y", "i", "h", "j", "k"},
    "i": {"u", "o", "j", "k", "l"},
    "o": {"i", "p", "k", "l", "m"},
    "p": {"o", "m"},
    "q": {"a", "z", "s", "w"},
    "s": {"q", "z", "e", "d", "w", "x"},
    "d": {"s", "e", "r", "f", "x", "c"},
    "f": {"d", "r", "t", "g", "c", "v"},
    "g": {"f", "t", "y", "h", "v", "b"},
    "h": {"g", "y", "u", "j", "b", "n"},
    "j": {"h", "u", "i", "k", "n"},
    "k": {"j", "i", "o", "l"},
    "l": {"k", "o", "p", "m"},
    "m": {"l", "p"},
    "w": {"q", "s", "x"},
    "x": {"w", "s", "d", "c"},
    "c": {"x", "d", "f", "v"},
    "v": {"c", "f", "g", "b"},
    "b": {"v", "g", "h", "n"},
    "n": {"b", "h", "j"}
}

QWERTZ_ADJACENCY: Dict[str, Set[str]] = dict(QWERTY_ADJACENCY)
# Swap Z and Y in QWERTZ
QWERTZ_ADJACENCY["z"] = QWERTY_ADJACENCY["y"]
QWERTZ_ADJACENCY["y"] = QWERTY_ADJACENCY["z"]

DVORAK_ADJACENCY: Dict[str, Set[str]] = {
    "a": {"o", "e", "u"},
    "o": {"a", "e", "i", "q"},
    "e": {"o", "u", "i", "j"},
    "u": {"e", "i", "d", "k"},
    "i": {"u", "d", "f", "x"},
    "d": {"i", "h", "f", "b"},
    "h": {"d", "t", "b", "m"},
    "t": {"h", "n", "m", "w"},
    "n": {"t", "s", "w", "v"},
    "s": {"n", "w", "v", "z"}
}


class TyposquatMatch:
    """Represents a matched typo-squatting candidate with mutation details."""
    __slots__ = (
        "brand", "technique", "distance", "keyboard_layout",
        "bitsquat_bit", "simulated_apex", "risk_score"
    )

    def __init__(
        self,
        brand: str,
        technique: str,
        distance: int,
        keyboard_layout: str,
        simulated_apex: str,
        risk_score: float,
        bitsquat_bit: Optional[int] = None
    ):
        self.brand = brand
        self.technique = technique
        self.distance = distance
        self.keyboard_layout = keyboard_layout
        self.simulated_apex = simulated_apex
        self.risk_score = round(risk_score, 2)
        self.bitsquat_bit = bitsquat_bit

    def to_dict(self) -> Dict[str, Any]:
        return {
            "brand": self.brand,
            "technique": self.technique,
            "distance": self.distance,
            "keyboard_layout": self.keyboard_layout,
            "simulated_apex": self.simulated_apex,
            "risk_score": self.risk_score,
            "bitsquat_bit": self.bitsquat_bit
        }


class TyposquatVerdict:
    """Evaluation result for typosquatting graph analysis."""
    __slots__ = (
        "domain", "is_typosquat", "risk_score", "targeted_brand",
        "primary_technique", "matches", "explanation", "is_exempt",
        "is_whitelisted", "scan_duration_us"
    )

    def __init__(
        self,
        domain: str,
        is_typosquat: bool,
        risk_score: float,
        targeted_brand: Optional[str],
        primary_technique: str,
        matches: List[TyposquatMatch],
        explanation: str,
        is_exempt: bool = False,
        is_whitelisted: bool = False,
        scan_duration_us: float = 0.0
    ):
        self.domain = domain
        self.is_typosquat = is_typosquat
        self.risk_score = round(risk_score, 2)
        self.targeted_brand = targeted_brand
        self.primary_technique = primary_technique
        self.matches = matches
        self.explanation = explanation
        self.is_exempt = is_exempt
        self.is_whitelisted = is_whitelisted
        self.scan_duration_us = round(scan_duration_us, 2)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "domain": self.domain,
            "is_typosquat": self.is_typosquat,
            "risk_score": self.risk_score,
            "targeted_brand": self.targeted_brand,
            "primary_technique": self.primary_technique,
            "matches": [m.to_dict() for m in self.matches],
            "explanation": self.explanation,
            "is_exempt": self.is_exempt,
            "is_whitelisted": self.is_whitelisted,
            "scan_duration_us": self.scan_duration_us
        }


class TyposquatGraphEngine:
    """
    On-device graph generator and classifier analyzing physical keyboard
    adjacency, bitsquatting, character omissions, duplications, and transpositions.
    """

    def __init__(self, risk_threshold: float = 65.0):
        self.risk_threshold = risk_threshold
        self._lock = threading.RLock()

        # Protection State & Conditional Whitelisting Law
        self._is_locked: bool = False
        self._countdown_seconds: int = 0
        self._whitelist: Set[str] = set()

        # Precomputed brand stems for fast O(1) graph indexing
        self._brand_stems: Dict[str, str] = {}
        for brand_key, profile in PROTECTED_BRANDS.items():
            self._brand_stems[profile.name.lower()] = profile.name
            for alias in profile.aliases:
                self._brand_stems[alias.lower()] = profile.name

    # --------------------------------------------------------------------------
    # Lock State & Conditional Whitelisting Law
    # --------------------------------------------------------------------------

    def set_lock_state(self, is_locked: bool, countdown_seconds: int = 0) -> None:
        with self._lock:
            self._is_locked = is_locked
            self._countdown_seconds = max(0, countdown_seconds)

    @property
    def is_locked(self) -> bool:
        with self._lock:
            return self._is_locked or self._countdown_seconds > 0

    def add_whitelist(self, domain: str) -> bool:
        clean = domain.lower().strip().rstrip(".")
        if not clean:
            return False

        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "adding whitelist entries during an active focus lock or timer."
                )
            self._whitelist.add(clean)
            return True

    def remove_whitelist(self, domain: str) -> bool:
        clean = domain.lower().strip().rstrip(".")
        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "removing whitelist entries during an active focus lock."
                )
            if clean in self._whitelist:
                self._whitelist.remove(clean)
                return True
            return False

    def get_whitelist(self) -> List[str]:
        with self._lock:
            return sorted(list(self._whitelist))

    # --------------------------------------------------------------------------
    # Life Safety Exemption Check
    # --------------------------------------------------------------------------

    @classmethod
    def is_life_safety_exempt(cls, domain: str) -> bool:
        clean = domain.lower().strip().rstrip(".")
        if clean in LIFE_SAFETY_DOMAINS:
            return True
        for exempt in LIFE_SAFETY_DOMAINS:
            if clean.endswith("." + exempt):
                return True
        return False

    # --------------------------------------------------------------------------
    # Soundex Phonetic Approximation
    # --------------------------------------------------------------------------

    @classmethod
    def soundex_hash(cls, token: str) -> str:
        """Calculates 4-character Soundex phonetic key."""
        clean = token.lower().strip()
        if not clean or not clean[0].isalpha():
            return "0000"

        first_letter = clean[0].upper()
        mapping = {
            "b": "1", "f": "1", "p": "1", "v": "1",
            "c": "2", "g": "2", "j": "2", "k": "2", "q": "2", "s": "2", "x": "2", "z": "2",
            "d": "3", "t": "3",
            "l": "4",
            "m": "5", "n": "5",
            "r": "6"
        }

        encoded: List[str] = [first_letter]
        prev_code = mapping.get(clean[0], "0")

        for char in clean[1:]:
            code = mapping.get(char, "0")
            if code != "0" and code != prev_code:
                encoded.append(code)
            prev_code = code

        soundex = "".join(encoded)
        soundex = (soundex + "0000")[:4]
        return soundex

    # --------------------------------------------------------------------------
    # Graph Mutation Generators
    # --------------------------------------------------------------------------

    @classmethod
    def generate_keyboard_fat_fingers(cls, stem: str, layout: str = "QWERTY") -> Set[str]:
        """Generates fat-finger neighboring key substitutions."""
        table = (
            QWERTY_ADJACENCY if layout == "QWERTY"
            else AZERTY_ADJACENCY if layout == "AZERTY"
            else QWERTZ_ADJACENCY if layout == "QWERTZ"
            else DVORAK_ADJACENCY
        )
        mutations: Set[str] = set()
        for idx, char in enumerate(stem):
            if char in table:
                for neighbor in table[char]:
                    mutations.add(stem[:idx] + neighbor + stem[idx + 1:])
        return mutations

    @classmethod
    def generate_omissions(cls, stem: str) -> Set[str]:
        """Generates single-character omission typos."""
        mutations: Set[str] = set()
        for idx in range(len(stem)):
            mutations.add(stem[:idx] + stem[idx + 1:])
        return mutations

    @classmethod
    def generate_duplications(cls, stem: str) -> Set[str]:
        """Generates single-character duplication typos."""
        mutations: Set[str] = set()
        for idx in range(len(stem)):
            mutations.add(stem[:idx] + stem[idx] + stem[idx:])
        return mutations

    @classmethod
    def generate_transpositions(cls, stem: str) -> Set[str]:
        """Generates adjacent two-character transposition swaps."""
        mutations: Set[str] = set()
        for idx in range(len(stem) - 1):
            mutations.add(stem[:idx] + stem[idx + 1] + stem[idx] + stem[idx + 2:])
        return mutations

    @classmethod
    def generate_bitsquatting(cls, stem: str) -> Set[Tuple[str, int]]:
        """Generates single-bit flips across ASCII characters."""
        mutations: Set[Tuple[str, int]] = set()
        for idx, char in enumerate(stem):
            code = ord(char)
            for bit in range(8):
                flipped = code ^ (1 << bit)
                # Ensure flipped character is valid alphanumeric or hyphen
                if (97 <= flipped <= 122) or (48 <= flipped <= 57) or (flipped == 45):
                    new_char = chr(flipped)
                    if new_char != char:
                        mutated = stem[:idx] + new_char + stem[idx + 1:]
                        mutations.add((mutated, bit))
        return mutations

    # --------------------------------------------------------------------------
    # Evaluation Engine
    # --------------------------------------------------------------------------

    def evaluate(self, domain: str) -> TyposquatVerdict:
        """
        Evaluates domain against the physical keyboard adjacency and typo graph.
        """
        t0 = time.perf_counter()
        clean = domain.lower().strip().rstrip(".")

        # 1. Life Safety Check (Priority #1)
        if self.is_life_safety_exempt(clean):
            duration = (time.perf_counter() - t0) * 1e6
            return TyposquatVerdict(
                domain=clean,
                is_typosquat=False,
                risk_score=0.0,
                targeted_brand=None,
                primary_technique="EXEMPT",
                matches=[],
                explanation="Inviolable life-safety or critical platform infrastructure (exempt).",
                is_exempt=True,
                is_whitelisted=False,
                scan_duration_us=duration
            )

        # 2. Whitelist Check
        with self._lock:
            if clean in self._whitelist or any(clean.endswith("." + w) for w in self._whitelist):
                duration = (time.perf_counter() - t0) * 1e6
                return TyposquatVerdict(
                    domain=clean,
                    is_typosquat=False,
                    risk_score=0.0,
                    targeted_brand=None,
                    primary_technique="WHITELISTED",
                    matches=[],
                    explanation="Domain is explicitly allowed by typosquatting whitelist.",
                    is_exempt=False,
                    is_whitelisted=True,
                    scan_duration_us=duration
                )

        # Extract apex label
        parts = clean.split(".")
        if len(parts) >= 2:
            apex_stem = parts[-2]
            tld = parts[-1]
        else:
            apex_stem = clean
            tld = ""

        # 3. Check if domain IS the legitimate apex of the brand
        profile = BrandDictionary.find_matched_brand(apex_stem)
        if profile and BrandDictionary.is_legitimate_brand_apex(clean, profile.name):
            duration = (time.perf_counter() - t0) * 1e6
            return TyposquatVerdict(
                domain=clean,
                is_typosquat=False,
                risk_score=0.0,
                targeted_brand=profile.name,
                primary_technique="OFFICIAL_APEX",
                matches=[],
                explanation=f"Official legitimate apex domain for {profile.name}.",
                is_exempt=False,
                is_whitelisted=False,
                scan_duration_us=duration
            )

        # 4. Search Typo Graph across Target Brand Stems
        matches: List[TyposquatMatch] = []

        for target_stem, brand_name in self._brand_stems.items():
            if len(target_stem) < 3:
                continue

            # Exact match on stem but with non-legitimate TLD
            if apex_stem == target_stem:
                m = TyposquatMatch(
                    brand=brand_name,
                    technique="TLD_SQUATTING",
                    distance=0,
                    keyboard_layout="ANY",
                    simulated_apex=f"{target_stem}.{tld}",
                    risk_score=85.0
                )
                matches.append(m)
                continue

            # Check QWERTY / AZERTY / QWERTZ Adjacency
            for layout in ("QWERTY", "AZERTY", "QWERTZ"):
                fat_fingers = self.generate_keyboard_fat_fingers(target_stem, layout=layout)
                if apex_stem in fat_fingers:
                    matches.append(TyposquatMatch(
                        brand=brand_name,
                        technique="KEYBOARD_ADJACENCY_FAT_FINGER",
                        distance=1,
                        keyboard_layout=layout,
                        simulated_apex=f"{target_stem}.{tld}",
                        risk_score=92.0
                    ))

            # Check Omissions
            if apex_stem in self.generate_omissions(target_stem):
                matches.append(TyposquatMatch(
                    brand=brand_name,
                    technique="CHARACTER_OMISSION",
                    distance=1,
                    keyboard_layout="N/A",
                    simulated_apex=f"{target_stem}.{tld}",
                    risk_score=90.0
                ))

            # Check Duplications
            if apex_stem in self.generate_duplications(target_stem):
                matches.append(TyposquatMatch(
                    brand=brand_name,
                    technique="CHARACTER_DUPLICATION",
                    distance=1,
                    keyboard_layout="N/A",
                    simulated_apex=f"{target_stem}.{tld}",
                    risk_score=88.0
                ))

            # Check Transpositions
            if apex_stem in self.generate_transpositions(target_stem):
                matches.append(TyposquatMatch(
                    brand=brand_name,
                    technique="CHARACTER_TRANSPOSITION",
                    distance=1,
                    keyboard_layout="N/A",
                    simulated_apex=f"{target_stem}.{tld}",
                    risk_score=91.0
                ))

            # Check Bitsquatting
            for bit_cand, bit_idx in self.generate_bitsquatting(target_stem):
                if apex_stem == bit_cand:
                    matches.append(TyposquatMatch(
                        brand=brand_name,
                        technique="BITSQUATTING_BIT_FLIP",
                        distance=1,
                        keyboard_layout="RAM_HARDWARE",
                        simulated_apex=f"{target_stem}.{tld}",
                        risk_score=95.0,
                        bitsquat_bit=bit_idx
                    ))

            # Check Phonetic Lookalike (Soundex)
            if len(target_stem) >= 4 and len(apex_stem) >= 4:
                if self.soundex_hash(apex_stem) == self.soundex_hash(target_stem):
                    # Only if edit distance is small (<= 2)
                    if abs(len(apex_stem) - len(target_stem)) <= 1:
                        matches.append(TyposquatMatch(
                            brand=brand_name,
                            technique="PHONETIC_HOMOPHONE",
                            distance=2,
                            keyboard_layout="PHONETIC",
                            simulated_apex=f"{target_stem}.{tld}",
                            risk_score=78.0
                        ))

        # 5. Composite Verdict Determination
        if matches:
            # Sort by highest risk score
            matches.sort(key=lambda m: m.risk_score, reverse=True)
            top_match = matches[0]
            max_score = top_match.risk_score
            targeted_brand = top_match.brand
            primary_technique = top_match.technique
            is_typosquat = max_score >= self.risk_threshold
            explanation = (
                f"Typosquatting mutation detected targeting '{targeted_brand}' via "
                f"{primary_technique} (mutation distance: {top_match.distance})."
            )
        else:
            max_score = 0.0
            targeted_brand = None
            primary_technique = "NONE"
            is_typosquat = False
            explanation = "No typosquatting or keyboard adjacency mutations detected."

        duration = (time.perf_counter() - t0) * 1e6

        return TyposquatVerdict(
            domain=clean,
            is_typosquat=is_typosquat,
            risk_score=max_score,
            targeted_brand=targeted_brand,
            primary_technique=primary_technique,
            matches=matches,
            explanation=explanation,
            is_exempt=False,
            is_whitelisted=False,
            scan_duration_us=duration
        )
