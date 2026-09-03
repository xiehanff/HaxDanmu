import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Playback priority. High-priority entries jump ahead of normal ones in
/// the waiting queue when every lane is busy.
enum DanmuPriority { normal, high }

/// Lifecycle of the engine. A single enum prevents impossible flag
/// combinations such as "playing while paused".
enum DanmuPhase { unconfigured, ready, playing, paused }

/// Outcome of [DanmuHandle.send] / [DanmuEngine.enqueue].
enum DanmuEnqueueResult {
  /// Placed on a lane immediately.
  accepted,

  /// All lanes busy; stored in the waiting queue.
  queued,

  /// Stored until the first layout resolves the lane geometry.
  pendingLayout,

  /// Dropped: invalid entry (width/speed), or a queue is full.
  rejected,
}

/// Layout and motion rules. Immutable value object with structural equality
/// so the widget can detect config changes in [State.didUpdateWidget] and
/// forward them to [DanmuEngine.updateConfig].
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
  })  : assert(laneHeight > 0 && laneHeight != double.infinity),
        assert(laneSpacing >= 0 && laneSpacing != double.infinity),
        assert(laneCount > 0),
        assert(gap >= 0 && gap != double.infinity),
        assert(speed > 0 && speed != double.infinity),
        assert(maxQueueSize > 0);

  /// Painted height of one entry.
  final double laneHeight;

  /// Vertical space between neighbouring lanes.
  final double laneSpacing;

  /// Maximum number of lanes. The effective count also depends on the
  /// available height and is exposed by [DanmuEngine.laneCount].
  final int laneCount;

  /// Minimum horizontal distance between the tail of the last entry on a
  /// lane and the head of the next one at launch time.
  final double gap;

  /// Default scrolling speed in logical pixels per second.
  final double speed;

  /// Bound for both the waiting queue and the pre-layout queue.
  final int maxQueueSize;

  /// Whether [DanmuPhase.playing] is entered on the first layout.
  final bool autoStart;

  /// Vertical pitch of one lane: painted height plus spacing.
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

/// One danmu payload. [width] must match the painted width of [child]: the
/// engine never lays [child] out, it only positions it. Entries whose
/// [width] or [speed] is non-positive or NaN are rejected by
/// [DanmuEngine.enqueue] in release builds as well, because asserts are
/// stripped there and such entries would corrupt motion and lane recycling.
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

  /// Painted width of [child] in logical pixels.
  final double width;

  /// Per-entry override of [DanmuConfig.speed] in logical pixels per second.
  final double? speed;

  final DanmuPriority priority;

  /// Preferred lane; ignored when out of range for the current layout.
  final int? laneHint;
}

/// Point-in-time counters for host-side diagnostics.
@immutable
class DanmuSnapshot {
  const DanmuSnapshot({
    required this.phase,
    required this.activeCount,
    required this.queuedCount,
  });

  final DanmuPhase phase;
  final int activeCount;
  final int queuedCount;
}

/// Render-ready projection of one active item, in logical pixels relative to
/// the viewport passed to [DanmuEngine.configure].
@immutable
class ActiveDanmu {
  const ActiveDanmu({
    required this.entry,
    required this.lane,
    required this.left,
    this.renderId = 0,
  });

  final DanmuEntry entry;
  final int lane;
  final double left;

  /// Engine-generated identity for Flutter element reconciliation. It is
  /// independent of [DanmuEntry.id], which is allowed to repeat.
  final int renderId;
}

/// A command bridge. It owns no playback state; the widget installs callbacks.
/// Every command is a safe no-op once the current widget detaches (or before
/// any widget mounts), so hosts may keep the handle across route changes.
class DanmuHandle {
  DanmuEnqueueResult send(DanmuEntry entry) =>
      _send?.call(entry) ?? DanmuEnqueueResult.rejected;

  void play() => _play?.call();
  void pause() => _pause?.call();
  void clear() => _clear?.call();

  DanmuEnqueueResult Function(DanmuEntry entry)? _send;
  VoidCallback? _play;
  VoidCallback? _pause;
  VoidCallback? _clear;
  Object? _attachment;

  /// Installs a command target and returns an ownership token. A later attach
  /// replaces the previous target. Calling [detach] with a stale token is a
  /// no-op, so disposal of an old widget cannot detach a newer widget that
  /// reused the same handle.
  Object attach({
    required DanmuEnqueueResult Function(DanmuEntry entry) send,
    required VoidCallback play,
    required VoidCallback pause,
    required VoidCallback clear,
  }) {
    final attachment = Object();
    _attachment = attachment;
    _send = send;
    _play = play;
    _pause = pause;
    _clear = clear;
    return attachment;
  }

  /// Detaches the current command target. Passing the token returned by
  /// [attach] makes the operation ownership-safe; omitting it preserves the
  /// original 0.1 API and force-detaches whichever target is current.
  void detach([Object? attachment]) {
    if (attachment != null && !identical(_attachment, attachment)) return;
    _attachment = null;
    _send = null;
    _play = null;
    _pause = null;
    _clear = null;
  }
}

