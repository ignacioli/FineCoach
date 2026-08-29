# T115 无障碍与兼容性（修订后口径）

记录日期：2026-08-29

2026-08-29 产品决定：取消 SE / 第二条 iOS 26 物理通道；不以 VoiceOver 人工脚本为验收。已有 `accessibilityIdentifier` / `accessibilityLabel` 保留，不新增旁白功能。

## 代码门槛

部署目标 iOS 18.0。仓库内无 `#available(iOS 26…)`、`glassEffect`、Liquid Glass、SwiftData。实现使用稳定 SwiftUI 语义与 `minHeight`/`minWidth` 44。

Accessibility XL UITests（Simulator T112 通过；真机滑动修复后 Backup XL 等已跑通）：

- `StudentLifecycleUITests.testOnboardingAndListRemainUsableWithAccessibilityContentSize`
- `CoreTrainingUITests.testTrainingFlowRemainsUsableWithAccessibilityContentSize`
- `HistoryShareUITests.testHistoryShareControlsRemainAccessibleAtXL`
- `BackupRestoreUITests.testBackupControlsAccessibleAtXL`

## 物理设备

iPhone XS Max / iOS 18.7.10，竖屏、简体中文、浅色。操作者指示记录：**人工操作，列表 VoiceOver 正常**（旁白导致锁屏卡住后，本里程碑不再重开旁白，且不再作为门）。

## 通过条件（修订后）

- Dynamic Type XL 自动化 + 44pt + 文字/图标：满足
- 无 iOS 26-only API：源码审计通过
- 不要求 SE、不要求第二台 iOS 26 真机、不以 VoiceOver 脚本为门
