# TestFlight 外部测试：核实结论与决策清单（草稿）

> 日期：2026-11-02。基于 `main` @ `5d565d5`（worktree 分支 `topic/busy-franklin-e68ecd`）。
> 范围：只做核实和准备，没有改产品代码、工程配置或签名。
> 标「待核实」的是 Apple 平台政策，提交前要对照最新官方文档。

## 1. 网络调用核实

结论：App 和小组件里没有发起网络请求的代码，也没有第三方 SDK。按代码事实，App 隐私问卷可以如实填「不收集数据」（Data Not Collected）。

依据：

- 在 `ios/FineCoachApp`、`ios/FineCoachWidgets` 的全部 `.swift` 中搜索 `URLSession`、`URLRequest`、`NWConnection`、`Network` 框架、`WKWebView`、`SFSafariViewController`、`CloudKit`、`NSPersistentCloudKitContainer`、`StoreKit`、`AdSupport`、`AppTrackingTransparency`、常见分析/崩溃 SDK 名：均无命中。
- 全部 `import` 只有 Apple 框架：Foundation、SwiftUI、CoreData、UIKit、Combine、WidgetKit、UniformTypeIdentifiers、os/OSLog、CryptoKit、ActivityKit、UserNotifications、Darwin、Charts、Security、CoreText、CommonCrypto、AppIntents。
- 工程没有 Swift Package、CocoaPods 或 Carthage 依赖：`project.pbxproj` 里没有 `XCRemoteSwiftPackageReference`，仓库里没有 `Package.swift`、`Podfile`、`Cartfile`。链接的框架只有系统框架（`project.pbxproj:170-177`）。
- 出现 `URL(string:)` 的地方都不是网络请求：
  - `Features/Settings/SettingsView.swift:9,44`：「源代码」行用系统 `openURL` 在浏览器打开 GitHub 仓库，由用户点击触发，App 本身不发请求。
  - `Features/ArchiveViewer/ArchiveViewerPresentation.swift:93` / `ArchiveAboutView.swift:60`：用系统浏览器打开 Creative Commons 许可页。
  - `Core/Platform/NotificationAdapter.swift:122`：打开系统设置。
  - `Core/Domain/SessionActivityContent.swift:66`、`FineCoachWidgets/TodayWidget.swift:8`：`finecoach://` 本地深链。
- `Data(contentsOf:)` 只读本地文件（存储代际指针、归档快照、备份暂存、动作目录等）。
- 通知只用本地触发器 `UNTimeIntervalNotificationTrigger`（`NotificationAdapter.swift:104`），没有 `registerForRemoteNotifications`，两个 entitlements 里也没有 `aps-environment`。
- 文件离开设备只有一种途径：用户主动通过系统分享面板或「存储到文件」交出（`Core/Platform/SystemShareAdapter.swift:43-104`）。开发者收不到这些文件。
- `PrivacyInfo.xcprivacy` 已声明 `NSPrivacyCollectedDataTypes` 为空、`NSPrivacyTracking = false`，只声明了磁盘空间 API（`E174.1`）。

要注意的点：

- 学员资料包含身体数据和伤病备注，属于健康相关信息，但都只存在本机，也没有使用 HealthKit。问卷按「不收集」填写的前提是「收集」指传到开发者或第三方；这个定义是 Apple 的，提交前按最新文档核实（待核实）。

## 2. 签名、Bundle ID、App Group、版本号

### Team

`DEVELOPMENT_TEAM = 9Z7427RG9X`，所有 target 都是自动签名（`project.pbxproj:2747,2750` 等）。

本机 Xcode 偏好 `com.apple.dt.Xcode` → `IDEProvisioningTeamByIdentifier` 里，这个 Team 记录为 `teamType = "Personal Team"`、`isFreeProvisioningTeam = 1`。**结论：`9Z7427RG9X` 是免费的 Personal Team，不能上传 TestFlight。** 这次核实只读本机配置文件，没有登录 Apple 账号。

