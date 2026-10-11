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

G4 已于 2026-08-30 通过。R1 已实现并验收。下一步唯一允许：创建 M1-B `spec.md`（尚未开始）。T115 不以 VoiceOver 人工脚本为门。

## T125 证据对照（2026-08-30）

产品负责人确认可关闭 T125。同日宣布 **G4 通过**；R1 已实现并验收。不以 Apple Developer Program / TestFlight / App Store 为条件。对照 `specs/001-m1-a-core-session/spec.md`：

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

## M1-B Phase 8 证据对照（2026-09-30，T051）

会话分支 `claude/finecoach-m1b-phase8-ecf1d1`，输入提交 `7a7b5a5`（Phase 8 收尾，2026-10-03）。Simulator：iPhone 17 Pro Max，iOS 26.5，Debug。**模拟器结果是工程回归，不是物理设备验收。**

自动化门（最后一次）：`xcodebuild build` 通过；`FineCoachTests` 267 项（1 项按设计跳过）0 失败；`FineCoachIntegrationTests` 96/96；设计值扫描 0 违规。

| 需求 | 证据 | 证明什么 / 不证明什么 |
| --- | --- | --- |
| NFR-005、M1B-FR-009、AC-015 | `FCStatusTests`（5 类状态各有文字与图标、各自登记的显示文件都用 `FCStatusLabel`） | 状态不只靠颜色；显示位置为静态登记。界面待人工审核 |
| NFR-002、NFR-007 | `CapabilityManifestTests`（Info.plist、entitlements、隐私清单、工程文件、源码无网络/通讯录/相册/相机/定位/遥测） | 只证明声明与静态引用，不证明运行时 |
| NFR-002 | `LogSurfaceTests`（日志只有固定枚举标识；`AppLogger` 之外只有 T116 harness 写控制台） | 不是统一日志的运行时抓取 |
| NFR-003 | `PrivacyCoverTests` + `ScenePrivacyCoordinatorTests` + 已有 `PrivacyCoverUITests`；系统模态内容加了同一个遮罩 | 遮罩存在与接线；**App 切换器实际截图未验证**（沿用 M1-A `app-switcher-privacy.md` 的残留） |
| NFR-004 | `TouchTargetComponentTests`（交互组件都声明 ≥44pt 点击区） | 组件层保证；页面渲染与大字号截断由 T070、人工审核覆盖，**没有整页 XCUITest** |
| AC-013、NFR-001（T049） | `CapabilityManifestTests`：无网络框架、无 `URLSession`/`NWConnection`、无第三方包；M1-A 飞行模式审计 `ValidationEvidence/offline-core.md` | M1-B 未新增联网代码；**没有重新做飞行模式实测**（模拟器无法切飞行模式） |
| T052 独立隐私/安全审查 | `mobile-privacy-security-reviewer`，PASS WITH FINDINGS | 见下表处置 |

### T052 发现处置

| 发现 | 处置 |
| --- | --- |
| (1) 分享模拟启动参数正式版可用 | 已修：`#if DEBUG` |
| (2) `T116PerformanceHarness` 正式版可用 | **登记例外（产品负责人 2026-09-30）**：只写合成数据到独立存储，只能由启动参数触发，安装版无法传参 |
| (3) 备份口令留在 ViewModel 内存 | 已修：导出成功、取消、离开页面、恢复成功时清空 |
| (4) 导出临时副本未走 `ProtectedFileStore` | **登记为可接受（产品负责人 2026-09-30）**：文件本身已用口令加密，用后即删 |
| 系统模态遮罩 | 已修：结束/删除训练、归档学员、新建指标三处加遮罩；系统文件选择器无法覆盖，登记为已知限制 |

### 已知缺口与遗留（如实记录）

- 未验证：锁屏通知文字、系统分享实际投递、真机文件保护、App 切换器实际截图、正式版二进制。
- 出口合规：`Info.plist` 未设 `ITSAppUsesNonExemptEncryption`。产品负责人计划订阅 Apple Developer；上传 TestFlight 前由产品负责人在 App Store Connect 决定「使用加密 / 是否豁免」，再用一行写入 `Info.plist`。
- 旧界面测试：`StudentLifecycleUITests` 因 App 启动落在「今日」、空状态按钮标识被盖住而失败，已修复 2 项（首次启动、大字号）；另 2 项（归档/永久删除）因 D6 把入口移到编辑资料页而过期，已标记跳过，T081 登记重写。界面测试不在验收门内。
- 屏幕根容器标识覆盖子控件标识的问题已修（21 处）。
- 物理设备验收：产品负责人 2026-10-03 决定 M1-B **不做**；上述未验证项作为已知缺口保留。G6 于同日通过。

## M2 个人训练档案：系统模态遮罩（T050，2026-10-11）

- 查看模式没有 `.sheet` / `.fullScreenCover` 模态，唯一的页内浮层是 `fcBottomSheet`（M2-12 筛选、M2-15 选动作），在根部遮罩之下，无需另加遮罩；`ArchiveViewerScreenTests` 禁止 `Features/ArchiveViewer` 出现 `.sheet(` / `.fullScreenCover(`。
- M2-08 导入页用的系统文件选择器无法覆盖遮罩，沿用 M1-B 已登记的同一已知限制。

## M2 独立隐私与安全审查（T066，2026-10-11）

只读审查 `git diff 3dc41a3..4c352cc -- ios/`。无严重 / 高风险问题。

| 发现 | 处置 |
|---|---|
| 中：`Documents/Inbox` 中的加密档案副本只在 App 内正常退出时删除（进程被杀、打开 `.fcbackup`、冷启动连开两次都会残留） | 已修：启动时清扫 Inbox（保留正在处理的文件），忽略的文件立即删除，被覆盖的待处理文件删除；同一 Inbox 路径守卫，测试证明不碰 Inbox 外文件 |
| 低：本机档案指针无法读取时被当成「未选择」，首次导入会覆盖它 | 已修：Coach 数据为空且指针存在但无法读取时，安装状态解析抛错（关闭失败），导入返回 `installStateUnavailable`，指针与数据逐字节不变 |
| 低：`snapshot.bin` 明文先写入、后加文件保护和备份排除 | 已修：创建文件时即带保护等级，写入前先设备份排除，原有的事后读回检查保留 |
| 信息：分区名称随训练记录导出，但预览未列出 | 产品负责人 2026-10-11 决定：M2-03 预览列出「分区名称」，spec M2-FR-008 已补 |
| 信息：密码与派生密钥无法在 Swift `String` / `Data` 中可靠清零；`snapshot.bin` 为明文 JSON（与 Coach 存储同一保护等级）；离线猜测只受密码强度限制（PBKDF2 60 万次、最少 8 位） | 登记为残留风险，不修 |
| 信息：删除时后续步骤失败，界面仍显示内存中的档案 | 可重试完成；下次启动 janitor 清理。登记，不修 |

**只能在真机 / 正式环境确认（留给 T070）**：文件保护等级与备份排除的真机读回；`Documents/Inbox` 是否进入 iCloud / 设备备份；文件选择器或分享面板打开时 App 切换器截图；系统是否提示保存档案密码（D-12）；64 MiB 上限档案导入时的内存。
