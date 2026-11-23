import 'package:flutter/foundation.dart';

enum PriorityEventType {
  timerExpired,
  dailyQuotaDepleted,
  dailyQuotaMidnightRollover,
  scheduleWindowStart,
  scheduleWindowEnd,
  cooldownComplete,
}

@immutable
class ScheduleTriggerEvent implements Comparable<ScheduleTriggerEvent> {
  final String eventId;
  final String appId;
  final String packageName;
  final DateTime targetTimestamp;
  final PriorityEventType eventType;

  const ScheduleTriggerEvent({
    required this.eventId,
    required this.appId,
    required this.packageName,
    required this.targetTimestamp,
    required this.eventType,
  });

  @override
  int compareTo(ScheduleTriggerEvent other) {
    return targetTimestamp.compareTo(other.targetTimestamp);
  }

  @override
  String toString() => 'TriggerEvent($appId, $eventType, @$targetTimestamp)';
}

/// Binary Min-Heap Priority Queue ordering triggers by timestamp with sub-second resolution.
class PerAppPriorityQueue {
  final List<ScheduleTriggerEvent> _heap = [];

  int get length => _heap.length;
  bool get isEmpty => _heap.isEmpty;
  bool get isNotEmpty => _heap.isNotEmpty;

  /// Inserts a trigger event into the min-heap.
  void insert(ScheduleTriggerEvent event) {
    _heap.add(event);
    _swimUp(_heap.length - 1);
  }

  /// Peeks at the nearest upcoming trigger without removing it.
  ScheduleTriggerEvent? peek() {
    return _heap.isEmpty ? null : _heap.first;
  }

  /// Removes and returns the nearest trigger event.
  ScheduleTriggerEvent? pop() {
    if (_heap.isEmpty) return null;
    if (_heap.length == 1) return _heap.removeLast();

    final min = _heap.first;
    _heap[0] = _heap.removeLast();
    _sinkDown(0);
    return min;
  }

  /// Pops all events whose targetTimestamp is before or equal to [currentTime].
  List<ScheduleTriggerEvent> popExpired(DateTime currentTime) {
    final expired = <ScheduleTriggerEvent>[];
    while (_heap.isNotEmpty && _heap.first.targetTimestamp.isBefore(currentTime) ||
        (_heap.isNotEmpty && _heap.first.targetTimestamp.isAtSameMomentAs(currentTime))) {
      final item = pop();
      if (item != null) expired.add(item);
    }
    return expired;
  }

  /// Removes all trigger events associated with a specific appId.
  void removeByAppId(String appId) {
    _heap.removeWhere((e) => e.appId == appId);
    _rebuildHeap();
  }

  /// Removes all events with a specific eventId.
  void removeByEventId(String eventId) {
    _heap.removeWhere((e) => e.eventId == eventId);
    _rebuildHeap();
  }

  /// Empties the queue.
  void clear() {
    _heap.clear();
  }

  void _swimUp(int index) {
    int current = index;
    while (current > 0) {
      final parent = (current - 1) ~/ 2;
      if (_heap[current].compareTo(_heap[parent]) < 0) {
        _swap(current, parent);
        current = parent;
      } else {
        break;
      }
    }
  }

  void _sinkDown(int index) {
    int current = index;
    final length = _heap.length;

    while (true) {
      int smallest = current;
      final leftChild = 2 * current + 1;
      final rightChild = 2 * current + 2;

      if (leftChild < length && _heap[leftChild].compareTo(_heap[smallest]) < 0) {
        smallest = leftChild;
      }
      if (rightChild < length && _heap[rightChild].compareTo(_heap[smallest]) < 0) {
        smallest = rightChild;
      }

      if (smallest != current) {
        _swap(current, smallest);
        current = smallest;
      } else {
        break;
      }
    }
  }

  void _rebuildHeap() {
    for (int i = (_heap.length ~/ 2) - 1; i >= 0; i--) {
      _sinkDown(i);
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
}
