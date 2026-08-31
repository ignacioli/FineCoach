# T114 隐私 / Entitlements / 依赖 / 符号审计

记录日期：2026-08-29

输入提交：`f79b8fff4afee467c60a6ae61cb54927fcc03cdd`

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

Release 构建：`/tmp/FineCoachDD-T114-AppRelease/Build/Products/Release-iphoneos/FineCoach.app/FineCoach`

## 1. Targets

| Target | Product type |
| --- | --- |
| FineCoach | application |
| FineCoachTests | unit-test |
| FineCoachIntegrationTests | unit-test |
| FineCoachUITests | ui-testing |

无 share / notification / widget / watch appex。

## 2. Entitlements

`ios/FineCoachApp/FineCoach.entitlements` 是仓库内唯一 entitlements 文件，字典为空。Debug 与 Release 均设置 `CODE_SIGN_ENTITLEMENTS = FineCoachApp/FineCoach.entitlements`。

不存在 iCloud/CloudKit、push、associated domains、App Groups、network client/server、HealthKit 等 capability。

## 3. PrivacyInfo.xcprivacy

`NSPrivacyTracking` = false；collected data types 与 tracking domains 为空。备份路径使用磁盘空间查询（`volumeAvailableCapacityForImportantUsage` / `.systemFreeSize`），`PrivacyInfo.xcprivacy` 已声明 DiskSpace `E174.1`。TestFlight / Archive 隐私报告不是 M1-A 门。

## 4. Info.plist

`FineCoach-Info.plist` 仅声明 `com.finecoach.backup` / `.fcbackup`。无 URL scheme、background modes、ATS 例外、相机/麦克风/通讯录/健康 usage description。

部署：iOS 18.0，`TARGETED_DEVICE_FAMILY = 1`，`CFBundleDisplayName` = 精练教练，`developmentRegion` = zh-Hans。

## 5. 依赖

无 `Package.swift`、CocoaPods、Carthage、SPM remote package。App 链接 Foundation、SwiftUI、CoreData、Security、UIKit、OSLog、Combine；另经 Swift 导入 CryptoKit、CommonCrypto、UniformTypeIdentifiers。本地加密仅用于 `FineCoachBackup v1`。

## 6. 源码扫描

`ios/FineCoachApp` 中无 `URLSession`、`NWConnection`、`CKContainer`、CloudKit、Firebase、Sentry、Crashlytics、Mixpanel、MetricKit、WebSocket。账号/服务器客户端不存在。

系统分享与文件选择器是 Coach 主动发起的系统边界，不是 App 网络客户端。`AppLogger` 只记录固定枚举 token。`PerformanceSignposts` 是本机 `OSSignposter`。

## 7. Fault injection

`FaultInjectionBoundary.swift` 与 `TestFaultInjector.swift` 整体 `#if DEBUG`。Release 配置不设置 `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`。

## 8. Release 二进制

```sh
APP=/tmp/FineCoachDD-T114-AppRelease/Build/Products/Release-iphoneos/FineCoach.app/FineCoach
nm -j "$APP" | rg 'FaultInjection|FaultInjector|persistenceWriterSave|generationMetadataWrite|currentPointerReplace|recoverySnapshotReplace|TestFaultInjector'
nm -j "$APP" | rg -i 'URLSession|NWConnection|CKContainer|CloudKit|Firebase|Sentry|Crashlytics|Mixpanel|MetricKit|Telemetry|Analytics|WebSocket'
strings "$APP" | rg 'FaultInjectionPoint|FaultInjectionError|FaultInjectionBoundary|TestFaultInjector'
otool -L "$APP"
```

上述 `nm` / `strings` 匹配均为空。`otool -L` 仅为 Apple 系统库（Foundation、SwiftUI、CoreData、Security、UIKit、OSLog、Combine、CoreFoundation、CoreGraphics、CryptoKit 及 Swift 运行时）。

## 9. 结论

T114 源码、工程与当前 Release 二进制扫描通过：无账号/服务器/CloudKit/遥测/远程日志/远程崩溃 SDK，Release 不含 fault-injection。本地 PrivacyInfo / entitlements 已覆盖。Apple Developer Program、TestFlight、App Store 上架不是 M1-A 门；不得自行声称加密豁免。
