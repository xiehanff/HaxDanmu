import 'package:flutter_test/flutter_test.dart';

import 'package:hax_danmu_example/main.dart';

void main() {
  testWidgets('danmu demo page sends and renders an entry', (tester) async {
    await tester.pumpWidget(const HaxDanmuApp());

    // Nothing sent yet: the enqueue result label shows the placeholder.
    expect(find.text('最近一次入队：暂无'), findsOneWidget);

    // Sending places the entry on a lane immediately.
    await tester.tap(find.text('发送普通'));
    await tester.pump();

    expect(find.text('最近一次入队：accepted'), findsOneWidget);
    expect(find.text('来自服务端的弹幕'), findsOneWidget);

    // Clear removes every active entry from the viewport.
    await tester.tap(find.text('清空'));
    await tester.pump();

    expect(find.text('来自服务端的弹幕'), findsNothing);
  });
}
