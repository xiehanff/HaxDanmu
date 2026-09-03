import 'package:flutter_test/flutter_test.dart';

import 'package:hax_danmu_example/main.dart';

void main() {
  testWidgets('danmu demo page sends and renders an entry', (tester) async {
    await tester.pumpWidget(const HaxDanmuApp());

    expect(find.text('最近一次发送：暂无'), findsOneWidget);

    await tester.tap(find.text('发送普通'));
    await tester.pump();

    expect(find.text('最近一次发送：accepted'), findsOneWidget);
    expect(find.text('来自服务端的弹幕'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();

    expect(find.text('来自服务端的弹幕'), findsNothing);
  });
}
