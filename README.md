# HaxDanmu

基于 Ticker 的轨道式 Flutter 弹幕组件包。`example/` 是独立的演示工程,展示发送 / 暂停 / 继续 / 清空等能力。

## 安装

```yaml
dependencies:
  hax_danmu:
    path: ../            # 或 git 依赖 / pub.dev 版本号
```

## 快速开始

```dart
final handle = DanmuHandle();

// 作为覆盖层放进任意布局（例如叠在播放器上）
HaxDanmu(
  handle: handle,
  config: const DanmuConfig(laneCount: 4, laneHeight: 34),
  showLanes: true, // 调试时显示轨道分隔线
),

// 发送一条弹幕：width 需与 child 实际渲染宽度一致
final result = handle.send(DanmuEntry(
  id: '1',
  width: 220,
  child: const Text('Hello HaxDanmu'),
));
// result: accepted（上车）/ queued（排队）/ pendingLayout / rejected

handle.pause(); // 暂停
handle.play();  // 继续
handle.clear(); // 清空
```

## 工程结构

```
hax_danmu/
├── lib/
│   ├── hax_danmu.dart         # 公开 API：导出 engine 与 widget
│   └── src/
│       ├── danmu_engine.dart  # 纯调度状态机：轨道分配/防追尾/队列/帧推进
│       └── danmu_widget.dart  # HaxDanmu 组件：只拥有 Ticker，其余交给引擎
├── test/                      # 引擎 9 个单测 + 组件轨道 overlay 测试
├── example/                   # 独立演示 App（path 依赖引入组件）
│   ├── lib/main.dart
│   └── assets/icon.png
├── docs/
└── pubspec.yaml
```

## 设计要点

- **引擎与渲染分离**：`DanmuEngine` 是 `ChangeNotifier`，不依赖真实帧，可脱离 widget 直接单测；
- **防追尾调度**：新弹幕比前车快时会计算追上耗时与前车离屏耗时，追上更早则拒绝该轨道；
- **宿主零状态**：页面只持有 `DanmuHandle` 命令桥，组件 detach 后所有命令安全 no-op；
- **空闲自动停 Ticker**：无活跃弹幕时停止帧推进，保持 playing 相位，下次 send 免重启。

## 运行

本工程使用 fvm 固定 Flutter 3.44.8（见 `.fvmrc`）：

```bash
# 组件包：静态分析与测试
fvm flutter pub get
fvm flutter analyze
fvm flutter test

# 演示工程：独立解析，可单独运行
cd example
fvm flutter pub get
fvm flutter run
```
