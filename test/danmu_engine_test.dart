import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hax_danmu/src/danmu_engine.dart';

void main() {
  DanmuEntry entry(String id) => DanmuEntry(
        id: id,
        width: 100,
        child: const SizedBox(),
      );

  test('queues when the only lane is busy', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
      ),
    );
    engine.configure(const Size(300, 40));

    expect(engine.enqueue(entry('first')), DanmuEnqueueResult.accepted);
    expect(engine.enqueue(entry('second')), DanmuEnqueueResult.queued);
    expect(engine.activeItems, hasLength(1));
    expect(engine.waitingCount, 1);
  });

  test('drains a queued item after the active item exits', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('first'));
    engine.enqueue(entry('second'));

    engine.advance(const Duration(seconds: 4));

    expect(engine.activeItems.single.entry.id, 'second');
    expect(engine.waitingCount, 0);
  });

  test('high priority waits ahead of normal entries and stays FIFO', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));
    engine.enqueue(entry('normal'));
    engine.enqueue(const DanmuEntry(
      id: 'high-1',
      width: 100,
      priority: DanmuPriority.high,
      child: SizedBox(),
    ));
    engine.enqueue(const DanmuEntry(
      id: 'high-2',
      width: 100,
      priority: DanmuPriority.high,
      child: SizedBox(),
    ));

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'high-1');

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'high-2');
  });

  test('falls back to an available lane when the hint is busy', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 2,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
      ),
    );
    engine.configure(const Size(300, 80));
    engine.enqueue(const DanmuEntry(
      id: 'slow-lane-0',
      width: 100,
      speed: 5,
      laneHint: 0,
      child: SizedBox(),
    ));
    engine.enqueue(const DanmuEntry(
      id: 'fast-lane-1',
      width: 100,
      speed: 100,
      laneHint: 1,
      child: SizedBox(),
    ));
    engine.enqueue(const DanmuEntry(
      id: 'hinted',
      width: 100,
      laneHint: 0,
      child: SizedBox(),
    ));
    engine.enqueue(entry('fallback'));
    engine.advance(const Duration(seconds: 4));

    expect(engine.activeItems.map((item) => item.entry.id), contains('hinted'));
  });

  test('sends before layout are simply queued and later activated', () {
    final engine = DanmuEngine(const DanmuConfig(laneCount: 2));

    expect(engine.enqueue(entry('before-layout')), DanmuEnqueueResult.queued);

    engine.configure(const Size(300, 80));

    expect(engine.activeItems, hasLength(1));
    expect(engine.waitingCount, 0);
  });

  test('prevents a faster follower from catching a slower entry', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(const DanmuEntry(
      id: 'slow',
      width: 100,
      speed: 100,
      child: SizedBox(),
    ));
    engine.advance(const Duration(milliseconds: 1500));

    expect(
      engine.enqueue(const DanmuEntry(
        id: 'fast',
        width: 50,
        speed: 200,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.queued,
    );
    expect(
      engine.enqueue(const DanmuEntry(
        id: 'slower',
        width: 50,
        speed: 60,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.accepted,
    );
  });

  test('drops active entries whose lanes are removed', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 4,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 0,
      ),
    );
    engine.configure(const Size(300, 160));
    engine.enqueue(entry('a'));
    engine.enqueue(entry('b'));
    engine.enqueue(entry('c'));

    engine.updateConfig(
      const DanmuConfig(
        laneCount: 2,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 0,
      ),
    );

    expect(engine.laneCount, 2);
    expect(engine.activeItems.map((item) => item.entry.id), ['a', 'b']);
  });

  test('rejects invalid per-entry speeds in release-safe engine checks', () {
    final engine = DanmuEngine(const DanmuConfig(laneCount: 2));
    engine.configure(const Size(300, 80));

    expect(
      engine.enqueue(const DanmuEntry(
        id: 'nan-speed',
        width: 100,
        speed: double.nan,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.rejected,
    );
    expect(
      engine.enqueue(const DanmuEntry(
        id: 'infinite-speed',
        width: 100,
        speed: double.infinity,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.rejected,
    );
  });

  test('zero effective lanes wait without requesting animation frames', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 20));

    expect(engine.enqueue(entry('waiting')), DanmuEnqueueResult.queued);
    expect(engine.needsFrame, isFalse);

    engine.configure(const Size(300, 40));

    expect(engine.activeItems.single.entry.id, 'waiting');
    expect(engine.needsFrame, isTrue);
  });

  test('zero-size layout pauses geometry without losing active work', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));

    engine.configure(Size.zero);

    expect(engine.activeItems, hasLength(1));
    expect(engine.needsFrame, isFalse);

    engine.configure(const Size(300, 40));

    expect(engine.activeItems, hasLength(1));
    expect(engine.needsFrame, isTrue);
  });

  test('active entries keep the effective speed captured at launch', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 0,
        speed: 60,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(const DanmuEntry(
      id: 'front',
      width: 50,
      speed: 100,
      child: SizedBox(),
    ));
    engine.advance(const Duration(seconds: 1));
    engine.enqueue(const DanmuEntry(
      id: 'default-speed',
      width: 50,
      child: SizedBox(),
    ));

    engine.updateConfig(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 0,
        speed: 200,
      ),
    );
    engine.advance(const Duration(seconds: 2));

    final follower = engine.activeItems.singleWhere(
      (item) => item.entry.id == 'default-speed',
    );
    expect(follower.left, closeTo(180, 0.001));
  });

  test('render identity stays unique when business ids repeat', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 2,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 80));
    engine.enqueue(entry('same-id'));
    engine.enqueue(entry('same-id'));

    expect(engine.activeItems.map((item) => item.renderId).toSet(), hasLength(2));
  });

  group('runtime config validation', () {
    final cases = <DanmuConfig>[
      const DanmuConfig(laneHeight: double.nan),
      const DanmuConfig(laneHeight: 0),
      const DanmuConfig(laneSpacing: -1),
      const DanmuConfig(laneCount: 0),
      const DanmuConfig(gap: -1),
      const DanmuConfig(speed: double.nan),
      const DanmuConfig(speed: 0),
      const DanmuConfig(maxQueueSize: 0),
    ];

    for (final config in cases) {
      test('$config is rejected', () {
        expect(() => DanmuEngine(config), throwsArgumentError);
      });
    }
  });

  test('failed runtime config update keeps the previous config', () {
    final engine = DanmuEngine(const DanmuConfig(speed: 100));

    expect(
      () => engine.updateConfig(const DanmuConfig(speed: double.infinity)),
      throwsArgumentError,
    );
    expect(engine.config.speed, 100);
  });

  test('maxQueueSize bounds pre-layout admission', () {
    final engine = DanmuEngine(const DanmuConfig(maxQueueSize: 2));

    expect(engine.enqueue(entry('one')), DanmuEnqueueResult.queued);
    expect(engine.enqueue(entry('two')), DanmuEnqueueResult.queued);
    expect(engine.enqueue(entry('three')), DanmuEnqueueResult.rejected);
    expect(engine.waitingCount, 2);
  });

  test('zero-size accepted entries survive geometry restoration', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
        maxQueueSize: 2,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));
    engine.enqueue(entry('already-waiting'));

    engine.configure(Size.zero);
    expect(engine.enqueue(entry('accepted-while-zero')), DanmuEnqueueResult.queued);
    expect(engine.enqueue(entry('over-capacity')), DanmuEnqueueResult.rejected);

    engine.configure(const Size(300, 40));
    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'already-waiting');

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'accepted-while-zero');
    expect(engine.waitingCount, 0);
  });

  test('lowering maxQueueSize never discards already accepted entries', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
        maxQueueSize: 3,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));
    engine.enqueue(entry('one'));
    engine.enqueue(entry('two'));
    engine.enqueue(entry('three'));

    engine.updateConfig(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
        maxQueueSize: 1,
      ),
    );

    expect(engine.waitingCount, 3);
    expect(engine.enqueue(entry('new')), DanmuEnqueueResult.rejected);

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'one');
    expect(engine.waitingCount, 2);
  });

  test('pause freezes motion and resume continues from the same position', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        speed: 100,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('moving'));
    engine.advance(const Duration(seconds: 1));
    final beforePause = engine.activeItems.single.left;

    engine.pause();
    engine.advance(const Duration(seconds: 5));
    expect(engine.activeItems.single.left, beforePause);

    engine.play();
    engine.advance(const Duration(seconds: 1));
    expect(engine.activeItems.single.left, closeTo(beforePause - 100, 0.001));
  });

  test('clear removes active and waiting entries', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));
    engine.enqueue(entry('waiting'));

    engine.clear();

    expect(engine.activeItems, isEmpty);
    expect(engine.waitingCount, 0);
    expect(engine.needsFrame, isFalse);
  });
}
