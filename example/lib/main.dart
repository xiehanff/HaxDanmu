import 'package:flutter/material.dart';

import 'package:hax_danmu/hax_danmu.dart';

void main() => runApp(const HaxDanmuApp());

class HaxDanmuApp extends StatelessWidget {
  const HaxDanmuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HaxDanmu',
      theme: ThemeData(colorSchemeSeed: const Color(0xff2563eb)),
      home: const DanmuDemoPage(),
    );
  }
}

class DanmuDemoPage extends StatefulWidget {
  const DanmuDemoPage({super.key});

  @override
  State<DanmuDemoPage> createState() => _DanmuDemoPageState();
}

class _DanmuDemoPageState extends State<DanmuDemoPage> {
  final DanmuHandle _handle = DanmuHandle();
  int _sequence = 0;
  DanmuEnqueueResult? _lastResult;

  @override
  void initState() {
    super.initState();
    debugPrint('[demo] DanmuDemoPage initState');
  }

  @override
  void dispose() {
    debugPrint('[demo] DanmuDemoPage dispose');
    super.dispose();
  }

  DanmuEntry _entry({
    required String text,
    DanmuPriority priority = DanmuPriority.normal,
  }) {
    final id = 'demo-${++_sequence}';
    return DanmuEntry(
      id: id,
      width: 220,
      priority: priority,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: priority == DanmuPriority.high
                ? const [Color(0xfff59e0b), Color(0xffc2410c)]
                : const [Color(0xff2563eb), Color(0xff4338ca)],
          ),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                priority == DanmuPriority.high
                    ? Icons.bolt
                    : Icons.chat_bubble_outline,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _send(String text, {DanmuPriority priority = DanmuPriority.normal}) {
    final result = _handle.send(_entry(text: text, priority: priority));
    setState(() => _lastResult = result);
    debugPrint('[hax_danmu] send result=${result.name} text=$text');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('danmu-demo-page'),
      appBar: AppBar(title: const Text('HaxDanmu 弹幕演示')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '引擎用枚举表示阶段，组件内部拥有 Ticker；宿主只持有可选命令句柄。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff111827),
                borderRadius: BorderRadius.circular(20),
              ),
              child: HaxDanmu(
                handle: _handle,
                config: const DanmuConfig(
                  laneCount: 4,
                  laneHeight: 34,
                  laneSpacing: 14,
                ),
                showLanes: true,
                onDisposed: () => debugPrint(
                  '[hax_danmu] disposed label=danmu-page',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('最近一次入队：${_lastResult?.name ?? '暂无'}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _send('来自服务端的弹幕'),
                child: const Text('发送普通'),
              ),
              FilledButton.tonal(
                onPressed: () => _send(
                  '高优先级用户弹幕',
                  priority: DanmuPriority.high,
                ),
                child: const Text('发送高优先级'),
              ),
              OutlinedButton(
                onPressed: _handle.pause,
                child: const Text('暂停'),
              ),
              OutlinedButton(
                onPressed: _handle.play,
                child: const Text('继续'),
              ),
              OutlinedButton(
                onPressed: _handle.clear,
                child: const Text('清空'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
