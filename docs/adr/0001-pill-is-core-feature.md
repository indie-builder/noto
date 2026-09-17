# ADR-0001：屏幕边缘药丸是核心功能，重构不可移除

- 状态：Accepted（已接受）
- 日期：2026-09-18
- 决策人：项目所有者
- 关联：PR #1（重构）、PR #2（误删）、PR #3（恢复）

## 背景

2026-09-17 的全局精简行动中，PR #1 先把药丸模块重构为规范几何（canonical per-edge transform）并拆分文件；PR #2 在执行「LOC ≥ 30% 削减」时把药丸当作可删减面整体移除。项目所有者随即指出：**屏幕边缘药丸是要的核心功能，不能删掉**。PR #3 已将其完整恢复。

本 ADR 把这一结论固化为架构决策，约束后续所有重构。

## 决策

**屏幕边缘药丸（`Sources/NotoApp/Pill/`）是本产品的核心功能，长期保留。** 任何后续重构、精简、LOC 削减都必须保持其功能与质量不降级；本 ADR 只能被新的 ADR 显式取代（Superseded），不得删除或静默废弃。

### 必须保留的功能面

- 贴边凸舌：悬停展开 / 常驻 / 隐藏三种可见性（设置页可切换）。
- 「今日待办」环：逾期橙色、有待办 accent、无待办无强调环；无日期与已完成任务不计入。
- 「写一笔」：借主窗口录入框，药丸自身永不做文本输入、永不抢焦点（nonactivatingPanel + statusBar 层级）。
- 移动 / 设置两端弧线按钮；悬停元素弹出带箭头描述卡（今日 / 新建）。
- ⌥ 拖动沿边移动、拖向其他屏幕边即换边；各边位置独立记忆；右键菜单可换边 / 隐藏 / 恢复居中。
- 前台全屏应用时自动隐藏，退出全屏恢复。
- 四条屏幕边全部支持；通透（macOS 26 原生 glassEffect）与纯黑两种材质，旧系统 / 降低透明度回退纯黑。
- 设置页「屏幕边缘 / 位置 / 材质」三行控件。

### 必须遵守的架构约束（重构时）

1. **唯一的边映射**：四条边的几何一律由 `PillEdge.contentTransform(in:)` 从「右侧」规范空间映射得到；命中矩形（`PillController.rect`）、剪影（`NotchSilhouette`）、提示卡尾巴（`PillTooltipTail`）共用它。**不允许重新引入逐边 switch。**
2. **窗口 frame 恒定**：面板固定为最大展开尺寸，展开/收起只做窗口内部剪影的 SwiftUI 形变；不做窗口级 frame 动画（发抖根源）。
3. **命中在 AppKit 层**：`panel.ignoresMouseEvents` + `PillHostingView.interactiveRects` 控制穿透与命中；收起态命中区较轮廓横向外扩 10、纵向外扩 8。
4. **数据推送**：药丸不轮询数据库；`AppModel` 变化后调用 `PillModel.refresh(force:)`，内部按 dataVersion + 日期去重。

### 必须共存的资产

- `Tests/NotoAppTests/PillTests.swift`：几何、放置、悬停命中的回归测试，随功能共存。
- `THIRD-PARTY-NOTICES/codenotch.txt` 及 `scripts/build.sh` 中拷贝 `Codenotch-LICENSE.txt` 的步骤：贴边面板与剪影改编自 codenotch（MIT，© Vinz），**只要派生代码存在，归属文件就必须随包分发**。
- README 的「屏幕边缘的待办药丸」章节。

### 涉及文件清单

`Sources/NotoApp/Pill/`（PillPanel / PillEdge / PillMetrics / PillShapes / PillModel / PillController / PillViews 共 7 个文件）、`AppModel` 的 `pill` 属性与 `reload` 内的 `pill?.model.refresh()`、`ContentView.onAppear` 的面板启动、`SettingsView` 外观页、`NotoApp` 的 `--preview-pill` 组件预览分支。

## 后果

- LOC 精简类工作的度量必须把药丸及其测试视为不可削减项；削减目标只能通过其他模块或文档达成。
- 后续重构若改动几何常量或命中算法，必须先让 `PillTests` 全绿，并按本 ADR「架构约束」自查。
- 若未来确要移除或重写此功能（例如产品方向变化），必须先写新 ADR 显式取代本篇，并由项目所有者确认；不允许在常规重构 PR 中顺手删除。
