import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hax_danmu/hax_danmu.dart';

void main() {
  test('tiny finite lane extent caps lane count without flooring infinity', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 4,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 160));

    expect(
      () => engine.updateConfig(
        const DanmuConfig(
          laneCount: 4,
          laneHeight: double.minPositive,
          laneSpacing: 0,
        ),
      ),
      returnsNormally,
    );

    expect(engine.laneCount, 4);
    expect(engine.config.laneHeight, double.minPositive);
  });

  testWidgets(
      'unbounded fallback obeys minimum constraints and matches render edge',
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

    // First ticker frame establishes its timestamp and must not move the item.
    await tester.pump();

    final viewport = tester.getRect(find.byType(HaxDanmu));
    final entryLeft = tester.getTopLeft(find.byKey(childKey)).dx;
    expect(entryLeft, closeTo(viewport.right, 0.001));
  });
}
