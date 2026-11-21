import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/core/ring_buffer_pool.dart';

void main() {
  group('RingBufferPool & PooledBuffer Tests', () {
    test('Initializes with exact pre-allocated capacity', () {
      final pool = RingBufferPool(capacity: 8, bufferSize: 512);

      expect(pool.capacity, equals(8));
      expect(pool.availableCount, equals(8));
      expect(pool.leasedCount, equals(0));

      final telemetry = pool.getTelemetry();
      expect(telemetry.capacity, equals(8));
      expect(telemetry.activeLeases, equals(0));
      expect(telemetry.poolExhaustionEvents, equals(0));
    });

    test('Acquires and recycles pooled buffers with correct state tracking', () {
      final pool = RingBufferPool(capacity: 4);

      final buf1 = pool.acquire();
      expect(buf1.isLeased, isTrue);
      expect(pool.availableCount, equals(3));
      expect(pool.leasedCount, equals(1));

      final buf2 = pool.acquire();
      expect(pool.availableCount, equals(2));
      expect(pool.leasedCount, equals(2));

      // Recycle buf1
      buf1.release();
      expect(buf1.isLeased, isFalse);
      expect(pool.availableCount, equals(3));
      expect(pool.leasedCount, equals(1));

      // Recycle buf2
      buf2.release();
      expect(pool.availableCount, equals(4));
      expect(pool.leasedCount, equals(0));

      final telemetry = pool.getTelemetry();
      expect(telemetry.totalAcquisitions, equals(2));
      expect(telemetry.totalRecycles, equals(2));
      expect(telemetry.reuseRatio, equals(1.0));
    });

    test('Handles pool exhaustion gracefully by allocating transient fallback buffer', () {
      final pool = RingBufferPool(capacity: 2);

      final buf1 = pool.acquire();
      final buf2 = pool.acquire();
      expect(pool.availableCount, equals(0));

      // Third acquisition causes exhaustion event
      final overflowBuf = pool.acquire();
      expect(overflowBuf.id, equals(-1));
      expect(pool.getTelemetry().poolExhaustionEvents, equals(1));

      // Releasing transient buffer does not overflow pool
      overflowBuf.release();
      expect(pool.availableCount, equals(0));

      buf1.release();
      expect(pool.availableCount, equals(1));
      buf2.release();
      expect(pool.availableCount, equals(2));
    });

    test('Double recycling a buffer is idempotent and does not corrupt pool list', () {
      final pool = RingBufferPool(capacity: 2);

      final buf = pool.acquire();
      buf.release();
      expect(pool.availableCount, equals(2));

      // Second release call should be ignored
      buf.release();
      expect(pool.availableCount, equals(2));
    });

    test('Buffer reset clears length and resets content state', () {
      final pool = RingBufferPool(capacity: 2);
      final buf = pool.acquire();
      buf.length = 120;
      expect(buf.length, equals(120));

      buf.reset();
      expect(buf.length, equals(0));
      expect(buf.isLeased, isFalse);
    });

    test('BufferPoolTelemetry JSON serialization round-trip', () {
      const telemetry = BufferPoolTelemetry(
        capacity: 16,
        activeLeases: 4,
        totalAcquisitions: 100,
        totalRecycles: 96,
        poolExhaustionEvents: 0,
        reuseRatio: 0.96,
      );

      final json = telemetry.toJson();
      expect(json['capacity'], equals(16));
      expect(json['activeLeases'], equals(4));
      expect(json['reuseRatio'], equals(0.96));
    });
  });
}
