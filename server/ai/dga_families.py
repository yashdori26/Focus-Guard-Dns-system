"""
FocusDNS AI Engine - DGA (Domain Generation Algorithm) Malware Profiles & Generator.

Maintains structural signatures, mathematical generators, and characteristic profiles
for 20+ documented malware DGA families to enable on-device classification and testing:
  - Conficker (A/B), GameOver Zeus, Necurs, Mirai, Matsnu, Suppobox, Bamital,
    Qakbot, Locky, Rovnix, Ramnit, Banjori, Shiotob, Tinba, Pykspa, Ranbyus,
    Nymaim, Simda, Dircrypt, Murofet.
"""

import time
import hashlib
from typing import Dict, List, Set, Optional, Tuple, Any


class DgaFamilyProfile:
    """Represents the statistical and architectural signature of a DGA family."""
    __slots__ = (
        "name", "type", "length_range", "tlds", "char_set",
        "has_vowels", "is_dictionary_based", "description"
    )

    def __init__(
        self,
        name: str,
        dga_type: str,
        length_range: Tuple[int, int],
        tlds: List[str],
        char_set: str,
        has_vowels: bool = True,
        is_dictionary_based: bool = False,
        description: str = ""
    ):
        self.name = name
        self.type = dga_type.upper()  # RANDOM_ALPHANUMERIC, DICTIONARY, HEX, PERMUTATION
        self.length_range = length_range
        self.tlds = tlds
        self.char_set = char_set
        self.has_vowels = has_vowels
        self.is_dictionary_based = is_dictionary_based
        self.description = description


# Dictionary words used by dictionary-based DGA malware (Matsnu, Suppobox)
SAMPLE_DGA_WORDS: List[str] = [
    "black", "stone", "water", "river", "white", "house", "light", "shadow",
    "green", "forest", "mountain", "eagle", "falcon", "silver", "golden",
    "winter", "summer", "autumn", "spring", "dragon", "cloud", "storm",
    "fire", "shield", "sword", "castle", "bridge", "tower", "valley"
]

