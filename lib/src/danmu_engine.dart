import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Playback priority. High-priority entries are ordered before normal ones
/// whenever they are waiting to be activated.
enum DanmuPriority { normal, high }

/// Internal lifecycle of the scheduling engine.
enum DanmuPhase { unconfigured, ready, playing, paused }

/// Outcome of an enqueue request.
enum DanmuEnqueueResult {
  /// Placed on a lane immediately.
  accepted,

  /// Accepted by the engine and waiting for layout or an available lane.
  queued,

  /// Dropped because the entry is invalid or the waiting queue is full.
  rejected,
}

@immutable
class DanmuConfig {
  const DanmuConfig({
    this.laneHeight = 36,
    this.laneSpacing = 10,
    this.laneCount = 4,
    this.gap = 32,
    this.speed = 86,
    this.maxQueueSize = 80,
    this.autoStart = true,
  });

  final double laneHeight;
  final double laneSpacing;
  final int laneCount;
  final double gap;
  final double speed;

  /// Maximum number of entries waiting to be activated.
  ///
  /// This is an admission limit. Lowering it at runtime does not discard
  /// entries that were already accepted; new sends are rejected until the
  /// waiting count falls below the new limit.
  final int maxQueueSize;

  final bool autoStart;

  double get laneExtent => laneHeight + laneSpacing;

  @override
  bool operator ==(Object other) =>
      other is DanmuConfig &&
      other.laneHeight == laneHeight &&
      other.laneSpacing == laneSpacing &&
      other.laneCount == laneCount &&
      other.gap == gap &&
      other.speed == speed &&
      other.maxQueueSize == maxQueueSize &&
      other.autoStart == autoStart;

  @override
  int get hashCode => Object.hash(
        laneHeight,
        laneSpacing,
        laneCount,
        gap,
        speed,
        maxQueueSize,
        autoStart,
      );

  @override
  String toString() =>
      'DanmuConfig(laneHeight: $laneHeight, laneSpacing: $laneSpacing, '
      'laneCount: $laneCount, gap: $gap, speed: $speed, '
      'maxQueueSize: $maxQueueSize, autoStart: $autoStart)';
}

@immutable
class DanmuEntry {
  const DanmuEntry({
    required this.id,
    required this.child,
    required this.width,
    this.speed,
    this.priority = DanmuPriority.normal,
    this.laneHint,
  }) : assert(width > 0 && width != double.infinity);

  final String id;
  final Widget child;
  final double width;
  final double? speed;
  final DanmuPriority priority;
  final int? laneHint;
}

@immutable
class ActiveDanmu {
  const ActiveDanmu({
    required this.entry,
    required this.lane,
    required this.left,
    required this.renderId,
  });

  final DanmuEntry entry;
  final int lane;
  final double left;
  final int renderId;
}

/// Internal scheduling state: lanes, queueing, and per-frame motion.
class DanmuEngine extends ChangeNotifier {
  DanmuEngine(DanmuConfig config) : _config = _validatedConfig(config);

  DanmuConfig _config;
  final List<_DanmuItem> _active = [];
  final Queue<DanmuEntry> _queue = Queue<DanmuEntry>();
  DanmuPhase _phase = DanmuPhase.unconfigured;
  Size _size = Size.zero;
  int _laneCount = 0;
  int _nextRenderId = 0;

  DanmuConfig get config => _config;
  int get laneCount => _laneCount;
  int get waitingCount => _queue.length;

  bool get needsFrame =>
      _phase == DanmuPhase.playing &&
      _active.isNotEmpty &&
      _size != Size.zero &&
      _laneCount > 0;

  UnmodifiableListView<ActiveDanmu> get activeItems => UnmodifiableListView(
        _active
            .map((item) => ActiveDanmu(
                  entry: item.entry,
                  lane: item.lane,
                  left: item.left,
                  renderId: item.renderId,
                ))
            .toList(growable: false),
      );

  /// Publishes viewport geometry. Never notifies because the widget calls this
  /// from build and already rebuilds in the same frame.
  void configure(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      _size = Size.zero;
      _laneCount = 0;
      return;
    }

    final nextLaneCount = _laneCountFor(size);
    if (_size == size && _laneCount == nextLaneCount) return;