### Bundle ID 与 App Group

| Target | Bundle ID | App Group | MARKETING_VERSION | CURRENT_PROJECT_VERSION | 依据 |
|---|---|---|---|---|---|
| FineCoach（App） | `com.finecoach.app` | `group.com.finecoach.app` | 0.2.0 | 1 | `project.pbxproj:2748,2758,2759`（Debug）、`2772,2782,2783`（Release）；`FineCoachApp/FineCoach.entitlements` |
| FineCoachWidgets（小组件 + Live Activity） | `com.finecoach.app.widgets` | `group.com.finecoach.app` | 0.2.0 | 1 | `project.pbxproj:2871,2878,2879`（Debug）、`2893,2900,2901`（Release）；`FineCoachWidgets/FineCoachWidgets.entitlements` |
| FineCoachTests | `com.finecoach.app.tests` | — | — | — | `project.pbxproj:2795,2808`（不上传） |
| FineCoachIntegrationTests | `com.finecoach.app.integration-tests` | — | — | — | `project.pbxproj:2820,2833`（不上传） |
| FineCoachUITests | `com.finecoach.app.ui-tests` | — | — | — | `project.pbxproj:2845,2858`（不上传） |

其他上传相关事实：

- `IPHONEOS_DEPLOYMENT_TARGET = 18.0`，`TARGETED_DEVICE_FAMILY = 1`（只支持 iPhone，`project.pbxproj:2724`）。
- 显示名 `精练教练`，分类 `public.app-category.sports`，开发语言 `zh-Hans`（`project.pbxproj:2753-2755`）。
- AppIcon 有 1024×1024 的浅色、深色、着色三版（`AppIcon.appiconset/Contents.json`）。
- `FineCoach-Info.plist` 和生成的 Info.plist 键里**没有** `ITSAppUsesNonExemptEncryption`。按硬约束，本轮不添加。
- `FineCoach-Info.plist` 里 `com.finecoach.backup` 同时出现在 `UTExportedTypeDeclarations` 和 `UTImportedTypeDeclarations`。这不影响本轮，列为后续观察项；上传校验是否告警，待第一次归档时确认。

## 3. 动作库署名

### provenance.json 的实际构成

`ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json`（`contentVersion = m1a.catalog.2026-10-18`）共 542 条：

| 来源（`sourceIdentifier` 前缀） | 许可（`licenseIdentifier` 原值） | 条数 |
|---|---|---|
| `free-exercise-db` | `Unlicense` | 310 |
| `wger.de` | `CC-BY-SA 4` 74 + `CC-BY-SA-4.0` 73 | 147 |
| `wger.de` | `CC-BY-SA-3.0` 64 + `CC-BY-SA 3` 4 | 68 |
| `wger.de` | `CC0-1.0` 9 + `CC0` 2 | 11 |
| `finecoach-built` | `MIT` | 6 |

交接文档 §1 写的「542 条来自 wger.de，CC-BY-SA-3.0」与实际不符。README 第 103 行的说法和上表一致。另外，wger 的作者字段（`authorOrOwner`）里有 488 条不是 `wger.de`，而是 wger 上的具体贡献者用户名。

### App 内现状

- **学员视图「关于本档案」**（`Features/ArchiveViewer/ArchiveAboutView.swift:33-69`）：只有导入的档案包含内置动作时才显示「动作资料来源」。来源名取 `sourceIdentifier` 前缀，比如 `free-exercise-db, finecoach-built, wger.de`；许可名把档案里出现的许可去重后列出（`Core/Domain/Archive/ArchiveExportPolicy.swift:234-259`），只有 BY-SA 许可才显示 creativecommons.org 链接（`ArchiveViewerPresentation.swift:96-98`）。
- **教练视图「设置 → 关于」**（`Features/Settings/SettingsView.swift:32-38`）：一行 `.informational`，只显示「版本 x（build）」，不可点，**没有 wger、free-exercise-db 或 FineCoach 自建条目的署名，也没有许可证说明**。教练视图的动作库页面也没有引用 provenance 的地方（`Features/` 下没有读取 `licenseIdentifier` 或 `attributionRequirement` 的代码）。

