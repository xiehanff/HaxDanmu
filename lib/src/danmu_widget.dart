import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'danmu_engine.dart';

/// A lane-based danmu layer. The widget owns only the ticker; scheduling,
/// queueing and motion live in [DanmuEngine]. The optional [handle] lets a
/// page send commands without owning state, and its methods are safe no-ops
/// once the widget is disposed.
class HaxDanmu extends StatefulWidget {
  const HaxDanmu({
    super.key,
    this.handle,
    this.config = const DanmuConfig(),
    this.background,
    this.showLanes = false,
    this.onDisposed,
  });

  final DanmuHandle? handle;

  /// Layout and motion rules. Changes take effect at runtime: lane metrics
  /// are recomputed and active entries on removed lanes are dropped.
  final DanmuConfig config;

  final Widget? background;

  /// Draws the effective lane bands; a debug aid.
  final bool showLanes;

  final VoidCallback? onDisposed;

  @override
  State<HaxDanmu> createState() => _HaxDanmuState();
}

class _HaxDanmuState extends State<HaxDanmu>
    with SingleTickerProviderStateMixin {
  late final DanmuEngine _engine;
  late final Ticker _ticker;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _engine = DanmuEngine(widget.config);
    _ticker = createTicker(_onTick);
    _attachHandle(widget.handle);
  }

  void _attachHandle(DanmuHandle? handle) {
    handle?.attach(
      send: _send,
      play: _play,
      pause: _pause,
      clear: _engine.clear,
    );
  }

  @override
  void didUpdateWidget(covariant HaxDanmu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _engine.updateConfig(widget.config);
    }
    if (oldWidget.handle != widget.handle) {
      oldWidget.handle?.detach();
      _attachHandle(widget.handle);
    }
  }

  @override
  void dispose() {
    widget.handle?.detach();
    _ticker.dispose();
    _engine.dispose();
    widget.onDisposed?.call();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous != null) _engine.advance(elapsed - previous);
    // Nothing left to animate: stop the ticker but keep the playing phase,
    // so the next accepted send restarts motion without an explicit play.
    if (_engine.isIdle) _stopTicker();
  }

  DanmuEnqueueResult _send(DanmuEntry entry) {
    final result = _engine.enqueue(entry);
    if (_engine.phase == DanmuPhase.playing &&
        (result == DanmuEnqueueResult.accepted ||
            result == DanmuEnqueueResult.queued)) {
      _ensureTicker();
    }
    return result;
  }

  void _play() {
    _engine.play();
    if (_engine.phase == DanmuPhase.playing) _ensureTicker();
  }

  void _pause() {
    _engine.pause();
    _stopTicker();
  }

  void _ensureTicker() {
    if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void _stopTicker() {
    _ticker.stop();
    _lastTick = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fallbacks keep the component alive inside unbounded parents (for
        // example a Column) instead of crashing on infinite constraints.
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 300,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 160,
        );
        _engine.configure(size);
        // configure may have activated pending entries (autoStart).
        if (_engine.phase == DanmuPhase.playing) _ensureTicker();
        return AnimatedBuilder(
          animation: _engine,
          builder: (context, child) => ClipRect(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (widget.background != null)
                    Positioned.fill(child: widget.background!),
                  if (widget.showLanes)
                    _LaneOverlay(
                      laneCount: _engine.laneCount,
                      extent: widget.config.laneExtent,
                      spacing: widget.config.laneSpacing,
                    ),
                  ..._engine.activeItems.map(
                    (item) => Positioned(
                      left: item.left,
                      top: item.lane * widget.config.laneExtent,
                      width: item.entry.width,
                      height: widget.config.laneHeight,
                      child: RepaintBoundary(child: item.entry.child),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One debug band per lane. It uses the engine's effective lane count, which
/// can be smaller than [DanmuConfig.laneCount] when the height cannot fit
/// them all; with that count the column can never overflow its height.
class _LaneOverlay extends StatelessWidget {
  const _LaneOverlay({
    required this.laneCount,
    required this.extent,
    required this.spacing,
  });

  final int laneCount;
  final double extent;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: List<Widget>.generate(laneCount, (_) {
          return SizedBox(
            height: extent,
            child: Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white12)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
