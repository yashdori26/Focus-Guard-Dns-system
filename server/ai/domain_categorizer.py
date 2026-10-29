"""
FocusDNS AI Engine - Dynamic Multi-Class Domain Categorizer.

Automatically classifies previously unindexed domains into standardized IAB
categories in real time using lexical tokenization, sub-word segmentation,
and weighted TF-IDF likelihood distributions.

Categories:
  - GAMING, SOCIAL_MEDIA, ADULT_CONTENT, PRODUCTIVITY_WORK,
    SHOPPING_ECOMMERCE, STREAMING_ENTERTAINMENT, CRYPTO_GAMBLING, MALWARE_THREAT.
"""

import math
import re
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.category_lexicon import (
    CATEGORY_VOCABULARY, TLD_CATEGORY_PRIORS, ALL_CATEGORIES,
    CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_PRODUCTIVITY,
    CAT_SHOPPING, CAT_STREAMING, CAT_CRYPTO_GAMBLING, CAT_MALWARE, CAT_UNCATEGORIZED
)

# Categories considered high-distraction during Deep Focus Sessions
DISTRACTING_CATEGORIES: Set[str] = {
    CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_STREAMING, CAT_CRYPTO_GAMBLING
}


class CategoryVerdict:
    """Structured result returned by the Dynamic Domain Categorizer."""
    __slots__ = (
        "primary_category", "confidence", "is_distracting",
        "category_probabilities", "matched_tokens", "domain", "explanation"
    )

    def __init__(
        self,
        primary_category: str,
        confidence: float,
        is_distracting: bool,
        category_probabilities: Dict[str, float],
        matched_tokens: Dict[str, List[str]],
        domain: str,
        explanation: str
    ):
        self.primary_category = primary_category
        self.confidence = round(confidence, 4)
        self.is_distracting = is_distracting
        self.category_probabilities = category_probabilities
        self.matched_tokens = matched_tokens
        self.domain = domain
        self.explanation = explanation

    def to_dict(self) -> Dict[str, Any]:
        return {
            "primary_category": self.primary_category,
            "confidence": self.confidence,
            "is_distracting": self.is_distracting,
            "category_probabilities": self.category_probabilities,
            "matched_tokens": self.matched_tokens,
            "domain": self.domain,
            "explanation": self.explanation
        }


class DomainCategorizer:
    """
    On-device lexical and sub-word domain categorizer.
    """

    @classmethod
    def tokenize_domain(cls, domain: str) -> List[Tuple[str, float]]:
        """
        Extracts sub-words and assigns structural position weights:
        - Apex registered domain: 2.0x weight
        - Subdomains: 1.0x weight
        """
        clean = domain.lower().strip().rstrip(".")
        parts = clean.split(".")
        if not parts:
            return []

        weighted_tokens: List[Tuple[str, float]] = []

        # Analyze labels
        for idx, part in enumerate(parts):
            # Apex label has highest semantic weight
            is_apex = (idx == len(parts) - 2) if len(parts) >= 2 else True
            weight = 2.0 if is_apex else 1.0

            # 1. Split on hyphens and underscores
            subparts = re.split(r"[-_]", part)
            for sp in subparts:
                if len(sp) >= 2:
                    weighted_tokens.append((sp, weight))

                # 2. Split letter/digit transitions (e.g. 'bet365' -> 'bet', '365')
                chunks = re.findall(r"[a-z]+|\d+", sp)
                if len(chunks) > 1:
                    for ch in chunks:
                        if len(ch) >= 2:
                            weighted_tokens.append((ch, weight * 0.9))

                # 3. Sub-word dictionary scanning (e.g. 'steamcommunity' -> 'steam', 'community')
                for cat_vocab in CATEGORY_VOCABULARY.values():
                    for kw in cat_vocab.keys():
                        if len(kw) >= 4 and kw in sp and kw != sp:
                            weighted_tokens.append((kw, weight * 0.85))

        return weighted_tokens

    @classmethod
    def classify(cls, domain: str) -> CategoryVerdict:
        """
        Classifies domain into 8 categories with probability distribution.
        """
        clean = domain.lower().strip().rstrip(".")
        tokens = cls.tokenize_domain(clean)

        raw_scores: Dict[str, float] = {cat: 0.1 for cat in ALL_CATEGORIES}  # Laplace prior
        matched_tokens: Dict[str, List[str]] = {cat: [] for cat in ALL_CATEGORIES}

        # 1. Accumulate weighted keyword scores
        for token, token_weight in tokens:
            for cat, vocab in CATEGORY_VOCABULARY.items():
                if token in vocab:
                    kw_weight = vocab[token] * token_weight
                    raw_scores[cat] += kw_weight
                    if token not in matched_tokens[cat]:
                        matched_tokens[cat].append(token)

        # 2. Apply TLD Prior Boost
        tld = clean.split(".")[-1] if "." in clean else ""
        if tld in TLD_CATEGORY_PRIORS:
            prior_cat = TLD_CATEGORY_PRIORS[tld]
            raw_scores[prior_cat] += 4.5
            matched_tokens[prior_cat].append(f".{tld}")

        # 3. Softmax / Normalization to generate probabilities
        # exp(score) / sum(exp(scores)) with scaling factor
        scale = 0.5
        max_score = max(raw_scores.values())
        exp_scores = {cat: math.exp((score - max_score) * scale) for cat, score in raw_scores.items()}
        total_exp = sum(exp_scores.values())
        probabilities = {cat: round(exp_scores[cat] / total_exp, 4) for cat in ALL_CATEGORIES}

        # 4. Rank categories
        ranked = sorted(probabilities.items(), key=lambda x: x[1], reverse=True)
        top_cat, top_prob = ranked[0]

        # Check if score difference is significant enough to claim a category
        total_matched = sum(len(m) for m in matched_tokens.values())
        if total_matched == 0 or top_prob < 0.22:
            primary_cat = CAT_UNCATEGORIZED
            confidence = 0.50
            explanation = "Domain contains insufficient lexical tokens for conclusive classification."
        else:
            primary_cat = top_cat
            confidence = top_prob
            matched_str = ", ".join(matched_tokens[primary_cat][:4])
            explanation = f"Classified as '{primary_cat}' with {confidence * 100:.1f}% confidence. Matches: [{matched_str}]."

        is_distracting = primary_cat in DISTRACTING_CATEGORIES

        return CategoryVerdict(
            primary_category=primary_cat,
            confidence=confidence,
            is_distracting=is_distracting,
            category_probabilities=probabilities,
            matched_tokens={k: v for k, v in matched_tokens.items() if v},
            domain=domain,
            explanation=explanation
        )

    predict = classify


CategoryPrediction = CategoryVerdict
