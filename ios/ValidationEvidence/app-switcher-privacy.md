# T119 任务切换器隐私遮罩

记录日期：2026-08-29

## 实现

`FineCoachApp` 在 `scenePhase` 为 `inactive` / `background` / unknown 时**同步**调用 `ScenePrivacyCoordinator.sceneWillResignActive()`，再在 background 里异步做 checkpoint。`RootNavigation` 在 `isCovered` 时叠一层不透明黑色 `PrivacyCover`。回到 `active` 时清除。

`ScenePrivacyCoordinatorTests`：resign → covered、become active → 清除。

`PrivacyCoverUITests`：Simulator 与 iPhone XS Max 进程级通过（active 无遮罩，Home 后再 activate 仍无遮罩）。

## 物理设备系统任务切换器

设备：iPhone XS Max / iOS 18.7.10。飞行模式验证之后，Coach 打开进行中/已有训练页，从底部上滑并停住打开 App 切换器。

**精练教练卡片为全黑**，未见学员名、动作名或组数。回到 App 后内容正常。本仓库未另存 PNG（观察由操作者当场确认）。

## 残留

未把切换器 PNG 检入 `ValidationEvidence/`。若需要可归档的像素证据，请补一张系统截图。
