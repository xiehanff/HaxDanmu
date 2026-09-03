import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'danmu_engine.dart';

/// Command bridge for a mounted [HaxDanmu].
///
/// Commands are safe no-ops before attachment and after disposal. Binding
/// ownership stays private to the widget so hosts only see the commands they
/// are expected to call.
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

  Object _attach({
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

  void _detach(Object attachment) {
    if (!identical(_attachment, attachment)) return;
    _attachment = null;
    _send = null;
    _play = null;
    _pause = null;
    _clear = null;
  }
}

/// A lane-based danmu layer.
///
/// Scheduling and motion live in [DanmuEngine]; this widget only adapts that
/// state to Flutter layout and a single [Ticker].
class HaxDanmu extends StatefulWidget {
  const HaxDanmu({
    super.key,
    this.handle,
    this.config = const DanmuConfig(),
    this.showLanes = false,
  });

  final DanmuHandle? handle;
  final DanmuConfig config;

  /// Draws the effective lane bands as a debug aid.
  final bool showLanes;

  @override
  State<HaxDanmu> createState() => _HaxDanmuState();
}

class _HaxDanmuState extends State<HaxDanmu>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final DanmuEngine _engine;
  late final Ticker _ticker;
  Duration? _lastTick;
  bool? _tickerModeEnabled;
  Object? _handleAttachment;

  @override
  void initState() {
    super.initState();
    _engine = DanmuEngine(widget.config);
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    _attachHandle(widget.handle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode.valuesOf is newer than the package's Flutter 3.27 minimum.
    // Keep this compatibility read until the minimum supported Flutter moves
    // past the transition, then migrate to the newer API.
    // ignore: deprecated_member_use
    final tickerModeEnabled = TickerMode.of(context);
    if (_tickerModeEnabled != tickerModeEnabled) {
      _tickerModeEnabled = tickerModeEnabled;
      _resetTickBaseline();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resetTickBaseline();
  }

  void _attachHandle(DanmuHandle? handle) {
    _handleAttachment = handle?._attach(
      send: _send,
      play: _play,
      pause: _pause,
      clear: _engine.clear,
    );
  }

  void _detachHandle(DanmuHandle? handle) {
    final attachment = _handleAttachment;
    if (handle != null && attachment != null) {
      handle._detach(attachment);
    }
    _handleAttachment = null;
  }

  @override
  void didUpdateWidget(covariant HaxDanmu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _engine.updateConfig(widget.config);
    }
    if (oldWidget.handle != widget.handle) {
      _detachHandle(oldWidget.handle);
      _attachHandle(widget.handle);
    }
  }

  @override
  void dispose() {
    _detachHandle(widget.handle);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous != null) _engine.advance(elapsed - previous);
    if (!_engine.needsFrame) _stopTicker();
  }

  DanmuEnqueueResult _send(DanmuEntry entry) {
    final result = _engine.enqueue(entry);
    if (_engine.needsFrame) _ensureTicker();
    return result;
  }

  void _play() {
    _engine.play();
    if (_engine.needsFrame) _ensureTicker();
  }

  void _pause() {
    _engine.pause();
    _stopTicker();
  }

  void _ensureTicker() {
    if (_ticker.isActive) return;
    _resetTickBaseline();
    _ticker.start();
  }

  void _stopTicker() {
    if (_ticker.isActive) _ticker.stop();
    _resetTickBaseline();
  }

  void _resetTickBaseline() {
    _lastTick = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredSize = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 300,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 160,
        );
        final size = constraints.constrain(desiredSize);
        _engine.configure(size);

        if (_engine.needsFrame) {
          _ensureTicker();
        } else {
          _stopTicker();
        }

        return AnimatedBuilder(
          animation: _engine,
          builder: (context, child) => ClipRect(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (widget.showLanes)
                    _LaneOverlay(
                      laneCount: _engine.laneCount,
                      extent: widget.config.laneExtent,
                      spacing: widget.config.laneSpacing,
                    ),
                  ..._engine.activeItems.map(
                    (item) => Positioned(
                      key: ValueKey(item.renderId),
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
