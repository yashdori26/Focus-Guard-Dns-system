"""
FocusDNS AI Engine - On-Device Continuous Adaptive Learner & Safety Watchdog.

Enables safe, localized online learning and weight adaptation directly on-device
without transmitting telemetry or training data to any remote cloud servers.

Guarantees & Safeguards:
  1. Safe Learning Invariants:
     - Learning rate bounded to alpha <= 0.01
     - Individual weight delta clipped: |delta_w| <= 0.05 per training step
     - L2 weight regularization (lambda = 0.001) preventing weight explosion
  2. Automatic Benchmark Watchdog & Rollback:
     - Evaluates golden verification domains after weight updates.
     - If benign benchmark accuracy drops or emergency domains are affected,
       weights are instantly and automatically rolled back to the prior checkpoint.
  3. Life Safety Exemption:
     - Emergency services (911.gov, 112.gov, push.apple.com, update.microsoft.com,
       play.googleapis.com) are hardcoded EXEMPT and cannot be trained as threats.
  4. Conditional Whitelisting Law:
     - Training samples from whitelist feedback are permitted when idle;
       strictly forbidden and raises PermissionError("ERROR_ACCESS_DENIED (5)")
       if an active focus session or countdown timer is running.
"""

import time
import math
import copy
import threading
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.fast_tokenizer import FastTokenizer

# Hardcoded Life Safety Exemptions
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "push.apple.com",
    "update.microsoft.com",
    "play.googleapis.com"
}

# Golden Benchmark Verification Suite for Model Sanity Watchdog
GOLDEN_BENCHMARK_SUITE: List[Tuple[str, int]] = [
    # (domain, expected_label: 0 = Benign, 1 = Threat)
    ("apple.com", 0),
    ("google.com", 0),
    ("wikipedia.org", 0),
    ("github.com", 0),
    ("update.microsoft.com", 0),
    ("аpple.com", 1),  # Cyrillic homograph
    ("gооgle.com", 1),  # Cyrillic homograph
    ("bcdfghjklmnpqrstvwxyz.org", 1),  # Zero-vowel DGA
    ("qzxwkjvnmpltr.biz", 1),  # High-entropy DGA
]


class AdaptiveLearningSample:
    """Represents a single verified labeled training sample."""
    __slots__ = ("domain", "features", "target_label", "weight", "source", "timestamp")

    def __init__(
        self,
        domain: str,
        features: List[float],
        target_label: int,  # 0 = Benign, 1 = Threat
        weight: float = 1.0,
        source: str = "USER_FEEDBACK",
        timestamp: Optional[float] = None
    ):
        self.domain = domain.lower().strip()
        self.features = features
        self.target_label = target_label
        self.weight = weight
        self.source = source
        self.timestamp = timestamp or time.time()


