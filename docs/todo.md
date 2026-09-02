# TODO

评审遗留事项,按优先级分组。

## 关键缺口(v0.2 目标)

1. **文本便捷 API** —— 宿主目前必须自己用 `TextPainter` 量出宽度才能构造 `DanmuEntry`,是最大的易用性硬伤。
   做法:增加 `DanmuEntry.text('...', style: ...)` 工厂,内部自动测宽并自动生成 `id`;
   验收:demo 页改用 `text()` 发送纯文本弹幕,不再手写 `width: 220`。

2. **顶部/底部固定弹幕** —— 目前仅支持右→左滚动模式,弹幕库的基本盘缺一角。
   做法:引入模式概念(滚动/顶部停驻/底部停驻),停驻型需处理驻留时长与同轨不重叠;
   涉及 `DanmuEntry` 增加模式字段、`DanmuEngine` 轨道分配与离屏判定分支。

3. **`DanmuEntry.id` 处置** —— 必填但引擎从未使用(不去重、不查找)。
   做法:随条目 1 的 `text()` 工厂自动生成,同时把构造函数的 `id` 改为可选;
   或者用起来(去重 / 撤回单条)。

## 次要建议

4. **`DanmuHandle` 重复 attach 防护** —— 同一 handle 被 attach 到第二个组件时会静默覆盖前者,前者失去控制。
   做法:`attach()` 加 debug assert:已绑定未 detach 时立即报错。

5. **性能声明与压力测试** —— 现实现每帧重建 `Positioned` 触发 Stack relayout,几十条并发没问题,千级弹幕不在目标内。
   做法:README 声明「千级弹幕 / Canvas 自绘渲染」为 non-goal;补一条高并发 widget 压测。

6. **时序 widget 测试** —— 组件测试目前只覆盖轨道 overlay。
   做法:补一条「发送 → 按 `width / speed` 推进时长 → 断言离屏与轨道回收」的完整生命周期测试。

## 上传 GitHub 后

7. README 补演示 GIF / 截图(放在特性列表旁)。
8. README 增加英文段落(可选,面向国际用户)。
9. example 页接入 `assets/icon.png`(如 AppBar leading);widget 测试中需用 `errorBuilder` 或注入 TestAssetBundle 规避资源加载失败。
10. 用图标生成各平台启动器图标(`flutter_launcher_icons`);如需 1024px 源图,可从原 icns 的 `ic10` 块重新抽取。

## 发布 pub.dev 前

11. 填写 pubspec 中 homepage / repository / issue_tracker 的占位 URL(当前为 YOUR_USERNAME)。
12. description 补关键词(danmaku / barrage / bullet comments)。
