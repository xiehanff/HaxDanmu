import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hax_danmu/hax_danmu.dart';

void main() {
  // Center releases the navigator's tight full-screen constraints so the
  // SizedBox really dictates the component size.
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

  testWidgets('lane overlay follows the effective and updated lane count',
      (tester) async {
    // Height 200 / extent 40 fits five lanes, but laneCount caps them at 4:
    // the overlay must mirror the engine, not the raw config.
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
    await tester.pump();
    expect(laneBands(), findsNWidgets(4));

    // A height that fits only two lanes must shrink the overlay with it.
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
    await tester.pump();
    expect(laneBands(), findsNWidgets(2));

    // A viewport shorter than one lane keeps the overlay empty instead of
    // producing a RenderFlex overflow for a clipped lane.
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
    await tester.pump();
    expect(laneBands(), findsNothing);

    // Runtime config changes must reach the engine through didUpdateWidget.
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
    await tester.pump();
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
    await tester.pump();

    expect(
      handle.send(const DanmuEntry(
        id: 'waiting',
        width: 80,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.queued,
    );
    await tester.pump();

    // An active ticker would keep scheduling frames and make this time out.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 10),
      timeout: const Duration(milliseconds: 250),
    );
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
    await tester.pump();

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

    // Seed the ticker's previous timestamp, then advance enough for A to
    // leave while B remains. Without stable keys Flutter can reuse A's State
    // for B when the active child list shifts from [A, B] to [B].
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('A:A'), findsNothing);
    expect(find.text('B:B'), findsOneWidget);
    expect(find.text('B:A'), findsNothing);
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
