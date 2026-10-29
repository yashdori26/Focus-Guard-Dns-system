"""
Unit Tests for FastTensorEngine
Verifies SIMD dot-product, dense ReLU, dense Sigmoid, 3-layer MLP forward pass,
and Shannon entropy calculations.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.native.fast_tensor_engine import FastTensorEngine


class TestFastTensorEngine(unittest.TestCase):
    """Verifies vector operations and neural network forward pass in FastTensorEngine."""

    def setUp(self):
        self.engine = FastTensorEngine()

    def test_dot_product(self):
        a = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
        b = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        res = self.engine.dot_product(a, b)
        expected = sum(x * y for x, y in zip(a, b))
        self.assertAlmostEqual(res, expected, places=4)

    def test_dense_relu(self):
        x = [1.0, -1.0, 2.0]
        w = [
            [1.0, 1.0, 1.0],   # dot = 1 - 1 + 2 = 2
            [-2.0, 1.0, 0.0],  # dot = -2 - 1 + 0 = -3
        ]
        b = [0.5, 1.0]
        y = self.engine.dense_relu(x, w, b)
        self.assertEqual(len(y), 2)
        self.assertAlmostEqual(y[0], 2.5)  # 2 + 0.5 = 2.5
        self.assertEqual(y[1], 0.0)        # -3 + 1 = -2 -> ReLU(0.0)

    def test_dense_sigmoid(self):
        x = [1.0, 2.0]
        w = [[0.0, 0.0]]
        b = [0.0]  # Sigmoid(0) = 0.5
        y = self.engine.dense_sigmoid(x, w, b)
        self.assertAlmostEqual(y[0], 0.5, places=4)

    def test_mlp_forward_and_batch(self):
        # 16 inputs -> 32 h1 -> 16 h2 -> 1 out
        features = [0.1] * 16
        w1 = [[0.05] * 16 for _ in range(32)]
        b1 = [0.0] * 32
        w2 = [[0.02] * 32 for _ in range(16)]
        b2 = [0.0] * 16
        w3 = [0.05] * 16
        b3 = 0.0

        prob = self.engine.mlp_forward(features, w1, b1, w2, b2, w3, b3)
        self.assertGreaterEqual(prob, 0.0)
        self.assertLessEqual(prob, 1.0)

        # Batch forward
        batch = [features, [0.5] * 16, [0.9] * 16]
        probs = self.engine.batch_forward(batch, w1, b1, w2, b2, w3, b3)
        self.assertEqual(len(probs), 3)

    def test_shannon_entropy(self):
        self.assertEqual(self.engine.shannon_entropy(""), 0.0)
        self.assertEqual(self.engine.shannon_entropy("aaaa"), 0.0)
        self.assertAlmostEqual(self.engine.shannon_entropy("abcd"), 2.0, places=3)

    def test_backend_name(self):
        backend = self.engine.get_runtime_backend()
        self.assertTrue(len(backend) > 0)


if __name__ == "__main__":
    unittest.main()