# Profiles for 20 Known DGA Malware Families
DGA_FAMILIES: Dict[str, DgaFamilyProfile] = {
    "conficker": DgaFamilyProfile(
        name="Conficker",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(5, 12),
        tlds=["com", "net", "org", "info", "biz", "cc", "cn"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Linear Congruential Generator (LCG) based on date"
    ),
    "gameover_zeus": DgaFamilyProfile(
        name="GameOver Zeus (GOZ)",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(16, 32),
        tlds=["com", "net", "org", "biz", "info"],
        char_set="abcdefghijklmnopqrstuvwxyz0123456789",
        description="High-entropy P2P C2 rendezvous algorithm"
    ),
    "necurs": DgaFamilyProfile(
        name="Necurs",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(9, 19),
        tlds=["com", "net", "org", "ru", "biz", "co.uk"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Spam and banking trojan botnet DGA"
    ),
    "mirai": DgaFamilyProfile(
        name="Mirai",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(8, 14),
        tlds=["cc", "su", "xyz", "top"],
        char_set="abcdefghijklmnopqrstuvwxyz0123456789",
        description="IoT botnet dynamic DNS rendezvous"
    ),
    "matsnu": DgaFamilyProfile(
        name="Matsnu",
        dga_type="DICTIONARY",
        length_range=(12, 28),
        tlds=["com", "net", "org", "de"],
        char_set="abcdefghijklmnopqrstuvwxyz-",
        is_dictionary_based=True,
        description="Concatenates 2 to 3 English words with hyphens"
    ),
    "suppobox": DgaFamilyProfile(
        name="Suppobox",
        dga_type="DICTIONARY",
        length_range=(10, 24),
        tlds=["net", "com"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        is_dictionary_based=True,
        description="Concatenates two dictionary words without separators"
    ),
    "bamital": DgaFamilyProfile(
        name="Bamital",
        dga_type="HEX",
        length_range=(12, 12),
        tlds=["com", "net", "info", "org"],
        char_set="0123456789abcdef",
        has_vowels=False,
        description="Fixed 12-character MD5-derived hexadecimal string"
    ),
    "qakbot": DgaFamilyProfile(
        name="Qakbot",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(15, 25),
        tlds=["com", "net", "org", "biz", "info"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Banking trojan generating low-vowel pseudorandom strings"
    ),
    "locky": DgaFamilyProfile(
        name="Locky",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(10, 18),
        tlds=["xyz", "top", "pw", "click", "work"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Ransomware C2 failover generator"
    ),
    "rovnix": DgaFamilyProfile(
        name="Rovnix",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(12, 22),
        tlds=["info", "biz", "org", "com"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Rootkit VBR bootkit C2 beacon"
    ),
    "ramnit": DgaFamilyProfile(
        name="Ramnit",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(8, 16),
        tlds=["com", "net", "org", "biz"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Banking worm LCG seed generator"
    ),
    "banjori": DgaFamilyProfile(
        name="Banjori",
        dga_type="PERMUTATION",
        length_range=(14, 22),
        tlds=["com"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Appends incremental character permutation to seed"
    ),
    "shiotob": DgaFamilyProfile(
        name="Shiotob",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(12, 18),
        tlds=["net", "biz", "org", "info"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Infostealer utilizing daily rotating TLDs"
    ),
    "tinba": DgaFamilyProfile(
        name="Tinba",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(12, 12),
        tlds=["com", "net", "biz", "ru"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Tiny Banker trojan 12-char LCG DGA"
    ),
    "pykspa": DgaFamilyProfile(
        name="Pykspa",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(8, 14),
        tlds=["com", "net", "org", "info"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Skype worm pseudo-pronounceable DGA"
    ),
    "ranbyus": DgaFamilyProfile(
        name="Ranbyus",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(11, 17),
        tlds=["net", "org", "com"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Smartcard credential stealer C2"
    ),
    "nymaim": DgaFamilyProfile(
        name="Nymaim",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(8, 13),
        tlds=["com", "net", "org", "biz"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Two-stage payload dropper DGA"
    ),
    "simda": DgaFamilyProfile(
        name="Simda",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(10, 20),
        tlds=["com", "net", "info", "ru"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Botnet generating short TTL C2s"
    ),
    "dircrypt": DgaFamilyProfile(
        name="Dircrypt",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(10, 16),
        tlds=["com", "net"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Ransomware DGA with monthly salt updates"
    ),
    "murofet": DgaFamilyProfile(
        name="Murofet",
        dga_type="RANDOM_ALPHANUMERIC",
        length_range=(9, 15),
        tlds=["com", "net", "biz", "info", "org"],
        char_set="abcdefghijklmnopqrstuvwxyz",
        description="Zues variant botnet DGA"
    )
}


class DgaGenerator:
    """
    Deterministic synthetic generator producing authentic DGA domains
    for testing, validation, and on-device model calibration.
    """

    @classmethod
    def generate_domain(cls, family_name: str, seed: int = 12345) -> str:
        """Generates a synthetic domain matching the specific DGA family profile."""
        clean_name = family_name.lower().strip()
        profile = DGA_FAMILIES.get(clean_name, DGA_FAMILIES["conficker"])

        # Deterministic PRNG from seed
        prng_state = seed & 0xFFFFFFFF

        def next_rand(max_val: int) -> int:
            nonlocal prng_state
            prng_state = (prng_state * 1664525 + 1013904223) & 0xFFFFFFFF
            return prng_state % max(1, max_val)

        if profile.type == "DICTIONARY":
            # Pick 2 words
            w1 = SAMPLE_DGA_WORDS[next_rand(len(SAMPLE_DGA_WORDS))]
            w2 = SAMPLE_DGA_WORDS[next_rand(len(SAMPLE_DGA_WORDS))]
            sep = "-" if profile.name == "Matsnu" else ""
            label = f"{w1}{sep}{w2}"
        elif profile.type == "HEX":
            # Generate MD5 hex chunk
            h = hashlib.md5(str(seed).encode()).hexdigest()
            target_len = profile.length_range[0]
            label = h[:target_len]
        else:
            # Random Alphanumeric or Permutation
            min_len, max_len = profile.length_range
            target_len = min_len + next_rand(max_len - min_len + 1)
            chars = []
            for _ in range(target_len):
                idx = next_rand(len(profile.char_set))
                chars.append(profile.char_set[idx])
            label = "".join(chars)

        tld = profile.tlds[next_rand(len(profile.tlds))]
        return f"{label}.{tld}"

    @classmethod
    def get_supported_families(cls) -> List[str]:
        """Returns list of all supported DGA malware family names."""
        names = set(DGA_FAMILIES.keys())
        for p in DGA_FAMILIES.values():
            names.add(p.name)
        return sorted(list(names))

    generate = generate_domain


class DGAFamilyRegistry:
    """Registry facade for malware DGA family profiles."""

    @staticmethod
    def get_supported_families() -> List[str]:
        return DgaGenerator.get_supported_families()

    @staticmethod
    def get_family_profile(name: str) -> Optional[DgaFamilyProfile]:
        clean = name.lower().strip()
        if clean in DGA_FAMILIES:
            return DGA_FAMILIES[clean]
        for p in DGA_FAMILIES.values():
            if p.name.lower() == clean:
                return p
        return None


SyntheticDGAGenerator = DgaGenerator