/// Pure scheduling state: lanes, queueing, and per-frame motion. The widget
/// supplies the clock, so this class can be tested without a Flutter frame
/// and reused by another renderer.
class DanmuEngine extends ChangeNotifier {
  DanmuEngine(DanmuConfig config) : _config = config;

  DanmuConfig _config;

  final List<_DanmuItem> _active = [];
  final Queue<DanmuEntry> _queue = Queue<DanmuEntry>();
  final Queue<DanmuEntry> _pendingLayout = Queue<DanmuEntry>();
  DanmuPhase _phase = DanmuPhase.unconfigured;
  Size _size = Size.zero;
  int _laneCount = 0;
  int _nextRenderId = 0;

  /// The active config; replace it at runtime with [updateConfig].
  DanmuConfig get config => _config;

  DanmuPhase get phase => _phase;

  /// Lanes available for the current size: 0 before the first [configure],
  /// afterwards between 0 and [DanmuConfig.laneCount]. A viewport shorter
  /// than one lane keeps messages queued until it grows.
  int get laneCount => _laneCount;

  /// True when nothing is active, queued, or awaiting layout.
  bool get isIdle =>
      _active.isEmpty && _queue.isEmpty && _pendingLayout.isEmpty;

  /// Whether advancing time can visibly change the current frame. Waiting
  /// entries alone do not need a ticker: they are drained synchronously when
  /// layout/config changes make a lane available.
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

  DanmuSnapshot get snapshot => DanmuSnapshot(
        phase: _phase,
        activeCount: _active.length,
        queuedCount: _queue.length + _pendingLayout.length,
      );

  /// Publishes the viewport size. Never notifies: it is called from build,
  /// and the caller rebuilds in the same frame anyway.
  void configure(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      // Invalidate geometry so the widget can stop its ticker. Active entries
      // are kept and may resume if a later valid layout can still host them.
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
    while (_pendingLayout.isNotEmpty) {
      _enqueueReady(_pendingLayout.removeFirst(), notify: false);
    }
    _drainQueue();
  }

  /// Applies a new config at runtime (e.g. from [State.didUpdateWidget]).
  /// Lane metrics are recomputed and active entries on removed lanes are
  /// dropped so they cannot keep scrolling through invisible geometry.
  /// Existing active entries keep the effective speed they had at launch;
  /// a new default speed only affects entries activated afterwards.
  void updateConfig(DanmuConfig value) {
    if (value == _config) return;
    _config = value;
    if (_size == Size.zero) return;
    _setLaneCount(_laneCountFor(_size));
    _drainQueue();
    notifyListeners();
  }

  int _laneCountFor(Size size) =>
      (size.height / _config.laneExtent).floor().clamp(0, _config.laneCount);

  void _setLaneCount(int nextLaneCount) {
    if (nextLaneCount == _laneCount) return;
    _laneCount = nextLaneCount;
    _active.removeWhere((item) => item.lane >= _laneCount);
  }

  DanmuEnqueueResult enqueue(DanmuEntry entry) {
    // Release builds strip asserts, so the engine re-checks the invariants
    // it depends on: a non-positive width breaks exit detection and a
    // non-positive speed freezes an entry inside its lane forever.
    final entrySpeed = entry.speed;
    final invalidSpeed =
        entrySpeed != null && (!entrySpeed.isFinite || entrySpeed <= 0);
    if (!entry.width.isFinite || entry.width <= 0 || invalidSpeed) {
      return DanmuEnqueueResult.rejected;
    }
    if (_size == Size.zero) {
      if (_pendingLayout.length >= _config.maxQueueSize) {
        return DanmuEnqueueResult.rejected;
      }
      _pendingLayout.add(entry);
      return DanmuEnqueueResult.pendingLayout;
    }
    return _enqueueReady(entry);
  }

  DanmuEnqueueResult _enqueueReady(
    DanmuEntry entry, {
    bool notify = true,
  }) {
    final lane = _findAvailableLane(entry);
    final result =
        lane == null ? DanmuEnqueueResult.queued : DanmuEnqueueResult.accepted;
    if (result == DanmuEnqueueResult.accepted) {
      _activate(entry, lane!);
    } else if (_queue.length < _config.maxQueueSize) {
      _enqueueQueued(entry);
    } else {
      return DanmuEnqueueResult.rejected;
    }
    if (notify) notifyListeners();
    return result;
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
    _pendingLayout.clear();
    notifyListeners();
  }

  /// Integrates motion. [elapsed] is the delta since the previous call, not
  /// an absolute timestamp, so pause/resume cannot produce time jumps.
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

  /// A lane accepts the entry when the launch gap to the nearest item ahead
  /// is respected AND the entry can never overlap any item ahead. Because
  /// speeds can differ per entry, "never overlap" must hold for every
  /// slower item on the lane, not just the nearest one: catching up takes
  /// `(width - tail) / (vNew - vOld)` seconds while the slower item needs
  /// `tail / vOld` seconds to leave the viewport, so the faster entry is
  /// only admitted when the slower item is gone by then.
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
