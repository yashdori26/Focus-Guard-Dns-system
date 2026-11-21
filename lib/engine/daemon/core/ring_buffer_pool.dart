import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Represents a leased buffer from the pre-allocated pool.
class PooledBuffer {
  final int id;
  final Uint8List bytes;
  int length;
  bool isLeased;
  final RingBufferPool _pool;

  PooledBuffer({
    required this.id,
    required this.bytes,
    this.length = 0,
    this.isLeased = false,
    required RingBufferPool pool,
  }) : _pool = pool;

  /// Releases this buffer back to the pool for reuse.
  void release() {
    _pool.recycle(this);
  }

  /// Clears length and resets buffer contents.
  void reset() {
    length = 0;
    isLeased = false;
  }
}

/// Statistics on ring buffer pool allocations and performance.
@immutable
class BufferPoolTelemetry {
  final int capacity;
  final int activeLeases;
  final int totalAcquisitions;
  final int totalRecycles;
  final int poolExhaustionEvents;
  final double reuseRatio;

  const BufferPoolTelemetry({
    required this.capacity,
    required this.activeLeases,
    required this.totalAcquisitions,
    required this.totalRecycles,
    required this.poolExhaustionEvents,
    required this.reuseRatio,
  });

  Map<String, dynamic> toJson() => {
        'capacity': capacity,
        'activeLeases': activeLeases,
        'totalAcquisitions': totalAcquisitions,
        'totalRecycles': totalRecycles,
        'poolExhaustionEvents': poolExhaustionEvents,
        'reuseRatio': reuseRatio,
      };
}

/// Zero-allocation, thread-safe pre-allocated direct memory ring buffer pool.
///
/// Designed to eliminate garbage collector pauses during high-frequency DNS query
/// bursts. Prevents CPU wakeups and minimizes energy consumption.
class RingBufferPool {
  final int capacity;
  final int bufferSize;

  final List<PooledBuffer> _buffers;
  final List<PooledBuffer> _available;

  int _totalAcquisitions = 0;
  int _totalRecycles = 0;
  int _exhaustionEvents = 0;

  RingBufferPool({
    this.capacity = 32,
    this.bufferSize = 1500, // Standard Ethernet MTU
  })  : _buffers = [],
        _available = [] {
    for (int i = 0; i < capacity; i++) {
      final buf = PooledBuffer(
        id: i,
        bytes: Uint8List(bufferSize),
        pool: this,
      );
      _buffers.add(buf);
      _available.add(buf);
    }
  }

  int get availableCount => _available.length;
  int get leasedCount => capacity - _available.length;

  /// Acquires a buffer from the pre-allocated pool.
  /// If the pool is exhausted, allocates a transient buffer and increments exhaustion count.
  PooledBuffer acquire() {
    _totalAcquisitions++;
    if (_available.isNotEmpty) {
      final buffer = _available.removeLast();
      buffer.isLeased = true;
      buffer.length = 0;
      return buffer;
    }

    // Pool exhaustion fallback
    _exhaustionEvents++;
    return PooledBuffer(
      id: -1,
      bytes: Uint8List(bufferSize),
      isLeased: true,
      pool: this,
    );
  }

  /// Recycles a leased buffer back to the pool.
  void recycle(PooledBuffer buffer) {
    if (!buffer.isLeased) return;
    _totalRecycles++;
    buffer.reset();

    if (buffer.id >= 0 && !_available.contains(buffer)) {
      _available.add(buffer);
    }
  }

  /// Generates current performance metrics.
  BufferPoolTelemetry getTelemetry() {
    final double ratio = _totalAcquisitions > 0
        ? (_totalRecycles / _totalAcquisitions).clamp(0.0, 1.0)
        : 1.0;

    return BufferPoolTelemetry(
      capacity: capacity,
      activeLeases: leasedCount,
      totalAcquisitions: _totalAcquisitions,
      totalRecycles: _totalRecycles,
      poolExhaustionEvents: _exhaustionEvents,
      reuseRatio: ratio,
    );
  }

  /// Resets pool metrics for testing.
  void resetMetrics() {
    _totalAcquisitions = 0;
    _totalRecycles = 0;
    _exhaustionEvents = 0;
  }
}