结论：交接文档要求「关于页 C21 有 wger 署名和许可证说明」，**教练端目前不满足**。教练端是主要使用场景，动作中文名和肌群也在教练端展示。是否以及怎样补上，写进了下面的决策 D6。这是产品行为改动，本轮没有做。

附带观察：同一许可在原始数据里有两种写法（`CC-BY-SA 4` / `CC-BY-SA-4.0`，`CC0` / `CC0-1.0`，`CC-BY-SA 3` / `CC-BY-SA-3.0`）。`licenseDisplayName` 只替换连字符和空格，不会合并它们，所以学员视图的署名里可能同时出现两种写法。

## 4. 出口合规相关事实（只陈述事实，不做结论）

- `.fcbackup`（备份）和 `.fcarchive`（个人训练档案）都用用户设置的密码加密：
  - 密钥派生：PBKDF2-HMAC-SHA256，用 CommonCrypto 的 `CCKeyDerivationPBKDF`（`Core/Backup/BackupCrypto.swift:79-104`）。
  - 加密：AES-GCM，用 CryptoKit（`BackupCrypto.swift:44-74`）。
  - 备份调用在 `Core/Backup/BackupImporter.swift:15,53,65`，档案调用在 `Core/Archive/ArchiveFileCodec.swift:201-205,332,498`。
- 另外有两处只用 `SHA256` 做标识派生，不做加密：`ArchiveIdentityService.swift:68`、`ArchiveComparisonAdapter.swift:43`。
- App 没有任何网络传输，所以加密只保护落在文件里的用户数据。
- 工程里没有 `ITSAppUsesNonExemptEncryption`，所以每次上传后，App Store Connect 都会问这个问题。

## 5. 需要负责人决定的事项

每项都要负责人明确拍板，并把决定记录在仓库里（比如在本文件或 `AGENTS.md` 的决策区追加日期和结论），之后才能执行。

### D1. 加入付费 Apple Developer Program，确定用哪个 Team

> **负责人决定（2026-11-02）**：以个人身份加入（选项 A）。负责人完成注册后，把新 Team ID 填入所有 target 的 `DEVELOPMENT_TEAM`，同步更新 AGENTS.md 中关于 Personal Team 的段落。

- 事实：现在的 `9Z7427RG9X` 是 Personal Team，不能用于 TestFlight 或 App Store。
- 选项 A：以个人身份加入（每年 99 美元，价格待核实）。商店卖家名显示个人法律姓名。
  - 后果：会得到一个新的 Team ID，所有 target 的 `DEVELOPMENT_TEAM` 都要改（`project.pbxproj` 里 5 个 target × 2 个配置），这是对 pbxproj 的一次串行改动。
- 选项 B：以组织身份加入。需要 D-U-N-S 编号，审核周期更长（待核实）。卖家名显示组织名。
- 两种都会影响：AGENTS.md 把「Personal Team 本机签名」定为可接受的安装方式，这段要同步更新。

### D2. Bundle ID 被占用时是否改名

> **负责人决定（2026-11-02）**：先尝试注册原 ID（`com.finecoach.app`、`com.finecoach.app.widgets`、`group.com.finecoach.app`）。只有被占用时，才整套改成 `com.ignacioli.finecoach`、`com.ignacioli.finecoach.widgets`、`group.com.ignacioli.finecoach`。

