import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hax_danmu/hax_danmu.dart';

void main() {
  Widget hostWith(double height, DanmuConfig config) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: height,
            child: HaxDanmu(
              showLanes: true,
              config: config,
            ),
          ),
        ),
      );

  Finder laneBands() => find.descendant(
        of: find.byType(HaxDanmu),
        matching: find.byType(DecoratedBox),
      );

  testWidgets('lane overlay follows effective and updated lane count',
      (tester) async {
    await tester.pumpWidget(
      hostWith(
        200,
        const DanmuConfig(
          laneCount: 4,
          laneHeight: 40,
          laneSpacing: 0,
          autoStart: false,
        ),
      ),
    );
    expect(laneBands(), findsNWidgets(4));

    await tester.pumpWidget(
      hostWith(
        100,
        const DanmuConfig(
          laneCount: 4,
          laneHeight: 40,
          laneSpacing: 0,
          autoStart: false,
        ),
      ),
    );
    expect(laneBands(), findsNWidgets(2));

    await tester.pumpWidget(
      hostWith(
        20,
        const DanmuConfig(
          laneCount: 4,
          laneHeight: 40,
          laneSpacing: 0,
          autoStart: false,
        ),
      ),
    );
    expect(laneBands(), findsNothing);

    await tester.pumpWidget(
      hostWith(
        200,
        const DanmuConfig(
          laneCount: 2,
          laneHeight: 40,
          laneSpacing: 0,
          autoStart: false,
        ),
      ),
    );
    expect(laneBands(), findsNWidgets(2));
  });

  testWidgets('zero-lane queued entry does not keep the ticker alive',
      (tester) async {
    final handle = DanmuHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 20,
            child: HaxDanmu(
              handle: handle,
              config: const DanmuConfig(
                laneCount: 1,
                laneHeight: 40,
                laneSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      handle.send(const DanmuEntry(
        id: 'waiting',
        width: 80,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.queued,
    );
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('stateful child keeps its own state when an earlier item exits',
      (tester) async {
    final handle = DanmuHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 80,
            child: HaxDanmu(
              handle: handle,
              config: const DanmuConfig(
                laneCount: 2,
                laneHeight: 40,
                laneSpacing: 0,
                gap: 0,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      handle.send(const DanmuEntry(
        id: 'duplicate-id',
        width: 50,
        speed: 200,
        laneHint: 0,
        child: _RememberingDanmu(label: 'A'),
      )),
      DanmuEnqueueResult.accepted,
    );
    expect(
      handle.send(const DanmuEntry(
        id: 'duplicate-id',
        width: 50,
        speed: 20,
        laneHint: 1,
        child: _RememberingDanmu(label: 'B'),
      )),
      DanmuEnqueueResult.accepted,
    );

    await tester.pump();
    expect(find.text('A:A'), findsOneWidget);
    expect(find.text('B:B'), findsOneWidget);

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('A:A'), findsNothing);
    expect(find.text('B:B'), findsOneWidget);
    expect(find.text('B:A'), findsNothing);
  });

  testWidgets('pause and resume do not turn wall-clock pause into motion',
      (tester) async {
    const childKey = ValueKey('moving-child');
    final handle = DanmuHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 40,
            child: HaxDanmu(
              handle: handle,
              config: const DanmuConfig(
                laneCount: 1,
                laneHeight: 40,
                laneSpacing: 0,
                speed: 50,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      handle.send(const DanmuEntry(
        id: 'moving',
        width: 50,
        child: SizedBox(key: childKey),
      )),
      DanmuEnqueueResult.accepted,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final beforePause = tester.getTopLeft(find.byKey(childKey)).dx;

    handle.pause();
    await tester.pump(const Duration(seconds: 5));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforePause, 0.001),
    );

    handle.play();
    await tester.pump(const Duration(seconds: 5));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforePause, 0.001),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforePause - 50, 0.001),
    );
  });

  testWidgets('TickerMode mute and resume do not advance silent wall-clock time',
      (tester) async {
    const childKey = ValueKey('ticker-mode-child');
    const danmuKey = ValueKey('ticker-mode-danmu');
    final handle = DanmuHandle();

    Widget host(bool enabled) => MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 40,
              child: TickerMode(
                enabled: enabled,
                child: HaxDanmu(
                  key: danmuKey,
                  handle: handle,
                  config: const DanmuConfig(
                    laneCount: 1,
                    laneHeight: 40,
                    laneSpacing: 0,
                    speed: 50,
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(host(true));
    expect(
      handle.send(const DanmuEntry(
        id: 'ticker-mode-moving',
        width: 50,
        child: SizedBox(key: childKey),
      )),
      DanmuEnqueueResult.accepted,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final beforeMute = tester.getTopLeft(find.byKey(childKey)).dx;

    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(seconds: 5));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforeMute, 0.001),
    );

    await tester.pumpWidget(host(true));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforeMute, 0.001),
    );

    // TickerMode enables the ticker during the rebuild; the resumed ticker's
    // first callback is scheduled for the following frame. That callback must
    // establish a fresh baseline without replaying the muted five seconds.
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforeMute, 0.001),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforeMute - 50, 0.001),
    );
  });

  testWidgets('app lifecycle gaps reset the ticker timebase', (tester) async {
    const childKey = ValueKey('lifecycle-child');
    final handle = DanmuHandle();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 40,
            child: HaxDanmu(
              handle: handle,
              config: const DanmuConfig(
                laneCount: 1,
                laneHeight: 40,
                laneSpacing: 0,
                speed: 50,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      handle.send(const DanmuEntry(
        id: 'lifecycle-moving',
        width: 50,
        child: SizedBox(key: childKey),
      )),
      DanmuEnqueueResult.accepted,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final beforeLifecycleGap = tester.getTopLeft(find.byKey(childKey)).dx;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pump(const Duration(seconds: 5));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforeLifecycleGap, 0.001),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.getTopLeft(find.byKey(childKey)).dx,
      closeTo(beforeLifecycleGap - 50, 0.001),
    );
  });

  testWidgets('stale widget disposal cannot detach a newer handle owner',
      (tester) async {
    const newerKey = ValueKey('newer-danmu');
    const entryKey = ValueKey('newer-entry');
    const config = DanmuConfig(
      laneCount: 1,
      laneHeight: 40,
      laneSpacing: 0,
    );
    final handle = DanmuHandle();

    Widget host({required bool includeOld}) => MaterialApp(
          home: Column(
            children: [
              if (includeOld)
                SizedBox(
                  width: 300,
                  height: 40,
                  child: HaxDanmu(
                    key: const ValueKey('old-danmu'),
                    handle: handle,
                    config: config,
                  ),
                ),
              SizedBox(
                width: 300,
                height: 40,
                child: HaxDanmu(
                  key: newerKey,
                  handle: handle,
                  config: config,
                ),
              ),
            ],
          ),
        );

    await tester.pumpWidget(host(includeOld: true));
    await tester.pumpWidget(host(includeOld: false));

    expect(
      handle.send(const DanmuEntry(
        id: 'newer-owner',
        width: 50,
        child: SizedBox(key: entryKey),
      )),
      DanmuEnqueueResult.accepted,
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(newerKey),
        matching: find.byKey(entryKey),
      ),
      findsOneWidget,
    );
  });

  testWidgets('unbounded fallback matches the actual constrained render edge',
      (tester) async {
    const childKey = ValueKey('unbounded-child');
    final handle = DanmuHandle();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 500),
                  child: HaxDanmu(
                    handle: handle,
                    config: const DanmuConfig(
                      laneCount: 1,
                      laneHeight: 40,
                      laneSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(HaxDanmu)).width, 500);
    expect(
      handle.send(const DanmuEntry(
        id: 'unbounded',
        width: 50,
        child: SizedBox(key: childKey),
      )),
      DanmuEnqueueResult.accepted,
    );
    await tester.pump();

    final viewport = tester.getRect(find.byType(HaxDanmu));
    final entryLeft = tester.getTopLeft(find.byKey(childKey)).dx;
    expect(entryLeft, closeTo(viewport.right, 0.001));
  });
}

class _RememberingDanmu extends StatefulWidget {
  const _RememberingDanmu({required this.label});

  final String label;

  @override
  State<_RememberingDanmu> createState() => _RememberingDanmuState();
}

class _RememberingDanmuState extends State<_RememberingDanmu> {
  late final String initialLabel = widget.label;

  @override
  Widget build(BuildContext context) => Text('${widget.label}:$initialLabel');
}
