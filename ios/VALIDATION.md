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

滑动修复后全量 UI 复跑：`/tmp/FineCoach-Device-UI-retry.xcresult`，**25/27 通过**。失败 2 条为 CoreTraining 在添加「平板支撑」后等 `StaticText`（XS Max 折叠/合并 accessibility label），不是 runner kill。

## 日常真机增量协议（宪法未要求每次全量）

宪法只禁止「用模拟器冒充真机验收」，**没有**要求每次提交在真机跑完全部 UI。规格的物理证据是 Phase 9 门（T113–T119），不是每次开发循环。

推荐：

1. 模拟器跑变更相关的 unit / integration / UI。
2. 真机只跑触及的 `-only-testing` 核心路径：学员 → 开训 → 加动作/组 → 结束 → 历史/分享或备份（约数分钟）。
3. 全量真机 UI（27 条、30–40 分钟）仅在 US 完成或 Phase 9 关门时跑一次。
4. XS Max 上避免 `app.swipeUp()`（会触发 Home）；用 `revealLowerContent()`。

## 仍未关闭

无未勾选 `tasks.md` 项。当前 gate 为 G4（M1-A 实现验收与 R1 状态更新）；通过前不得创建 M1-B spec。T115 不以 VoiceOver 人工脚本为门。

## T125 证据对照（2026-08-30）

产品负责人确认可关闭 T125 并进入 G4。不以 Apple Developer Program / TestFlight / App Store 为条件。对照 `specs/001-m1-a-core-session/spec.md`：

| 项 | 证据 |
| --- | --- |
| AC-001、AC-002 | `ValidationEvidence/us1-accessibility.md`；学员生命周期 UITests |
| AC-003、FR-013A | `ValidationEvidence/us4-exercise-library.md`（含 XS Max 动作库浏览 5/5） |
| AC-004、AC-005 | `ValidationEvidence/us2-accessibility.md`；CoreTraining UITests |
| AC-006、AC-007、SC-003 | `ValidationEvidence/us3-recovery.md`、`recovery-matrix.md` |
| AC-008–010 | `ValidationEvidence/us5-privacy.md` |
| AC-011、AC-012 | `ValidationEvidence/us6-backup.md` |
| AC-013、NFR-001、SC-005 | `ValidationEvidence/offline-core.md` |
| NFR-002、NFR-007、SC-004 | `privacy-canary.md`、`privacy-entitlements.md`、`us5-privacy.md` |
| NFR-003 | `app-switcher-privacy.md`（进程级遮罩；系统截图仍缺，T124 记为残留、不否决） |
| NFR-004、NFR-005、NFR-006、SC-007 | `accessibility.md`、`compatibility-matrix.md` |
| NFR-008 | `us5-privacy.md`、`us6-backup.md` |
| SC-001、SC-002 | `product-owner-acceptance.md` |
| SC-006 | `performance.md`、`t116-results.json` |
| 独立隐私安全 gate | `privacy-security-gate.md`（PASS WITH RESIDUALS） |
