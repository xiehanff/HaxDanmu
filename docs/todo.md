# TODO

评审遗留事项，按优先级分组。已经完成的底层正确性与 API 减法不再混在待办中。

## v0.3 候选

1. **文本便捷 API** —— 宿主目前必须自己量出文本宽度才能构造 `DanmuEntry`，是当前最大的易用性硬伤。
   做法：增加文本便捷构造能力，内部通过 `TextPainter` 测量宽度，并处理文本方向、样式、缩放等影响实际宽度的输入；
   验收：demo 页发送纯文本弹幕时不再手写固定 `width: 220`。

2. **顶部 / 底部固定弹幕** —— 目前仅支持右→左滚动模式。
   做法：引入模式概念（滚动 / 顶部停驻 / 底部停驻）；停驻型需要处理驻留时长、轨道占用、到期回收与同区域不重叠；
   涉及 `DanmuEntry` 模式字段、Engine 调度与生命周期分支。

3. **`DanmuEntry.id` 的正式语义** —— 当前业务 `id` 不参与渲染 identity，也不用于去重、查找或撤回。
   做法二选一：
   - 把 `id` 改成可选，仅作为宿主业务字段；
   - 或正式提供按 id 查询 / 撤回，并定义重复 id 的行为。

## 性能与压力验证

4. **建立可重复的性能基线** —— 当前目标是十几到几十条同时在屏弹幕，不以千级并发为目标。
   建议至少覆盖：
   - 10 / 30 / 100 active entries；
   - 60Hz / 120Hz 设备；
   - `RepaintBoundary` 开 / 关对 UI frame、Raster frame、layer count 和内存的影响；
   - 长文本、复杂 Stateful child、不同 speed 混合轨道。

5. **评估高密度渲染架构** —— 只有真实 profile 证明 `Stack + Positioned` 成为瓶颈后再做。
   候选：`Flow`、自定义 `RenderBox`、Canvas / `CustomPainter` 批量绘制；
   non-goal：为了理论性能提前把当前可维护的 Widget 渲染层整体重写。

6. **补更长时序压力测试** —— 当前已经覆盖 pause/resume、zero-size、轨道变化、队列上限、State identity 等关键边界；后续只在发现真实长时运行问题后增加针对性随机序列测试，避免继续围绕理论极端扩测试矩阵。

## 展示与文档

7. README 补演示 GIF / 截图（放在特性列表附近）。
8. README 增加英文说明（可选，面向国际用户）。
9. example 页接入 `assets/icon.png`（如 AppBar leading）。
10. 如需要完整平台启动器图标，再引入图标生成流程。

## 发布 pub.dev 前

11. 增加 `dart pub publish --dry-run` 的发布前检查，并确认 LICENSE / README / CHANGELOG / example 均满足 pub.dev 展示要求。

## 已完成的评审修复与减法

- StatefulWidget 弹幕稳定 render identity；
- 0 轨道 / 0 尺寸时停止无意义 Ticker；
- active 弹幕冻结启动时有效 speed，避免运行时默认速度更新破坏防追尾；
- `DanmuHandle` stale detach 所有权保护，并将 attach/detach 内部化；
- pre-layout 与 lane-waiting 合并为一个等待队列；
- `pendingLayout` 合并为统一的 `queued` 结果；
- `maxQueueSize` 改为 admission limit，运行时缩小不再静默删除已接受消息；
- zero-size → 恢复布局时已接受 waiting entry 不再静默丢失；
- `DanmuConfig` Release 模式运行时校验；
- 主入口只导出宿主需要的公开 API，不再暴露 Engine / render identity / frame 状态；
- 删除 `HaxDanmu.background` 与 `HaxDanmu.onDisposed`；
- 删除只锁 queue trim 内部顺序和极端浮点实现细节的测试；
- `pubspec.yaml` 已填入真实仓库地址、补充检索关键词并提升到 `0.2.0`；
- CHANGELOG 已固化 `0.2.0` 版本条目；
- Flutter 最低版本与当前开发版本 CI matrix。
