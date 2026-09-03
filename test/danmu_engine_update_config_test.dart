import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hax_danmu/hax_danmu.dart';

void main() {
  DanmuEntry entry(String id) => DanmuEntry(
        id: id,
        width: 100,
        child: const SizedBox(),
      );

  test('opens new lanes before trimming a smaller waiting limit', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        maxQueueSize: 3,
      ),
    );
    engine.configure(const Size(300, 80));
    engine.enqueue(entry('active'));
    engine.enqueue(entry('waiting-1'));
    engine.enqueue(entry('waiting-2'));
    engine.enqueue(entry('waiting-3'));

    expect(engine.snapshot.activeCount, 1);
    expect(engine.snapshot.queuedCount, 3);

    engine.updateConfig(
      const DanmuConfig(
        laneCount: 2,
        laneHeight: 40,
        laneSpacing: 0,
        maxQueueSize: 1,
      ),
    );

    // Lane 1 became available, so waiting-1 must be activated before the new
    // queue limit is enforced. Of the remaining two waiters, only one is kept.
    expect(engine.snapshot.activeCount, 2);
    expect(
      engine.activeItems.map((item) => item.entry.id),
      contains('waiting-1'),
    );
    expect(engine.snapshot.queuedCount, 1);
  });
}
