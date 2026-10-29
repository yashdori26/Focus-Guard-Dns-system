"""
FocusDNS AI Engine - Fast Tokenizer & Character N-Gram Analysis
Provides sub-millisecond lexical tokenization, character-level n-gram transitions,
and distance metrics (Damerau-Levenshtein, Jaro-Winkler, physical keyboard adjacency)
optimized for on-device threat hunting and zero-day phishing detection.
"""

import math
import re
from typing import List, Dict, Set, Tuple, Optional


class FastTokenizer:
    """
    High-performance sub-word and lexical tokenizer for internet domain names.
    Splits labels on boundaries (dots, hyphens, underscores, digit-letter transitions,
    camelCase transitions, and dictionary sub-words).
    """

    # Common prefixes and suffixes in internet domains
    COMMON_AFFIXES = {
        "prefixes": {"login", "signin", "auth", "secure", "verify", "account", "update", "service", "portal", "my", "web", "app", "api", "cdn", "dns", "ns", "mail"},
        "suffixes": {"online", "center", "portal", "support", "help", "security", "alert", "service", "desk", "hub", "zone", "net", "app", "cloud", "tech"},
    }

    # Transition regex for splitting CamelCase and alphanumeric boundaries
    SPLIT_REGEX = re.compile(r"([a-z]+|[A-Z][a-z]*|[0-9]+|[^a-zA-Z0-9]+)")

    def __init__(self, vocabulary: Optional[Set[str]] = None):
        self.vocabulary: Set[str] = set(vocabulary) if vocabulary else set()
        self._cache: Dict[str, List[str]] = {}
        self._max_cache_size = 5000

    def tokenize(self, domain: str) -> List[str]:
        """
        Tokenizes domain into sub-word tokens.
        Example: 'secure-apple-login24.com' -> ['secure', 'apple', 'login', '24', 'com']
        """
        domain = domain.lower().strip().rstrip(".")
        if not domain:
            return []

        if domain in self._cache:
            return list(self._cache[domain])

        tokens: List[str] = []
        labels = domain.split(".")
        for label in labels:
            if not label:
                continue
            # Split by hyphens and underscores
            parts = re.split(r"[-_]+", label)
            for part in parts:
                if not part:
                    continue
                # Split by character type transitions (letters vs digits)
                sub_parts = self.SPLIT_REGEX.findall(part)
                for sp in sub_parts:
                    sp_clean = sp.strip()
                    if sp_clean:
                        tokens.append(sp_clean)

        if len(self._cache) >= self._max_cache_size:
            self._cache.clear()
        self._cache[domain] = tokens
        return list(tokens)

    def extract_ngrams(self, text: str, n: int = 3) -> List[str]:
        """
        Extracts character n-grams from text.
        Example: 'apple', n=3 -> ['app', 'ppl', 'ple']
        """
        text = text.lower().strip()
        if len(text) < n:
            return [text] if text else []
        return [text[i : i + n] for i in range(len(text) - n + 1)]

    def extract_skipgrams(self, text: str, n: int = 2, k: int = 1) -> List[str]:
        """
        Extracts (n, k)-skipgrams from text (n characters with up to k skips).
        """
        text = text.lower().strip()
        length = len(text)
        if length < n:
            return []
        skipgrams = []
        for i in range(length):
            for d in range(1, k + 2):
                if i + d < length:
                    skipgrams.append(f"{text[i]}{text[i + d]}")
        return skipgrams

    def character_frequencies(self, text: str) -> Dict[str, float]:
        """
        Returns normalized relative character frequency distribution.
        """
        if not text:
            return {}
        total = float(len(text))
        freqs: Dict[str, int] = {}
        for char in text:
            freqs[char] = freqs.get(char, 0) + 1
        return {char: count / total for char, count in freqs.items()}

    def shannon_entropy(self, text: str) -> float:
        """
        Calculates Shannon entropy in bits per character.
        H(X) = -sum(p(x) * log2(p(x)))
        """
        if not text:
            return 0.0
        freqs = self.character_frequencies(text)
        entropy = 0.0
        for p in freqs.values():
            if p > 0:
                entropy -= p * math.log2(p)
        return round(entropy, 4)

    def kolmogorov_complexity_estimate(self, text: str) -> float:
        """
        Approximates normalized Kolmogorov complexity using run-length and repetitive dictionary ratio.
        Values closer to 1.0 indicate high algorithmic complexity (e.g. DGA);
        values closer to 0.0 indicate highly repetitive or structured patterns.
        """
        if not text:
            return 0.0
        n = len(text)
        if n == 1:
            return 0.1

        # Run-length transitions
        transitions = 0
        for i in range(1, n):
            if text[i] != text[i - 1]:
                transitions += 1

        # Distinct 2-grams ratio
        bigrams = self.extract_ngrams(text, 2)
        distinct_bigrams = len(set(bigrams))
        max_possible_bigrams = max(1, n - 1)
        bigram_ratio = distinct_bigrams / max_possible_bigrams

        transition_ratio = transitions / (n - 1)
        complexity = (0.5 * transition_ratio) + (0.5 * bigram_ratio)
        return round(min(1.0, max(0.0, complexity)), 4)

    def vowel_consonant_ratio(self, text: str) -> Tuple[float, int, int]:
        """
        Calculates vowel to consonant ratio and counts.
        Returns: (ratio, vowel_count, consonant_count)
        """
        vowels = set("aeiou")
        v_count = 0
        c_count = 0
        for ch in text.lower():
            if ch in vowels:
                v_count += 1
            elif "a" <= ch <= "z":
                c_count += 1

        total_letters = v_count + c_count
        ratio = (v_count / float(total_letters)) if total_letters > 0 else 0.0
        return round(ratio, 4), v_count, c_count

    def max_consecutive_consonants(self, text: str) -> int:
        """
        Calculates maximum consecutive consonants in string.
        High values (> 4) are strong indicators of DGA domains.
        """
        vowels = set("aeiou")
        max_cons = 0
        curr_cons = 0
        for ch in text.lower():
            if "a" <= ch <= "z" and ch not in vowels:
                curr_cons += 1
                if curr_cons > max_cons:
                    max_cons = curr_cons
            else:
                curr_cons = 0
        return max_cons

    def max_consecutive_digits(self, text: str) -> int:
        """
        Calculates maximum consecutive digits in string.
        """
        max_digits = 0
        curr_digits = 0
        for ch in text:
            if ch.isdigit():
                curr_digits += 1
                if curr_digits > max_digits:
                    max_digits = curr_digits
            else:
                curr_digits = 0
        return max_digits


