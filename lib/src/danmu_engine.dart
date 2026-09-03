import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Playback priority for entries waiting to be activated.
enum DanmuPriority { normal, high }

/// Result returned by [DanmuHandle.send].
enum DanmuEnqueueResult {
  /// Placed on a lane immediately.
  accepted,

  /// Accepted and waiting for layout or an available lane.
  queued,

  /// Rejected because the entry is invalid or the waiting queue is full.
  rejected,
}

/// Immutable layout and motion configuration for [HaxDanmu].
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

  /// Painted height of one lane entry.
  final double laneHeight;

  /// Vertical spacing after each lane.
  final double laneSpacing;

  /// Maximum number of lanes; actual count also depends on viewport height.
  final int laneCount;

  /// Minimum launch gap between neighbouring entries on one lane.
  final double gap;

  /// Default scrolling speed in logical pixels per second.
  final double speed;

  /// Maximum number of entries waiting to be activated.
  ///
  /// This is an admission limit. Lowering it at runtime does not discard
  /// entries that were already accepted; new sends are rejected until the
  /// waiting count falls below the new limit.
  final int maxQueueSize;

  /// Whether playback starts automatically once valid layout is available.
  final bool autoStart;

  /// Vertical pitch occupied by one lane.
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

/// One danmu payload.
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

  /// Host-owned business identifier. It is not used as render identity.
  final String id;

  /// Widget painted for this entry.
  final Widget child;

  /// Expected painted width of [child] in logical pixels.
  ///
  /// The scheduler uses this value for collision and exit calculations, so it
  /// must match the rendered width supplied by the host.
  final double width;

  /// Optional per-entry speed override.
  final double? speed;

  /// Waiting-queue priority.
  final DanmuPriority priority;

  /// Preferred lane; ignored when unavailable or out of range.
  final int? laneHint;
}

enum _DanmuPhase { unconfigured, stopped, playing }

/// Internal mutable render/scheduling item shared with the Flutter adapter.
class ActiveDanmu {
  ActiveDanmu({
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

/// Internal scheduling state: lanes, queueing, and per-frame motion.
class DanmuEngine extends ChangeNotifier {
  DanmuEngine(DanmuConfig config) : _config = _validatedConfig(config);

  DanmuConfig _config;
  final List<ActiveDanmu> _active = [];
  late final UnmodifiableListView<ActiveDanmu> _activeView =
      UnmodifiableListView(_active);
  final Queue<DanmuEntry> _queue = Queue<DanmuEntry>();
  _DanmuPhase _phase = _DanmuPhase.unconfigured;
  Size _size = Size.zero;
  int _laneCount = 0;
  int _nextRenderId = 0;

  DanmuConfig get config => _config;
  int get laneCount => _laneCount;
  int get waitingCount => _queue.length;
  UnmodifiableListView<ActiveDanmu> get activeItems => _activeView;

  bool get needsFrame =>
      _phase == _DanmuPhase.playing &&
      _active.isNotEmpty &&
      _size != Size.zero &&
      _laneCount > 0;

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
    if (_phase == _DanmuPhase.unconfigured) {
      _phase = _config.autoStart ? _DanmuPhase.playing : _DanmuPhase.stopped;
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
    if (_phase == _DanmuPhase.stopped) {
      _phase = _DanmuPhase.playing;
      notifyListeners();
    }
  }

  void pause() {
    if (_phase == _DanmuPhase.playing) {
      _phase = _DanmuPhase.stopped;
      notifyListeners();
    }
  }

  void clear() {
    _active.clear();
    _queue.clear();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (_phase != _DanmuPhase.playing) return;

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
      ActiveDanmu(
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
