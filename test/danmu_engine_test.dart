import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hax_danmu/hax_danmu.dart';

void main() {
  DanmuEntry entry(String id) => DanmuEntry(
        id: id,
        width: 100,
        child: const SizedBox(),
      );

  test('keeps the first item active and queues a collision', () {
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
    expect(engine.snapshot.activeCount, 1);
    expect(engine.snapshot.queuedCount, 1);
  });

  test('drains a queued item after enough time has elapsed', () {
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
    engine.play();

    engine.advance(const Duration(seconds: 4));

    expect(engine.snapshot.activeCount, 1);
    expect(engine.snapshot.queuedCount, 0);
    expect(engine.activeItems.single.entry.id, 'second');
  });

  test('keeps high-priority entries FIFO', () {
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
    engine.play();
    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'high-1');
  });

  test('falls back to an available lane when a hint is busy', () {
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
    engine.play();
    engine.advance(const Duration(seconds: 4));

    expect(engine.activeItems.map((item) => item.entry.id), contains('hinted'));
  });

  test('accepts sends before the first layout without losing them', () {
    final engine = DanmuEngine(const DanmuConfig(laneCount: 2));
    expect(
      engine.enqueue(entry('before-layout')),
      DanmuEnqueueResult.pendingLayout,
    );

    engine.configure(const Size(300, 80));

    expect(engine.snapshot.activeCount, 1);
    expect(engine.snapshot.queuedCount, 0);
  });

  test('queues a faster entry that would catch a slower one mid-screen', () {
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
    // Head at 150, tail at 250: the gap rule alone would admit a newcomer.
    engine.advance(const Duration(milliseconds: 1500));

    // At speed 200 the new entry reaches the slow one after 0.5s while the
    // slow one needs 2.5s to exit, so the lane must stay closed for it.
    expect(
      engine.enqueue(const DanmuEntry(
        id: 'fast',
        width: 50,
        speed: 200,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.queued,
    );
    // A slower follower can never catch up, so it is admitted.
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

  test('drains high-priority entries before normal ones', () {
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
    engine.enqueue(entry('normal'));
    engine.enqueue(const DanmuEntry(
      id: 'high',
      width: 100,
      priority: DanmuPriority.high,
      child: SizedBox(),
    ));
    engine.play();

    engine.advance(const Duration(seconds: 4));

    expect(engine.activeItems.single.entry.id, 'high');
  });

  test('drops items on lanes removed by a config change', () {
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
    expect(engine.activeItems.map((item) => item.lane), [0, 1, 2]);

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

  test('rejects entries with invalid width or speed even without asserts', () {
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

  test('zero effective lanes queue without requesting animation frames', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 20));

    expect(engine.laneCount, 0);
    expect(engine.enqueue(entry('waiting')), DanmuEnqueueResult.queued);
    expect(engine.needsFrame, isFalse);

    engine.configure(const Size(300, 40));

    expect(engine.snapshot.activeCount, 1);
    expect(engine.snapshot.queuedCount, 0);
    expect(engine.activeItems.single.entry.id, 'waiting');
    expect(engine.needsFrame, isTrue);
  });

  test('zero-size layout invalidates geometry without burning frames', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));
    expect(engine.needsFrame, isTrue);

    engine.configure(Size.zero);

    expect(engine.laneCount, 0);
    expect(engine.snapshot.activeCount, 1);
    expect(engine.needsFrame, isFalse);

    engine.configure(const Size(300, 40));

    expect(engine.snapshot.activeCount, 1);
    expect(engine.needsFrame, isTrue);
  });

  test('active entries keep their launch speed after config speed changes', () {
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

    expect(
      engine.enqueue(const DanmuEntry(
        id: 'default-speed',
        width: 50,
        child: SizedBox(),
      )),
      DanmuEnqueueResult.accepted,
    );

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

  test('render identity is unique even when business ids repeat', () {
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

    final ids = engine.activeItems.map((item) => item.renderId).toSet();
    expect(ids, hasLength(2));
  });

  test('stale handle detach cannot clear a newer attachment', () {
    final handle = DanmuHandle();
    var firstPlayCount = 0;
    var secondPlayCount = 0;

    final firstAttachment = handle.attach(
      send: (_) => DanmuEnqueueResult.accepted,
      play: () => firstPlayCount++,
      pause: () {},
      clear: () {},
    );
    final secondAttachment = handle.attach(
      send: (_) => DanmuEnqueueResult.accepted,
      play: () => secondPlayCount++,
      pause: () {},
      clear: () {},
    );

    handle.detach(firstAttachment);
    handle.play();

    expect(firstPlayCount, 0);
    expect(secondPlayCount, 1);

    handle.detach(secondAttachment);
    handle.play();
    expect(secondPlayCount, 1);
  });

  group('validates config in every build mode', () {
    final cases = <String, DanmuConfig>{
      'nan lane height': const DanmuConfig(laneHeight: double.nan),
      'infinite lane height':
          const DanmuConfig(laneHeight: double.infinity),
      'zero lane height': const DanmuConfig(laneHeight: 0),
      'negative lane spacing': const DanmuConfig(laneSpacing: -1),
      'nan lane spacing': const DanmuConfig(laneSpacing: double.nan),
      'zero lane count': const DanmuConfig(laneCount: 0),
      'negative gap': const DanmuConfig(gap: -1),
      'infinite gap': const DanmuConfig(gap: double.infinity),
      'zero speed': const DanmuConfig(speed: 0),
      'nan speed': const DanmuConfig(speed: double.nan),
      'zero queue size': const DanmuConfig(maxQueueSize: 0),
      'overflowing lane extent': const DanmuConfig(
        laneHeight: double.maxFinite,
        laneSpacing: double.maxFinite,
      ),
    };

    for (final MapEntry(key: name, value: config) in cases.entries) {
      test(name, () {
        expect(() => DanmuEngine(config), throwsArgumentError);
      });
    }
  });

  test('invalid runtime config leaves the previous config untouched', () {
    final engine = DanmuEngine(const DanmuConfig(speed: 100));

    expect(
      () => engine.updateConfig(const DanmuConfig(speed: double.infinity)),
      throwsArgumentError,
    );

    expect(engine.config.speed, 100);
  });

  test('maxQueueSize is a total bound before layout', () {
    final engine = DanmuEngine(const DanmuConfig(maxQueueSize: 2));

    expect(engine.enqueue(entry('one')), DanmuEnqueueResult.pendingLayout);
    expect(engine.enqueue(entry('two')), DanmuEnqueueResult.pendingLayout);
    expect(engine.enqueue(entry('three')), DanmuEnqueueResult.rejected);
    expect(engine.snapshot.queuedCount, 2);

    engine.configure(const Size(300, 160));

    expect(engine.snapshot.activeCount, 2);
    expect(engine.snapshot.queuedCount, 0);
  });

  test('pending-layout result is never silently lost after zero-size resize', () {
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
    expect(engine.enqueue(entry('active')), DanmuEnqueueResult.accepted);
    expect(engine.enqueue(entry('already-waiting')), DanmuEnqueueResult.queued);

    engine.configure(Size.zero);
    expect(
      engine.enqueue(entry('accepted-while-zero')),
      DanmuEnqueueResult.pendingLayout,
    );
    expect(engine.enqueue(entry('over-capacity')), DanmuEnqueueResult.rejected);
    expect(engine.snapshot.queuedCount, 2);

    engine.configure(const Size(300, 40));
    expect(engine.snapshot.queuedCount, 2);

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'already-waiting');
    expect(engine.snapshot.queuedCount, 1);

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'accepted-while-zero');
    expect(engine.snapshot.queuedCount, 0);
  });

  test('shrinking queue limit preserves priority and FIFO order', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
        maxQueueSize: 4,
      ),
    );
    engine.configure(const Size(300, 40));
    engine.enqueue(entry('active'));
    engine.enqueue(entry('normal-1'));
    engine.enqueue(entry('normal-2'));
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
    expect(engine.snapshot.queuedCount, 4);

    engine.updateConfig(
      const DanmuConfig(
        laneCount: 1,
        laneHeight: 40,
        laneSpacing: 0,
        gap: 20,
        speed: 100,
        maxQueueSize: 2,
      ),
    );

    expect(engine.snapshot.queuedCount, 2);
    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'high-1');
    expect(engine.snapshot.queuedCount, 1);

    engine.advance(const Duration(seconds: 4));
    expect(engine.activeItems.single.entry.id, 'high-2');
    expect(engine.snapshot.queuedCount, 0);
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

  test('resize from lanes to zero and back preserves waiting work', () {
    final engine = DanmuEngine(
      const DanmuConfig(
        laneCount: 4,
        laneHeight: 40,
        laneSpacing: 0,
        maxQueueSize: 4,
      ),
    );
    engine.configure(const Size(300, 160));
    engine.enqueue(entry('lane-0'));
    engine.enqueue(entry('lane-1'));
    engine.enqueue(entry('lane-2'));
    engine.enqueue(entry('lane-3'));
    engine.enqueue(entry('waiting'));
    expect(engine.snapshot.activeCount, 4);
    expect(engine.snapshot.queuedCount, 1);

    engine.configure(const Size(300, 20));

    expect(engine.laneCount, 0);
    expect(engine.snapshot.activeCount, 0);
    expect(engine.snapshot.queuedCount, 1);
    expect(engine.needsFrame, isFalse);

    engine.configure(const Size(300, 160));

    expect(engine.snapshot.activeCount, 1);
    expect(engine.activeItems.single.entry.id, 'waiting');
    expect(engine.snapshot.queuedCount, 0);
  });

  test('clear removes active and waiting entries in every geometry state', () {
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
    engine.configure(Size.zero);
    engine.enqueue(entry('waiting-zero'));

    engine.clear();

    expect(engine.isIdle, isTrue);
    expect(engine.snapshot.activeCount, 0);
    expect(engine.snapshot.queuedCount, 0);
    expect(engine.needsFrame, isFalse);
  });
}
