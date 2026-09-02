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
}