class FastDistanceMetrics:
    """
    Sub-millisecond distance metrics optimized for brand spoofing and typo-squatting detection.
    """

    @staticmethod
    def damerau_levenshtein(s1: str, s2: str, max_distance: int = 5) -> int:
        """
        Computes the true Damerau-Levenshtein distance (insertion, deletion,
        substitution, and adjacent transposition) with early exit.
        """
        len1, len2 = len(s1), len(s2)
        if abs(len1 - len2) > max_distance:
            return max_distance + 1

        if s1 == s2:
            return 0
        if not s1:
            return len2
        if not s2:
            return len1

        # Matrix initialization
        da: Dict[str, int] = {}
        row_count = len1 + 2
        col_count = len2 + 2

        # Flattened grid
        d = [[0] * col_count for _ in range(row_count)]
        max_dist = len1 + len2
        d[0][0] = max_dist

        for i in range(1, row_count):
            d[i][0] = max_dist
            d[i][1] = i - 1
        for j in range(1, col_count):
            d[0][j] = max_dist
            d[1][j] = j - 1

        for i in range(1, len1 + 1):
            db = 0
            for j in range(1, len2 + 1):
                i1 = da.get(s2[j - 1], 0)
                j1 = db
                cost = 0 if s1[i - 1] == s2[j - 1] else 1
                if cost == 0:
                    db = j

                d[i + 1][j + 1] = min(
                    d[i][j + 1] + 1,  # Deletion
                    d[i + 1][j] + 1,  # Insertion
                    d[i][j] + cost,   # Substitution
                    d[i1][j1] + (i - i1 - 1) + 1 + (j - j1 - 1),  # Transposition
                )
            da[s1[i - 1]] = i

        return d[len1 + 1][len2 + 1]

    @staticmethod
    def jaro_winkler(s1: str, s2: str, prefix_weight: float = 0.1) -> float:
        """
        Computes the Jaro-Winkler similarity metric (0.0 to 1.0).
        High values (> 0.88) indicate high likelihood of typo-squatting or brand impersonation.
        """
        if s1 == s2:
            return 1.0

        len1, len2 = len(s1), len(s2)
        if len1 == 0 or len2 == 0:
            return 0.0

        match_distance = max(len1, len2) // 2 - 1
        s1_matches = [False] * len1
        s2_matches = [False] * len2

        matches = 0
        for i in range(len1):
            start = max(0, i - match_distance)
            end = min(i + match_distance + 1, len2)
            for j in range(start, end):
                if s2_matches[j] or s1[i] != s2[j]:
                    continue
                s1_matches[i] = True
                s2_matches[j] = True
                matches += 1
                break

        if matches == 0:
            return 0.0

        transpositions = 0
        k = 0
        for i in range(len1):
            if not s1_matches[i]:
                continue
            while not s2_matches[k]:
                k += 1
            if s1[i] != s2[k]:
                transpositions += 1
            k += 1

        jaro = (
            (matches / len1)
            + (matches / len2)
            + ((matches - transpositions / 2.0) / matches)
        ) / 3.0

        # Winkler prefix boost (up to 4 matching characters)
        prefix_len = 0
        for c1, c2 in zip(s1[:4], s2[:4]):
            if c1 == c2:
                prefix_len += 1
            else:
                break

        jaro_winkler = jaro + (prefix_len * prefix_weight * (1.0 - jaro))
        return round(min(1.0, max(0.0, jaro_winkler)), 4)

    @staticmethod
    def keyboard_adjacency_distance(s1: str, s2: str) -> float:
        """
        Calculates normalized physical distance on a standard QWERTY layout.
        Allows detecting fat-finger typing errors (e.g., 'g' -> 'f' or 'h' or 't').
        """
        if s1 == s2:
            return 0.0

        keyboard_coords: Dict[str, Tuple[int, int]] = {
            "1": (0, 0), "2": (0, 1), "3": (0, 2), "4": (0, 3), "5": (0, 4), "6": (0, 5), "7": (0, 6), "8": (0, 7), "9": (0, 8), "0": (0, 9),
            "q": (1, 0), "w": (1, 1), "e": (1, 2), "r": (1, 3), "t": (1, 4), "y": (1, 5), "u": (1, 6), "i": (1, 7), "o": (1, 8), "p": (1, 9),
            "a": (2, 0), "s": (2, 1), "d": (2, 2), "f": (2, 3), "g": (2, 4), "h": (2, 5), "j": (2, 6), "k": (2, 7), "l": (2, 8),
            "z": (3, 0), "x": (3, 1), "c": (3, 2), "v": (3, 3), "b": (3, 4), "n": (3, 5), "m": (3, 6),
        }

        # If lengths differ by 1, check insertion/deletion adjacent to neighbor
        len1, len2 = len(s1), len(s2)
        if abs(len1 - len2) > 1:
            return 10.0

        # Exact 1-character substitution check
        if len1 == len2:
            diff_indices = [i for i in range(len1) if s1[i] != s2[i]]
            if len(diff_indices) == 1:
                idx = diff_indices[0]
                c1, c2 = s1[idx].lower(), s2[idx].lower()
                if c1 in keyboard_coords and c2 in keyboard_coords:
                    x1, y1 = keyboard_coords[c1]
                    x2, y2 = keyboard_coords[c2]
                    euclidean = math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2)
                    return round(euclidean, 3)

        return 5.0
