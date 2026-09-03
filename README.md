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

HaxDanmu(
  handle: handle,
  config: const DanmuConfig(
    laneCount: 4,
    laneHeight: 34,
    maxQueueSize: 80,
  ),
  showLanes: true, // 调试时显示轨道分隔线
),

// width 需与 child 的实际渲染宽度一致。
final result = handle.send(DanmuEntry(
  id: '1',
  width: 220,
  child: const Text('Hello HaxDanmu'),
));
// result: accepted（立即上轨）/ queued（已接收，等待布局或轨道）/
//         rejected（非法或等待队列已满）

handle.pause();
handle.play();
handle.clear();
```

## 队列与运行时配置语义

- `maxQueueSize` 是尚未上轨弹幕的**入队上限**；布局尚未可用和轨道繁忙都使用同一个等待队列；
- 运行时降低 `maxQueueSize` **不会删除已经接受的弹幕**；当现有等待数量高于新上限时，新发送会暂时返回 `rejected`，直到队列自然下降；
- 高优先级弹幕在所有等待弹幕中排在普通优先级之前，同一优先级保持 FIFO；
- 组件尺寸为 0 或不足一条轨道时，不会为了等待队列持续空转 Ticker；布局恢复后重新调度；
- `DanmuConfig` 在进入内部调度引擎时会做 Release-safe 运行时校验，NaN / Infinity / 非法速度、轨道尺寸和队列上限会被拒绝；
- 修改默认 `speed` 只影响之后上轨的弹幕，已经上轨的弹幕保持启动时的有效速度，避免运行时调速破坏防追尾约束；
- `DanmuHandle` 只暴露 `send / play / pause / clear`，组件绑定与解绑属于内部生命周期实现。

## 公开 API

主入口 `package:hax_danmu/hax_danmu.dart` 只暴露宿主真正需要的类型：

```text
HaxDanmu
DanmuHandle
DanmuConfig
DanmuEntry
DanmuPriority
DanmuEnqueueResult
```

轨道调度状态、render identity、Ticker 判定等属于实现细节，不作为主入口 API 契约。

## 工程结构

```text
hax_danmu/
├── lib/
│   ├── hax_danmu.dart         # 精简公开 API
│   └── src/
│       ├── danmu_engine.dart  # 内部调度：轨道分配 / 防追尾 / 队列 / 帧推进
│       └── danmu_widget.dart  # HaxDanmu + Handle + Ticker / Flutter 渲染桥接
├── test/                      # 调度与公开行为回归测试
├── example/                   # 独立演示 App
├── docs/
└── pubspec.yaml
```

## 设计要点

- **引擎与渲染分离**：内部调度逻辑可以脱离真实帧单测，但不要求普通用户理解或持有 Engine；
- **单 Ticker 驱动**：不是每条弹幕一个 `AnimationController`，所有滚动弹幕由组件内一个 Ticker 推进；
- **防追尾调度**：新弹幕比前车快时会计算追上耗时与前车离屏耗时，追上更早则不使用该轨道；
- **稳定渲染身份**：每次上轨使用内部独立 render identity，业务 `id` 重复也不会导致 StatefulWidget 串 State；
- **宿主低状态**：页面只需要持有可选 `DanmuHandle`；
- **空闲自动停帧**：没有可移动 active item 时停止 Ticker，等待布局或轨道恢复不消耗持续帧回调。

## 性能边界

当前渲染层使用 `Stack + Positioned + RepaintBoundary`，定位目标是播放器中常见的十几到几十条并发滚动弹幕。

千级同时在屏弹幕、Canvas 批量自绘和自定义 RenderObject 暂不属于当前版本目标；如果未来提升到高密度直播弹幕，应先用 profile / benchmark 验证 `Stack` relayout、layer 数量和每帧对象分配，再决定是否切换渲染架构。

## 兼容性与 CI

包声明支持 Flutter `>=3.27.0`。CI 同时验证：

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