class AdaptiveLearner:
    """
    On-device continuous adaptive learning engine with safety boundaries
    and automatic checkpoint rollback watchdog.
    """

    def __init__(
        self,
        num_features: int = 16,
        learning_rate: float = 0.005,
        l2_lambda: float = 0.001,
        max_delta_clip: float = 0.05
    ):
        self.num_features = num_features
        self.learning_rate = min(0.01, max(0.0001, learning_rate))
        self.l2_lambda = l2_lambda
        self.max_delta_clip = max_delta_clip

        self._lock = threading.RLock()

        # Protection State & Conditional Whitelisting Law
        self._is_locked: bool = False
        self._countdown_seconds: int = 0
        self._whitelist: Set[str] = set()

        # Local model weights: vector of weights and scalar bias
        self._weights: List[float] = [0.15] * num_features
        self._bias: float = -0.50

        # Checkpoint stack for automatic rollback
        self._checkpoint_weights: List[float] = list(self._weights)
        self._checkpoint_bias: float = self._bias

        # Training history buffer
        self._training_samples: List[AdaptiveLearningSample] = []
        self._total_training_steps: int = 0
        self._rollbacks_triggered: int = 0

        self._tokenizer = FastTokenizer()

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
    # Feature Extraction (16-D Normalized Vector)
    # --------------------------------------------------------------------------

    def extract_features(self, domain: str) -> List[float]:
        """Extracts 16-dimensional normalized lexical and structural features."""
        clean = domain.lower().strip().rstrip(".")
        parts = clean.split(".")
        apex = parts[-2] if len(parts) >= 2 else clean
        length = len(clean)

        # Shannon entropy
        entropy = self._tokenizer.shannon_entropy(clean)

        # Vowel ratio
        vowel_ratio, v_cnt, c_cnt = self._tokenizer.vowel_consonant_ratio(clean)

        # Consonant run
        max_cons = self._tokenizer.max_consecutive_consonants(clean)

        # Digit density
        digit_count = sum(1 for c in clean if c.isdigit())
        digit_ratio = digit_count / max(1, length)

        # Subdomain depth
        subdomain_depth = max(0, len(parts) - 2)

        # Consecutive digits
        max_digits = self._tokenizer.max_consecutive_digits(clean)

        # Alphanumeric ratio
        alnum_count = sum(1 for c in clean if c.isalnum())
        alnum_ratio = alnum_count / max(1, length)

        features = [
            min(1.0, length / 64.0),
            min(1.0, len(apex) / 32.0),
            min(1.0, entropy / 5.0),
            vowel_ratio,
            min(1.0, max_cons / 10.0),
            digit_ratio,
            min(1.0, subdomain_depth / 5.0),
            min(1.0, max_digits / 8.0),
            alnum_ratio,
            1.0 if "-" in apex else 0.0,
            1.0 if "_" in clean else 0.0,
            min(1.0, len(parts) / 6.0),
            1.0 if (len(apex) > 0 and apex[0].isdigit()) else 0.0,
            1.0 if (len(apex) > 0 and apex[-1].isdigit()) else 0.0,
            1.0 if any(ord(c) > 127 for c in clean) else 0.0,  # Non-ASCII flag
            1.0 if (v_cnt == 0 and length >= 6) else 0.0       # Zero-vowel flag
        ]
        return features

    # --------------------------------------------------------------------------
    # Forward Inference
    # --------------------------------------------------------------------------

    def predict_probability(self, features: List[float]) -> float:
        """Computes sigmoid output probability P(Threat | features)."""
        with self._lock:
            dot = self._bias
            for i in range(min(len(features), len(self._weights))):
                dot += features[i] * self._weights[i]

            # Sigmoid activation with numerical clamping
            dot = max(-20.0, min(20.0, dot))
            prob = 1.0 / (1.0 + math.exp(-dot))
            return round(prob, 4)

    def evaluate_domain(self, domain: str) -> Tuple[bool, float]:
        """Returns (is_threat, probability). Life-safety domains are always (False, 0.0)."""
        clean = domain.lower().strip().rstrip(".")

        if self.is_life_safety_exempt(clean):
            return False, 0.0

        with self._lock:
            if clean in self._whitelist or any(clean.endswith("." + w) for w in self._whitelist):
                return False, 0.0

        features = self.extract_features(clean)
        prob = self.predict_probability(features)
        return prob >= 0.50, prob

    # --------------------------------------------------------------------------
    # Safe Online Learning Step
    # --------------------------------------------------------------------------

    def train_sample(self, domain: str, target_label: int, sample_weight: float = 1.0) -> bool:
        """
        Executes a single guarded online gradient descent update.
        Raises ValueError if attempting to train threat label on Life-Safety domain.
        Raises PermissionError if locked and sample originates from whitelist modification.
        """
        clean = domain.lower().strip().rstrip(".")

        # Life Safety Invariant Check
        if self.is_life_safety_exempt(clean):
            if target_label == 1:
                raise ValueError(
                    f"INVIOLABLE SAFETY VIOLATION: Cannot train life-safety domain '{clean}' as a threat."
                )
            # Benign sample on life safety is a no-op since exemption is already absolute
            return False

        with self._lock:
            # Check Conditional Whitelisting Law if label is benign (whitelist)
            if target_label == 0 and self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "learning whitelist exceptions during active focus lock or timer."
                )

            # 1. Save checkpoint prior to update
            self._save_checkpoint()

            # 2. Extract features
            features = self.extract_features(clean)

            # 3. Compute error gradient
            predicted = self.predict_probability(features)
            error = predicted - float(target_label)  # dL/dz for binary cross-entropy with sigmoid

            # 4. Compute weight deltas with clipping and L2 regularization
            effective_lr = self.learning_rate * sample_weight

            new_weights = list(self._weights)
            for i in range(len(new_weights)):
                grad = (error * features[i]) + (self.l2_lambda * self._weights[i])
                delta_w = -effective_lr * grad
                # Clip delta
                clipped_delta = max(-self.max_delta_clip, min(self.max_delta_clip, delta_w))
                new_weights[i] += clipped_delta

            bias_grad = error
            clipped_bias_delta = max(-self.max_delta_clip, min(self.max_delta_clip, -effective_lr * bias_grad))
            new_bias = self._bias + clipped_bias_delta

            # 5. Apply provisional weights
            self._weights = new_weights
            self._bias = new_bias

            # 6. Model Sanity Watchdog Verification
            if not self._verify_golden_benchmarks():
                # Rollback!
                self._rollback_checkpoint()
                self._rollbacks_triggered += 1
                return False

            # Success: persist sample in training history
            sample = AdaptiveLearningSample(
                domain=clean,
                features=features,
                target_label=target_label,
                weight=sample_weight
            )
            self._training_samples.append(sample)
            if len(self._training_samples) > 1000:
                self._training_samples.pop(0)

            self._total_training_steps += 1
            return True

    # --------------------------------------------------------------------------
    # Benchmark Watchdog & Rollback
    # --------------------------------------------------------------------------

    def _verify_golden_benchmarks(self) -> bool:
        """
        Validates model predictions against the golden benchmark suite.
        Returns False if accuracy on golden benchmarks drops below 85% or any
        critical life-safety/benign benchmark is misclassified as threat.
        """
        correct = 0
        total = len(GOLDEN_BENCHMARK_SUITE)

        for domain, expected in GOLDEN_BENCHMARK_SUITE:
            is_threat, _ = self.evaluate_domain(domain)
            actual = 1 if is_threat else 0
            if actual == expected:
                correct += 1
            else:
                # If a benign golden domain is misclassified as a threat, immediately reject
                if expected == 0:
                    return False

        accuracy = correct / total
        return accuracy >= 0.85

    def _save_checkpoint(self) -> None:
        self._checkpoint_weights = list(self._weights)
        self._checkpoint_bias = self._bias

    def _rollback_checkpoint(self) -> None:
        self._weights = list(self._checkpoint_weights)
        self._bias = self._checkpoint_bias

    # --------------------------------------------------------------------------
    # Telemetry & Diagnostics
    # --------------------------------------------------------------------------

    def get_telemetry(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "total_training_steps": self._total_training_steps,
                "rollbacks_triggered": self._rollbacks_triggered,
                "training_samples_count": len(self._training_samples),
                "is_locked": self.is_locked,
                "learning_rate": self.learning_rate,
                "weights_norm": round(math.sqrt(sum(w * w for w in self._weights)), 4),
                "bias": round(self._bias, 4)
            }
