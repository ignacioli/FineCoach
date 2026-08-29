# T115 无障碍

记录日期：2026-08-29

## 代码门槛

部署目标 iOS 18.0。仓库内无 `#available(iOS 26…)`、`glassEffect`、Liquid Glass、SwiftData。实现使用稳定 SwiftUI 语义与 `minHeight`/`minWidth` 44。

已有 Accessibility XL UITests：

- `StudentLifecycleUITests.testOnboardingAndListRemainUsableWithAccessibilityContentSize`
- `CoreTrainingUITests.testTrainingFlowRemainsUsableWithAccessibilityContentSize`
- `HistoryShareUITests.testHistoryShareControlsRemainAccessibleAtXL`
- `BackupRestoreUITests.testBackupControlsAccessibleAtXL`

US1 曾在 iPhone XS Max 上跑过 Student XL 用例（见 `us1-accessibility.md`）。本轮 Simulator T112 再次通过上述 XL 用例。

## 物理设备（一条通道，不是 T115 通过）

iPhone XS Max / iOS 18.7.10，竖屏。`StudentLifecycleUITests.testOnboardingAndListRemainUsableWithAccessibilityContentSize` 通过（`/tmp/FineCoach-Device-UI.xcresult`）。CoreTraining / HistoryShare / BackupRestore 的 XL 用例在同一次 UI 跑次中为 `Test crashed with signal kill`，未完成断言。

## 未完成

- 未做人工 VoiceOver 朗读走查。
- 未覆盖 iPhone SE (2nd generation) / 最新 iOS 18.x 物理通道。
- 未覆盖较新 iPhone / iOS 26.x 物理通道（仅有 Simulator iOS 26.5）。
- 逻辑焦点顺序与最大 Dynamic Type 文本截断/重排未在两条物理通道记录。

严重/关键问题：自动化 XL 套件在 Simulator 未发现阻塞；人工 VO 未执行，不能将严重问题数记为已证明的 0。
