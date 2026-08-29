# T119 任务切换器隐私遮罩

记录日期：2026-08-29

## 实现

`FineCoachApp` 在 `scenePhase` 为 `inactive` / `background` / unknown 时**同步**调用 `ScenePrivacyCoordinator.sceneWillResignActive()`，再在 background 里异步做 checkpoint。`RootNavigation` 在 `isCovered` 时叠一层不透明黑色 `PrivacyCover`（全屏、拦截点击）。回到 `active` 时清除。

`ScenePrivacyCoordinatorTests` 证明 resign → covered、become active → 清除，无异步间隙。

`PrivacyCoverUITests.testPrivacyCoverIsAbsentWhileActiveAndClearsAfterBackground`：

- iPhone 17 Simulator：通过（`/tmp/FineCoach-T119-UI.xcresult`）
- iPhone XS Max / iOS 18.7.10：通过（`/tmp/FineCoach-Device-UI.xcresult`，11.7 s）

进程级证明：active 时无遮罩，Home 后再 activate 仍无遮罩。这不能替代系统任务切换器截图。

## 未完成

系统任务切换器截图必须在物理设备上于进入后台后、系统快照发生时采集。本文件在截图落地前不能勾选 T119。