- 事实：`com.finecoach.app`、`com.finecoach.app.widgets`、`group.com.finecoach.app` 还没在任何付费 Team 下注册。Bundle ID 全局唯一，Personal Team 下的自动签名记录可能也占着这个 ID（待核实：加入付费计划后能否在新 Team 下注册同名 ID）。
- 如果被占用，要改的地方：
  1. 两个 target 的 `PRODUCT_BUNDLE_IDENTIFIER`，小组件必须以 App 的 ID 为前缀。
  2. 两个 `.entitlements` 里的 App Group。
  3. 代码里唯一写死的 App Group 字符串：`Core/Platform/SharedContainer.swift:5`。
  4. 测试 target 的 ID（可选）。
- App Group 只用来存小组件快照 `widget-today.json`（`SharedContainer.swift:6-14`，读写方是 `WidgetSnapshotReader.swift:5`、`WidgetSnapshotPublisher.swift:29`），主存储不在 App Group 容器里。所以单改 App Group 不会丢学员数据，只是小组件要等 App 下次写快照后才有内容。
- 风险：如果改的是 App 的 Bundle ID，系统会把它当成另一个 App。TestFlight 版本和本机签名版本 Bundle ID 一样时会互相覆盖安装（覆盖时数据是否保留，待核实）；改名后两者可以并存，但数据不互通，只能用「备份与恢复」迁移。

### D3. 出口合规怎么回答

> **负责人决定（2026-11-02）**：首次上传时，在 App Store Connect 的问卷里如实选择「使用加密」，并按 §4 的事实回答（暂按选项 A）。问卷的结论由负责人记录到本文件之后，才在 Info.plist 中写入对应的键。在此之前，不设置 `ITSAppUsesNonExemptEncryption`，也不声称豁免。

- 事实见 §4。按硬约束，本轮**不设置** `ITSAppUsesNonExemptEncryption`，也**不声称豁免**。
- 选项 A：每次上传后在 App Store Connect 里手动回答，暂不写进 Info.plist。
  - 后果：每个 build 都要人工回答一次，回答内容由负责人决定。
- 选项 B：负责人根据 Apple 最新的出口合规文档和 BIS 规定确定分类后，把结论写进仓库，再在 Info.plist 里设置对应的值。
  - 后果：上传不再询问。但如果分类错了，责任在开发者。是否需要提交年度自分类报告或 CCATS，取决于分类结果（待核实）。
- 不管选哪种，都要由负责人对照官方文档判断 §4 里「用户密码加密本地文件、无网络传输」属于哪一类。本文件不下结论。

### D4. 隐私政策放在哪里

> **负责人决定（2026-11-02）**：用 GitHub Pages（选项 B），先发布中文版。开启 Pages 属于仓库设置改动，由负责人操作或另行授权。

- 草稿：`docs/distribution/privacy-policy.zh.md`。
- 选项 A：仓库内 Markdown，用 GitHub 文件页链接当 URL。最省事。
  - 后果：URL 依赖仓库保持公开，改路径或分支会让链接失效。
- 选项 B：GitHub Pages（例如 `ignacioli.github.io/FineCoach/privacy`）。URL 更稳定，看起来更正式。
  - 后果：要开 Pages 和维护一个分支或目录，属于仓库设置改动。
- 选项 C：独立域名。目前不需要。
- 还要决定：要不要同时提供英文版。审核员可能看不懂中文，但 App 只有 zh-Hans。

### D5. Build 号规则

> **负责人决定（2026-11-02）**：采用整数递增（选项 A），App 和小组件两个 target 同步加 1，每次上传都记入 CHANGELOG。含 D6/D7 的首个 TestFlight 版本用 `MARKETING_VERSION = 0.3.0`。

- 事实：两个 target 的 `CURRENT_PROJECT_VERSION` 都是 `1`，`MARKETING_VERSION` 都是 `0.2.0`。同一个 `MARKETING_VERSION` 下，每次上传的 build 号必须严格递增；App 和小组件的版本号必须一致（待核实最新要求）。
- 选项 A：整数递增（1、2、3…），每次上传前手动改两个 target 的 `CURRENT_PROJECT_VERSION`。
  - 后果：简单。但每次都要改 pbxproj，要记得两个 target 一起改。
