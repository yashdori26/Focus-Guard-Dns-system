/**
 * FocusDNS AI Engine - C++ SIMD Fast Tensor Inference Runtime Implementation
 * High-performance vectorized linear algebra, activation functions, and
 * 3-layer neural network inference for real-time edge security.
 */

#include "fast_tensor_runtime.h"

#include <cmath>
#include <cstring>
#include <algorithm>

// Architecture-specific SIMD includes
#if defined(__AVX2__)
    #include <immintrin.h>
    #define SIMD_NAME "AVX2+FMA"
#elif defined(__SSE4_1__) || defined(__SSE2__)
    #include <xmmintrin.h>
    #include <emmintrin.h>
    #define SIMD_NAME "SSE4.1/SSE2"
#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
    #include <arm_neon.h>
    #define SIMD_NAME "ARM NEON"
#else
    #define SIMD_NAME "Portable Auto-Vectorized"
#endif

extern "C" {

const char* fast_tensor_get_simd_type(void) {
    return SIMD_NAME;
}

int fast_tensor_dot(
    const float* a,
    const float* b,
    size_t n,
    float* out_result
) {
    if (!a || !b || !out_result) return TENSOR_ERR_NULL_PTR;
    if (n == 0) {
        *out_result = 0.0f;
        return TENSOR_SUCCESS;
    }

    float sum = 0.0f;
    size_t i = 0;

#if defined(__AVX2__)
    __m256 vsum = _mm256_setzero_ps();
    for (; i + 8 <= n; i += 8) {
        __m256 va = _mm256_loadu_ps(a + i);
        __m256 vb = _mm256_loadu_ps(b + i);
        vsum = _mm256_fmadd_ps(va, vb, vsum);
    }
    // Horizontal add of 8 floats in vsum
    float temp[8];
    _mm256_storeu_ps(temp, vsum);
    sum = temp[0] + temp[1] + temp[2] + temp[3] + temp[4] + temp[5] + temp[6] + temp[7];

#elif defined(__ARM_NEON) || defined(__ARM_NEON__)
    float32x4_t vsum = vdupq_n_f32(0.0f);
    for (; i + 4 <= n; i += 4) {
        float32x4_t va = vld1q_f32(a + i);
        float32x4_t vb = vld1q_f32(b + i);
        vsum = vmlaq_f32(vsum, va, vb);
    }
    float temp[4];
    vst1q_f32(temp, vsum);
    sum = temp[0] + temp[1] + temp[2] + temp[3];

#else
    // Loop unrolled by 4 for portable auto-vectorization
    float s0 = 0.0f, s1 = 0.0f, s2 = 0.0f, s3 = 0.0f;
    for (; i + 4 <= n; i += 4) {
        s0 += a[i] * b[i];
        s1 += a[i+1] * b[i+1];
        s2 += a[i+2] * b[i+2];
        s3 += a[i+3] * b[i+3];
    }
    sum = s0 + s1 + s2 + s3;
#endif

    // Accumulate tail elements
    for (; i < n; ++i) {
        sum += a[i] * b[i];
    }

    *out_result = sum;
    return TENSOR_SUCCESS;
}

int fast_tensor_dense_relu(
    const float* x,
    const float* w,
    const float* b,
    size_t in_features,
    size_t out_features,
    float* y
) {
    if (!x || !w || !b || !y) return TENSOR_ERR_NULL_PTR;
    if (in_features == 0 || out_features == 0) return TENSOR_ERR_INVALID_SIZE;

    for (size_t j = 0; j < out_features; ++j) {
        const float* row = w + (j * in_features);
        float dot_prod = 0.0f;
        fast_tensor_dot(x, row, in_features, &dot_prod);
        float val = dot_prod + b[j];
        y[j] = (val > 0.0f) ? val : 0.0f; // ReLU activation
    }
    return TENSOR_SUCCESS;
}

int fast_tensor_dense_sigmoid(
    const float* x,
    const float* w,
    const float* b,
    size_t in_features,
    size_t out_features,
    float* y
) {
    if (!x || !w || !b || !y) return TENSOR_ERR_NULL_PTR;
    if (in_features == 0 || out_features == 0) return TENSOR_ERR_INVALID_SIZE;

    for (size_t j = 0; j < out_features; ++j) {
        const float* row = w + (j * in_features);
        float dot_prod = 0.0f;
        fast_tensor_dot(x, row, in_features, &dot_prod);
        float val = dot_prod + b[j];
        // Stable sigmoid: 1 / (1 + exp(-val))
        if (val >= 16.0f) {
            y[j] = 1.0f;
        } else if (val <= -16.0f) {
            y[j] = 0.0f;
        } else {
            y[j] = 1.0f / (1.0f + std::exp(-val));
        }
    }
    return TENSOR_SUCCESS;
}

int fast_tensor_mlp_forward(
    const float* input_features,
    const float* w1,
    const float* b1,
    const float* w2,
    const float* b2,
    const float* w3,
    const float b3,
    float* out_probability
) {
    if (!input_features || !w1 || !b1 || !w2 || !b2 || !w3 || !out_probability) {
        return TENSOR_ERR_NULL_PTR;
    }

    // Stack-allocated scratchpads (Zero heap allocation, 100% L1 cache resident)
    float h1[32]; // 32 floats = 128 bytes
    float h2[16]; // 16 floats = 64 bytes

    // Layer 1: Input (16) -> Hidden 1 (32) + ReLU
    fast_tensor_dense_relu(input_features, w1, b1, 16, 32, h1);

    // Layer 2: Hidden 1 (32) -> Hidden 2 (16) + ReLU
    fast_tensor_dense_relu(h1, w2, b2, 32, 16, h2);

    // Layer 3: Hidden 2 (16) -> Output (1) + Sigmoid
    float dot3 = 0.0f;
    fast_tensor_dot(h2, w3, 16, &dot3);
    float out_val = dot3 + b3;

    float prob = 0.0f;
    if (out_val >= 16.0f) {
        prob = 1.0f;
    } else if (out_val <= -16.0f) {
        prob = 0.0f;
    } else {
        prob = 1.0f / (1.0f + std::exp(-out_val));
    }

    *out_probability = prob;
    return TENSOR_SUCCESS;
}

int fast_tensor_mlp_forward_batch(
    const float* batch_inputs,
    size_t batch_size,
    const float* w1,
    const float* b1,
    const float* w2,
    const float* b2,
    const float* w3,
    const float b3,
    float* out_probabilities
) {
    if (!batch_inputs || !out_probabilities) return TENSOR_ERR_NULL_PTR;

    for (size_t b = 0; b < batch_size; ++b) {
        const float* sample = batch_inputs + (b * 16);
        fast_tensor_mlp_forward(sample, w1, b1, w2, b2, w3, b3, &out_probabilities[b]);
    }
    return TENSOR_SUCCESS;
}

float fast_tensor_shannon_entropy(
    const uint32_t* char_counts,
    size_t total_length
) {
    if (!char_counts || total_length == 0) return 0.0f;

    const float inv_len = 1.0f / static_cast<float>(total_length);
    float entropy = 0.0f;

    for (size_t i = 0; i < 256; ++i) {
        uint32_t count = char_counts[i];
        if (count > 0) {
            float p = static_cast<float>(count) * inv_len;
            entropy -= p * std::log2(p);
        }
    }

    return entropy;
}

} // extern "C"
