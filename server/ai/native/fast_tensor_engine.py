"""
FocusDNS AI Engine - Fast Tensor Inference Engine & Native C++ SIMD Bindings
Provides sub-microsecond tensor dot-products, matrix-vector linear algebra,
and neural network forward passes. Transparently switches between native
C++ SIMD shared libraries and high-speed vectorized Python fallbacks.
"""

import ctypes
import math
import os
import platform
import sys
from typing import List, Tuple, Optional, Dict, Any


class FastTensorEngine:
    """
    Unified linear algebra runtime supporting SIMD vectorization.
    Loads libfast_tensor.so / fast_tensor.dll when present, or provides
    zero-dependency high-throughput mathematical evaluation.
    """

    _native_lib: Optional[ctypes.CDLL] = None
    _backend_name: str = "Pure Python Vectorized Engine"

    def __init__(self, lib_path: Optional[str] = None):
        self._init_native_bindings(lib_path)

    @classmethod
    def _init_native_bindings(cls, custom_path: Optional[str] = None):
        """Attempts to dynamically link native C++ shared library."""
        if cls._native_lib is not None:
            return

        candidate_paths = []
        if custom_path:
            candidate_paths.append(custom_path)

        curr_dir = os.path.dirname(os.path.abspath(__file__))
        if platform.system() == "Windows":
            candidate_paths.extend([
                os.path.join(curr_dir, "fast_tensor.dll"),
                os.path.join(curr_dir, "libfast_tensor.dll"),
            ])
        elif platform.system() == "Darwin":
            candidate_paths.extend([
                os.path.join(curr_dir, "libfast_tensor.dylib"),
            ])
        else:
            candidate_paths.extend([
                os.path.join(curr_dir, "libfast_tensor.so"),
                "/usr/local/lib/libfast_tensor.so",
                "/usr/lib/libfast_tensor.so",
            ])

        for path in candidate_paths:
            if os.path.exists(path):
                try:
                    lib = ctypes.CDLL(path)
                    # Configure signatures
                    lib.fast_tensor_get_simd_type.restype = ctypes.c_char_p

                    lib.fast_tensor_dot.argtypes = [
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.c_size_t,
                        ctypes.POINTER(ctypes.c_float),
                    ]
                    lib.fast_tensor_dot.restype = ctypes.c_int

                    lib.fast_tensor_mlp_forward.argtypes = [
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.POINTER(ctypes.c_float),
                        ctypes.c_float,
                        ctypes.POINTER(ctypes.c_float),
                    ]
                    lib.fast_tensor_mlp_forward.restype = ctypes.c_int

                    cls._native_lib = lib
                    simd_type = lib.fast_tensor_get_simd_type().decode("utf-8")
                    cls._backend_name = f"C++ Native SIMD ({simd_type})"
                    break
                except Exception:
                    continue

    def get_runtime_backend(self) -> str:
        """Returns the active computation backend name."""
        return self._backend_name

    def is_native_simd_active(self) -> bool:
        """Returns True if compiled C++ SIMD library is driving inference."""
        return self._native_lib is not None

    def dot_product(self, a: List[float], b: List[float]) -> float:
        """Computes vector dot product sum(a[i] * b[i])."""
        n = min(len(a), len(b))
        if n == 0:
            return 0.0

        if self._native_lib:
            arr_a = (ctypes.c_float * n)(*a[:n])
            arr_b = (ctypes.c_float * n)(*b[:n])
            res = ctypes.c_float(0.0)
            code = self._native_lib.fast_tensor_dot(arr_a, arr_b, n, ctypes.byref(res))
            if code == 0:
                return float(res.value)

        # Vectorized Python fallback (unrolled 4x for speed)
        s0, s1, s2, s3 = 0.0, 0.0, 0.0, 0.0
        i = 0
        limit = n - (n % 4)
        while i < limit:
            s0 += a[i] * b[i]
            s1 += a[i+1] * b[i+1]
            s2 += a[i+2] * b[i+2]
            s3 += a[i+3] * b[i+3]
            i += 4
        total = s0 + s1 + s2 + s3
        while i < n:
            total += a[i] * b[i]
            i += 1
        return total

    def dense_relu(
        self,
        x: List[float],
        w: List[List[float]],
        b: List[float]
    ) -> List[float]:
        """
        Matrix-vector layer with ReLU activation: Y = max(0, W * X + B)
        """
        out_features = len(b)
        y = [0.0] * out_features
        for j in range(out_features):
            row = w[j]
            dot = self.dot_product(x, row)
            val = dot + b[j]
            y[j] = val if val > 0.0 else 0.0
        return y

    def dense_sigmoid(
        self,
        x: List[float],
        w: List[List[float]],
        b: List[float]
    ) -> List[float]:
        """
        Matrix-vector layer with Sigmoid activation: Y = 1 / (1 + exp(-(W * X + B)))
        """
        out_features = len(b)
        y = [0.0] * out_features
        for j in range(out_features):
            row = w[j]
            dot = self.dot_product(x, row)
            val = dot + b[j]
            if val >= 16.0:
                y[j] = 1.0
            elif val <= -16.0:
                y[j] = 0.0
            else:
                y[j] = 1.0 / (1.0 + math.exp(-val))
        return y

    def mlp_forward(
        self,
        features: List[float],
        w1: List[List[float]],
        b1: List[float],
        w2: List[List[float]],
        b2: List[float],
        w3: List[float],
        b3: float
    ) -> float:
        """
        Executes end-to-end 3-layer MLP forward-pass:
        features(16) -> h1(32) [ReLU] -> h2(16) [ReLU] -> out(1) [Sigmoid]
        """
        if self._native_lib and len(features) == 16 and len(b1) == 32 and len(b2) == 16 and len(w3) == 16:
            try:
                # Flatten weights
                flat_w1 = [item for row in w1 for item in row]
                flat_w2 = [item for row in w2 for item in row]

                c_feat = (ctypes.c_float * 16)(*features)
                c_w1 = (ctypes.c_float * 512)(*flat_w1)
                c_b1 = (ctypes.c_float * 32)(*b1)
                c_w2 = (ctypes.c_float * 512)(*flat_w2)
                c_b2 = (ctypes.c_float * 16)(*b2)
                c_w3 = (ctypes.c_float * 16)(*w3)
                c_prob = ctypes.c_float(0.0)

                status = self._native_lib.fast_tensor_mlp_forward(
                    c_feat, c_w1, c_b1, c_w2, c_b2, c_w3, ctypes.c_float(b3), ctypes.byref(c_prob)
                )
                if status == 0:
                    return float(c_prob.value)
            except Exception:
                pass

        # High-speed Python computation
        h1 = self.dense_relu(features, w1, b1)
        h2 = self.dense_relu(h1, w2, b2)

        out_dot = self.dot_product(h2, w3)
        out_val = out_dot + b3
        if out_val >= 16.0:
            return 1.0
        elif out_val <= -16.0:
            return 0.0
        return 1.0 / (1.0 + math.exp(-out_val))

    def batch_forward(
        self,
        batch_inputs: List[List[float]],
        w1: List[List[float]],
        b1: List[float],
        w2: List[List[float]],
        b2: List[float],
        w3: List[float],
        b3: float
    ) -> List[float]:
        """Executes forward-pass over a batch of input feature vectors."""
        return [self.mlp_forward(x, w1, b1, w2, b2, w3, b3) for x in batch_inputs]

    def shannon_entropy(self, text: str) -> float:
        """Calculates Shannon entropy in bits per character."""
        if not text:
            return 0.0
        counts: Dict[str, int] = {}
        for c in text:
            counts[c] = counts.get(c, 0) + 1
        length = float(len(text))
        entropy = 0.0
        for count in counts.values():
            p = count / length
            entropy -= p * math.log2(p)
        return round(entropy, 4)