- 选项 B：日期型，例如 `20261102.1`。
  - 后果：自带时间信息，不容易撞号。
- 选项 C：用 `git rev-list --count HEAD`，在归档脚本里注入。
  - 后果：不用手改 pbxproj，但要写一个归档脚本，合并方式也会影响计数。
- 还要决定：TestFlight 版本是否继续用 `0.2.0`，还是从 `0.2.1` 或 `0.3.0` 开始，并在 CHANGELOG 中记录。

### D6. 教练端补动作库署名（新增，来自 §3）

> **负责人决定（2026-11-02）**：尽快做，在 TestFlight 外部测试之前完成（即选项 A），和 D7 一起推进。

- 事实：教练端「设置 → 关于」没有任何第三方署名。CC-BY-SA 要求在分发时注明来源和许可。通过 TestFlight 或 App Store 分发，App 本身就是分发载体。
- 选项 A：在 TestFlight 外部测试之前补上。把「关于」改成可点进的页面，列出 free-exercise-db（Unlicense）、wger（CC-BY-SA 3.0/4.0、CC0，附贡献者说明和许可链接）、FineCoach 自建（MIT），以及字体 OFL。
  - 后果：这是 UI 改动，要走 `components.md` 的组件流程，也要同步更新 Penpot。
- 选项 B：先上外部测试，正式上架前再补。
  - 后果：外部测试期间许可义务没有完全满足，有被审核员或权利人指出的风险。
- 还要决定：中文译名属于「改编」，是否要在署名里说明（CC-BY-SA 对改编作品的要求，待核实）。

### D7. 审核员怎样体验学员视图（新增，来自审核备注）

> **负责人决定（2026-11-02）**：采用选项 B，准备完全虚构的演示档案，和 D6 一起推进。

- 事实：首次启动时二选一，两种方式互斥（`archive.firstLaunch.note`「两种方式互斥，之后不能直接切换。」）。选择学员视图要导入一个 `.fcarchive`，还要输入密码。只有一台设备的审核员，自己没法生成档案再导入。
- 选项 A：在审核备注里说明学员视图需要教练导出的档案，审核只走教练视图。
  - 后果：可能被要求补充演示材料，审核轮次增加。
- 选项 B：准备一个**完全虚构**的演示档案（虚构学员、虚构训练），把文件放在审核附件或公开链接里，密码写进审核备注。
  - 后果：要专门生成一份不含任何真实学员数据的档案，生成过程要可复现。

### D8. 是否在中国大陆 App Store 上架（新增，正式上架阶段）

- 事实：从 2023 年 9 月起，Apple 要求在中国大陆 App Store 上架的新 App 提供 ICP 备案号（据媒体报道，以 Apple 当前文档为准，待核实）。按报道，备案需要中国大陆注册的公司，或者与本地发行方合作。
- 这一条只影响正式上架，TestFlight 外部测试是否受影响，待核实。
- 选项 A：先上架中国大陆以外的地区。
- 选项 B：办 ICP 备案后再上架中国大陆。

### D9. 是否支持英文（新增，待定）

- 事实：`Localizable.xcstrings` 只有 zh-Hans，共 951 个 key；`AppShortcuts.xcstrings` 有 3 个 key。
- 支持英文不是上架的前提条件。

## 6. 本轮产出

- `docs/distribution/testflight-readiness.md`（本文件）
- `docs/distribution/privacy-policy.zh.md`（隐私政策草稿）
- `docs/distribution/app-review-notes.md`（审核备注草稿）

三份草稿已由负责人审阅通过（2026-11-02）。隐私政策的生效日期和联系方式，以及审核备注第 4 节（演示档案的链接和密码），等 D4 的 GitHub Pages 开通后再补。
