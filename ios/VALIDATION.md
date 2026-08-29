# M1-A 验证命令与结果（T112）

记录日期：2026-08-29

输入提交：`f79b8fff4afee467c60a6ae61cb54927fcc03cdd`（本轮 Polish 工作区另有未提交源码与证据文件）

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

Simulator：iPhone 17，iOS 26.5，id `EFE2D5A0-4877-4682-BE79-7460C0C1E8C8`。

物理设备（已连接，本文件未作为 T112 通过条件）：iPhone XS Max（显示名 iPhone），iOS 18.7.10，id `00008020-000C5D2C3ED3002E`。

配置：Debug test schemes，除非另注。Simulator 结果是工程回归，不是物理设备验收。

## 可重放命令

从仓库根目录执行。

```sh
# Unit
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachTests \
  -destination 'platform=iOS Simulator,id=EFE2D5A0-4877-4682-BE79-7460C0C1E8C8' \
  -derivedDataPath /tmp/FineCoachDD-T112-Unit \
  -resultBundlePath /tmp/FineCoach-T112-Unit.xcresult

# Integration
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachIntegrationTests \
  -destination 'platform=iOS Simulator,id=EFE2D5A0-4877-4682-BE79-7460C0C1E8C8' \
  -derivedDataPath /tmp/FineCoachDD-T112-Int \
  -resultBundlePath /tmp/FineCoach-T112-Int.xcresult

# UI
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachUITests \
  -destination 'platform=iOS Simulator,id=EFE2D5A0-4877-4682-BE79-7460C0C1E8C8' \
  -derivedDataPath /tmp/FineCoachDD-T112-UI \
  -resultBundlePath /tmp/FineCoach-T112-UI.xcresult

# Format
xcrun swift-format lint --configuration .swift-format --recursive --parallel --strict \
  ios/FineCoachApp ios/FineCoachTests ios/FineCoachIntegrationTests ios/FineCoachUITests ios/TestSupport
```

## 首次全量（US1–US6 基线，未含本轮 Polish 新增测试）

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoach-T112-Unit.xcresult` | 69/69 通过 |
| FineCoachIntegrationTests | `/tmp/FineCoach-T112-Int.xcresult` | 66/66 通过 |
| FineCoachUITests | `/tmp/FineCoach-T112-UI.xcresult` | 25/26 通过；失败 1 |

失败：`CoreTrainingUITests.testEmptySessionAbandonAndDraftFinishGate`。丢弃草稿并完成后，US5 导航到 `sessionSummary.root`，测试只等 `activeSession.completedStatus` / 学员详情。这是测试断言未跟随 US5 结束态，不是完成丢失。

修复：断言接受 `sessionSummary.root`。复跑：

```sh
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachUITests \
  -destination 'platform=iOS Simulator,id=EFE2D5A0-4877-4682-BE79-7460C0C1E8C8' \
  -only-testing:FineCoachUITests/CoreTrainingUITests/testEmptySessionAbandonAndDraftFinishGate \
  -derivedDataPath /tmp/FineCoachDD-T112-UI-fix \
  -resultBundlePath /tmp/FineCoach-T112-UI-fix.xcresult
```

结果：`/tmp/FineCoach-T112-UI-fix.xcresult`，该用例通过。

## Polish 增量后的 unit 回归

`BackupHostileInputTests` 曾因 `project.pbxproj` 丢失 `B251` PBXBuildFile 而未编入。已恢复 `B251`。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests（含 ScenePrivacyCoordinator + HostileInput） | `/tmp/FineCoach-T112-Unit3.xcresult` | 70/70 通过 |
| PrivacyCoverUITests | `/tmp/FineCoach-T119-UI.xcresult` | 1/1 通过 |
| PerformanceMeasurementTests | `/tmp/FineCoach-T116-Int.xcresult` | 1/1 通过（Simulator 诊断） |

## 静态门槛

- Release iphoneos App：`/tmp/FineCoachDD-T114-AppRelease`（Polish 源码后重编），`CODE_SIGNING_ALLOWED=NO`，**BUILD SUCCEEDED**。
- `nm` / `strings` 未发现 fault-injection 或 URLSession/CloudKit/Firebase/Sentry 等符号。`otool -L` 仅为 Apple 系统框架。详见 `ValidationEvidence/privacy-entitlements.md`。
- `swift-format lint --strict` 在本轮源码上通过。

## 物理设备（iPhone XS Max / iOS 18.7.10）

设备：`00008020-000C5D2C3ED3002E`。Team `9Z7427RG9X`，Automatic Signing。首次启动被 iOS PPQ 拦截（`Developer App Certificate is not trusted`）；在「设置 → 通用 → VPN 与设备管理」完成在线核验后启动成功。

```sh
# Integration（含 Foundation Data Protection 回读与 PerformanceMeasurementTests）
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachIntegrationTests \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates \
  -derivedDataPath /tmp/FineCoachDD-T118-Device \
  -resultBundlePath /tmp/FineCoach-Device-Int.xcresult

# Unit（FineCoachTests 未写 DEVELOPMENT_TEAM，命令行补齐）
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachTests \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=9Z7427RG9X CODE_SIGN_STYLE=Automatic \
  -derivedDataPath /tmp/FineCoachDD-Device-Unit \
  -resultBundlePath /tmp/FineCoach-Device-Unit.xcresult

# UI
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachUITests \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates \
  -derivedDataPath /tmp/FineCoachDD-Device-UI \
  -resultBundlePath /tmp/FineCoach-Device-UI.xcresult
```

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| 启动 `com.finecoach.app` | — | 核验后 `devicectl process launch` 成功 |
| FoundationIntegrationTests | `/tmp/FineCoach-T118-Device.xcresult` | 9/9 通过（设备上强制 DP 回读） |
| FineCoachIntegrationTests | `/tmp/FineCoach-Device-Int.xcresult` | 67/67 通过 |
| FineCoachTests | `/tmp/FineCoach-Device-Unit.xcresult` | 70/70 通过 |
| FineCoachUITests | `/tmp/FineCoach-Device-UI.xcresult` | 10 通过 / 17 失败 |

UI 失败 17 条全部为 `Test crashed with signal kill`（XCTest runner 在 Backup/CoreTraining/Exercise/History 等套件启动时被杀，用例未完成断言）。通过的包括 `PrivacyCoverUITests`、`StudentLifecycleUITests`（4）、`RecoveryMatrixTests.testTerminateRelaunchKeepsCompletedAndDraft`、`RecoveryProcessDriverTests`、`testMatrixRecordsTwentyCombinations`、`SetupSmoke`。不是 Simulator 已覆盖的断言回归。

## 仍未关闭的物理门

T113 飞行模式、T115 双物理通道 VoiceOver、T116 Release 无 debugger 样本、T117 重启矩阵、T119 系统任务切换器截图。T118 设备 DP 回读见 `ValidationEvidence/file-protection.md`。
