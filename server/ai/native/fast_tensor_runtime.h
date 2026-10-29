/**
 * FocusDNS AI Engine - C++ SIMD Fast Tensor Inference Runtime
 * Header definitions for sub-10 microsecond vectorized dot-products,
 * matrix multiplications, and neural network forward-pass inference.
 */

#ifndef FAST_TENSOR_RUNTIME_H
#define FAST_TENSOR_RUNTIME_H

#include <cstdint>
#include <cstddef>

#ifdef __cplusplus
extern "C" {
#endif

// API Export macro
#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef BUILDING_FAST_TENSOR_DLL
        #define TENSOR_API __declspec(dllexport)
    #else
        #define TENSOR_API __declspec(dllimport)
    #endif
#else
    #define TENSOR_API __attribute__((visibility("default")))
#endif

// Return error codes
#define TENSOR_SUCCESS 0
#define TENSOR_ERR_NULL_PTR -1
#define TENSOR_ERR_DIM_MISMATCH -2
#define TENSOR_ERR_INVALID_SIZE -3

/**
 * Computes single-precision dot product of two vectors of size n using SIMD.
 * Supports AVX2 / SSE / ARM NEON auto-vectorization.
 */
TENSOR_API int fast_tensor_dot(
    const float* a,
    const float* b,
    size_t n,
    float* out_result
);

/**
 * Computes Dense Matrix-Vector Multiplication: Y = ReLU(W * X + B)
 * X: Vector of size in_features
 * W: Matrix of shape [out_features, in_features] (row-major)
 * B: Bias vector of size out_features
 * Y: Output vector of size out_features
 */
TENSOR_API int fast_tensor_dense_relu(
    const float* x,
    const float* w,
    const float* b,
    size_t in_features,
    size_t out_features,
    float* y
);

/**
 * Computes Dense Matrix-Vector Multiplication: Y = Sigmoid(W * X + B)
 */
TENSOR_API int fast_tensor_dense_sigmoid(
    const float* x,
    const float* w,
    const float* b,
    size_t in_features,
    size_t out_features,
    float* y
);

/**
 * End-to-end forward pass for 3-layer MLP:
 * Layer 1: Dense ReLU (in: 16 -> out: 32)
 * Layer 2: Dense ReLU (in: 32 -> out: 16)
 * Layer 3: Dense Sigmoid (in: 16 -> out: 1)
 */
TENSOR_API int fast_tensor_mlp_forward(
    const float* input_features,  // Size: 16
    const float* w1,              // Size: 32 * 16 = 512
    const float* b1,              // Size: 32
    const float* w2,              // Size: 16 * 32 = 512
    const float* b2,              // Size: 16
    const float* w3,              // Size: 1 * 16 = 16
    const float b3,               // Scalar
    float* out_probability        // Pointer to output float
);

/**
 * Batch forward pass for multiple domains concurrently.
 */
TENSOR_API int fast_tensor_mlp_forward_batch(
    const float* batch_inputs,    // Size: batch_size * 16
    size_t batch_size,
    const float* w1,
    const float* b1,
    const float* w2,
    const float* b2,
    const float* w3,
    const float b3,
    float* out_probabilities      // Size: batch_size
);

/**
 * Computes Shannon entropy over character histogram (size 256).
 */
TENSOR_API float fast_tensor_shannon_entropy(
    const uint32_t* char_counts,
    size_t total_length
);

/**
 * Returns SIMD instruction set name compiled into this build.
 */
TENSOR_API const char* fast_tensor_get_simd_type(void);

#ifdef __cplusplus
}
#endif

#endif // FAST_TENSOR_RUNTIME_H