    _size = size;
    _setLaneCount(nextLaneCount);
    if (_phase == DanmuPhase.unconfigured) {
      _phase = _config.autoStart ? DanmuPhase.playing : DanmuPhase.ready;
    }
    _drainQueue();
  }

  /// Applies runtime configuration without retroactively discarding entries
  /// that the engine already accepted into the waiting queue.
  void updateConfig(DanmuConfig value) {
    final validated = _validatedConfig(value);
    if (validated == _config) return;

    _config = validated;
    if (_size != Size.zero) {
      _setLaneCount(_laneCountFor(_size));
      _drainQueue();
    }
    notifyListeners();
  }

  int _laneCountFor(Size size) {
    final theoreticalCount = size.height / _config.laneExtent;
    if (!theoreticalCount.isFinite || theoreticalCount >= _config.laneCount) {
      return _config.laneCount;
    }
    if (theoreticalCount <= 0) return 0;
    return theoreticalCount.floor();
  }

  void _setLaneCount(int nextLaneCount) {
    if (nextLaneCount == _laneCount) return;
    _laneCount = nextLaneCount;
    _active.removeWhere((item) => item.lane >= _laneCount);
  }

  DanmuEnqueueResult enqueue(DanmuEntry entry) {
    final entrySpeed = entry.speed;
    final invalidSpeed =
        entrySpeed != null && (!entrySpeed.isFinite || entrySpeed <= 0);
    if (!entry.width.isFinite || entry.width <= 0 || invalidSpeed) {
      return DanmuEnqueueResult.rejected;
    }

    if (_size == Size.zero) {
      if (_queue.length >= _config.maxQueueSize) {
        return DanmuEnqueueResult.rejected;
      }
      _enqueueQueued(entry);
      return DanmuEnqueueResult.queued;
    }

    return _enqueueReady(entry);
  }

  DanmuEnqueueResult _enqueueReady(DanmuEntry entry) {
    final lane = _findAvailableLane(entry);
    if (lane != null) {
      _activate(entry, lane);
      notifyListeners();
      return DanmuEnqueueResult.accepted;
    }

    if (_queue.length >= _config.maxQueueSize) {
      return DanmuEnqueueResult.rejected;
    }

    _enqueueQueued(entry);
    notifyListeners();
    return DanmuEnqueueResult.queued;
  }

  void _enqueueQueued(DanmuEntry entry) {
    if (entry.priority == DanmuPriority.normal) {
      _queue.add(entry);
      return;
    }

    final entries = _queue.toList();
    var insertAt = 0;
    while (insertAt < entries.length &&
        entries[insertAt].priority == DanmuPriority.high) {
      insertAt++;
    }
    entries.insert(insertAt, entry);
    _queue
      ..clear()
      ..addAll(entries);
  }

  void play() {
    if (_phase == DanmuPhase.ready || _phase == DanmuPhase.paused) {
      _phase = DanmuPhase.playing;
      notifyListeners();
    }
  }

  void pause() {
    if (_phase == DanmuPhase.playing) {
      _phase = DanmuPhase.paused;
      notifyListeners();
    }
  }

  void clear() {
    _active.clear();
    _queue.clear();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (_phase != DanmuPhase.playing) return;

    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return;

    for (final item in _active) {
      item.left -= item.speed * seconds;
    }
    _active.removeWhere((item) => item.left + item.entry.width <= 0);
    _drainQueue();
    notifyListeners();
  }

  void _drainQueue() {
    while (_queue.isNotEmpty) {
      final entry = _queue.first;
      final lane = _findAvailableLane(entry);
      if (lane == null) return;
      _queue.removeFirst();
      _activate(entry, lane);
    }
  }

  int? _findAvailableLane(DanmuEntry entry) {
    if (_laneCount == 0) return null;

    final entrySpeed = entry.speed ?? _config.speed;
    final candidates = <int>[];
    final hintedLane = entry.laneHint;
    if (hintedLane != null && hintedLane >= 0 && hintedLane < _laneCount) {
      candidates.add(hintedLane);
    }
    for (var index = 0; index < _laneCount; index++) {
      if (index != hintedLane) candidates.add(index);
    }

    for (final lane in candidates) {
      var nearestTail = double.negativeInfinity;
      var catchesUp = false;

      for (final item in _active) {
        if (item.lane != lane) continue;
        final tail = item.left + item.entry.width;
        if (tail > nearestTail) nearestTail = tail;

        if (entrySpeed > item.speed) {
          final timeToCatch = (_size.width - tail) / (entrySpeed - item.speed);
          final timeToExit = tail / item.speed;
          if (timeToCatch < timeToExit) {
            catchesUp = true;
            break;
          }
        }
      }

      if (catchesUp) continue;
      if (nearestTail == double.negativeInfinity ||
          nearestTail + _config.gap <= _size.width) {
        return lane;
      }
    }

    return null;
  }

  void _activate(DanmuEntry entry, int lane) {
    _active.add(
      _DanmuItem(
        entry: entry,
        lane: lane,
        left: _size.width,
        speed: entry.speed ?? _config.speed,
        renderId: _nextRenderId++,
      ),
    );
  }

  static DanmuConfig _validatedConfig(DanmuConfig value) {
    Never invalid(String name, Object? actual, String message) {
      throw ArgumentError.value(actual, name, message);
    }

    if (!value.laneHeight.isFinite || value.laneHeight <= 0) {
      invalid('laneHeight', value.laneHeight, 'must be finite and > 0');
    }
    if (!value.laneSpacing.isFinite || value.laneSpacing < 0) {
      invalid('laneSpacing', value.laneSpacing, 'must be finite and >= 0');
    }
    if (value.laneCount <= 0) {
      invalid('laneCount', value.laneCount, 'must be > 0');
    }
    if (!value.gap.isFinite || value.gap < 0) {
      invalid('gap', value.gap, 'must be finite and >= 0');
    }
    if (!value.speed.isFinite || value.speed <= 0) {
      invalid('speed', value.speed, 'must be finite and > 0');
    }
    if (value.maxQueueSize <= 0) {
      invalid('maxQueueSize', value.maxQueueSize, 'must be > 0');
    }
    if (!value.laneExtent.isFinite || value.laneExtent <= 0) {
      invalid(
        'laneExtent',
        value.laneExtent,
        'laneHeight + laneSpacing must stay finite and > 0',
      );
    }
    return value;
  }
}

class _DanmuItem {
  _DanmuItem({
    required this.entry,
    required this.lane,
    required this.left,
    required this.speed,
    required this.renderId,
  });

  final DanmuEntry entry;
  final int lane;
  final double speed;
  final int renderId;
  double left;
}
