# HaxDanmu

基于 Ticker 的轨道式 Flutter 弹幕组件包。`example/` 是独立演示工程，展示发送 / 暂停 / 继续 / 清空等能力。

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
  config: const DanmuConfig(
    laneCount: 4,
    laneHeight: 34,
    maxQueueSize: 80,
  ),
  showLanes: true, // 调试时显示轨道分隔线
),

// 发送一条弹幕：width 需与 child 实际渲染宽度一致
final result = handle.send(DanmuEntry(
  id: '1',
  width: 220,
  child: const Text('Hello HaxDanmu'),
));
// result: accepted（立即上轨）/ queued（等待轨道）/
//         pendingLayout（等待有效布局）/ rejected（非法或队列已满）

handle.pause(); // 暂停
handle.play();  // 继续
handle.clear(); // 清空
```

## 队列与运行时配置语义

- `maxQueueSize` 是**所有尚未上轨弹幕的总上限**：包括布局尚未可用时发送的弹幕，以及轨道繁忙时排队的弹幕；
- 组件尺寸为 0 或不足一条轨道时，不会为了等待队列持续空转 Ticker；布局恢复后会重新尝试调度；
- `DanmuConfig` 在进入 `DanmuEngine` 时会做运行时校验，NaN / Infinity / 非法速度、轨道尺寸和队列上限在 Release 构建中同样会被拒绝；
- 修改默认 `speed` 只影响之后上轨的弹幕。已经上轨的弹幕会保持启动时的有效速度，避免运行时调速破坏防追尾约束；
- 运行时缩小 `maxQueueSize` 时，会先使用新增的可用轨道，再裁剪仍在等待的队列。队列按优先级组织，裁剪从尾部开始；
- `DanmuHandle` 使用绑定所有权保护：旧组件销毁时不会误解绑后来复用同一 handle 的新组件。

## 工程结构

```text
hax_danmu/
├── lib/
│   ├── hax_danmu.dart         # 公开 API：导出 engine 与 widget
│   └── src/
│       ├── danmu_engine.dart  # 纯调度状态机：轨道分配/防追尾/队列/帧推进
│       └── danmu_widget.dart  # HaxDanmu 组件：Ticker + Flutter 渲染桥接
├── test/                      # Engine / Widget 的调度、生命周期与边界回归测试
├── example/                   # 独立演示 App（path 依赖引入组件）
│   ├── lib/main.dart
│   └── assets/icon.png
├── docs/
└── pubspec.yaml
```

## 设计要点

- **引擎与渲染分离**：`DanmuEngine` 是 `ChangeNotifier`，不依赖真实帧，可脱离 widget 直接单测；
- **单 Ticker 驱动**：不是每条弹幕一个 `AnimationController`，所有滚动弹幕由组件内一个 Ticker 推进；
- **防追尾调度**：新弹幕比前车快时会计算追上耗时与前车离屏耗时，追上更早则拒绝该轨道；
- **稳定渲染身份**：每次上轨由 Engine 生成独立 render identity，业务 `id` 重复也不会导致 StatefulWidget 串 State；
- **宿主低状态**：页面只持有 `DanmuHandle` 命令桥，组件 detach 后命令安全 no-op；
- **空闲自动停帧**：没有可移动 active item 时停止 Ticker，等待布局或轨道恢复不消耗持续帧回调。

## 性能边界

当前渲染层使用 `Stack + Positioned + RepaintBoundary`，定位目标是播放器中常见的十几到几十条并发滚动弹幕。Engine 有硬队列上限并在空闲时停 Ticker。

千级同时在屏弹幕、Canvas 批量自绘和自定义 RenderObject 暂不属于当前版本目标；如果未来把目标提升到高密度直播弹幕，应先用 profile/benchmark 验证 `Stack` relayout、layer 数量和每帧对象分配，再决定是否切换渲染架构。

## 兼容性与 CI

包声明支持 Flutter `>=3.27.0`。CI 会同时验证：

- Flutter 3.27.0：声明的最低支持版本；
- Flutter 3.44.8：项目当前开发基线。

两套环境都会分别运行 package 与 example 的 `pub get / analyze / test`。

本工程本地使用 FVM 固定 Flutter 3.44.8（见 `.fvmrc`）：

```bash
# 组件包
fvm flutter pub get
fvm flutter analyze
fvm flutter test

# 演示工程
cd example
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run
```
