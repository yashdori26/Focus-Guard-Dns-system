# FocusDNS AI Engine - SIMD Fast Tensor Engine Makefile
CC = g++
CFLAGS = -O3 -fPIC -shared -Wall -Wextra -std=c++17

# Detect AVX2 or fallback to portable SSE/NEON
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
    SIMD_FLAGS = -mavx2 -mfma
else
    SIMD_FLAGS =
endif

TARGET = libfast_tensor.so

all: $(TARGET)

$(TARGET): fast_tensor_runtime.cpp fast_tensor_runtime.h
	$(CC) $(CFLAGS) $(SIMD_FLAGS) -o $(TARGET) fast_tensor_runtime.cpp

clean:
	rm -f $(TARGET)
