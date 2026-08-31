# T116 性能

记录日期：2026-08-30

SC-006 暂定：恢复 P95 ≤ 1 s；动作搜索反馈 P95 ≤ 200 ms；Set 确认视觉反馈 P95 ≤ 100 ms。协议：物理基准 iPhone、Release、无 debugger、5 次 warm-up + 30 个样本。

## 测量夹具

`PerformanceSignposts` 区间：`Recovery`（`reconcileOnLaunch`，与 `AppLifecycleCoordinator.sceneDidBecomeActive` 相同）、`ExerciseSearch`（`ExerciseLibraryUseCases.search`，与动作库 reload 相同）、`SetConfirm`（`confirmSet`，与课中确认相同）。

Release 无 debugger 入口：`T116PerformanceHarness`，启动参数 `-FineCoachT116Harness`。使用隔离目录 `FineCoachT116`，不碰 Coach 生产库。5 次 warm-up 后 30 个样本，线性插值 P50/P95。

`FineCoachIntegrationTests/Performance/PerformanceMeasurementTests.swift` 仍为 Debug 仓储诊断夹具，不能单独勾选 T116。

## Simulator 诊断（不是 T116 通过）

设备：iPhone 17 Simulator / iOS 26.5。配置：Debug test host。结果包：`/tmp/FineCoach-T116-Int.xcresult`。

| 指标 | P50 (ms) | P95 (ms) | 预算 |
| --- | --- | --- | --- |
| 恢复 `reconcileOnLaunch` | 2.45 | 2.87 | ≤ 1000 |
| Exercise 搜索 `"深蹲"` | 0.08 | 0.13 | ≤ 200 |
| `confirmSet` 用例 | 8.61 | 19.70 | ≤ 100 |

## 物理设备 Debug 诊断（不是 T116 通过）

设备：iPhone XS Max / iOS 18.7.10。配置：Debug test host，附加 debugger。`PerformanceMeasurementTests` 含在 `/tmp/FineCoach-Device-Int.xcresult`（67/67 通过）。预算断言通过，但测量路径仍是仓储/领域，且附加了 debugger。

## 物理设备 Release、无 debugger（T116）

日期：2026-08-30。工具链：Xcode 26.6（17F113）。设备：iPhone XS Max（`iPhone11,6`），iOS 18.7.10（22H374），UDID `00008020-000C5D2C3ED3002E`。屏幕解锁。配置：Release-iphoneos，Personal Team `9Z7427RG9X`。启动：`devicectl device process launch`，`startStopped: false`，未附加 LLDB。

HEAD：`256876c07d99440d0c8923eeccb11bc865bb1871`（工作区含未提交的 T120 catalog 与本 harness）。

```sh
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoach -configuration Release \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates -derivedDataPath /tmp/FineCoachDD-T116 \
  DEVELOPMENT_TEAM=9Z7427RG9X CODE_SIGN_STYLE=Automatic build

xcrun devicectl device install app --device 00008020-000C5D2C3ED3002E \
  /tmp/FineCoachDD-T116/Build/Products/Release-iphoneos/FineCoach.app

xcrun devicectl device process launch --terminate-existing \
  --device 00008020-000C5D2C3ED3002E --json-output ios/ValidationEvidence/t116-launch.json \
  com.finecoach.app -FineCoachT116Harness

xcrun devicectl device copy from --device 00008020-000C5D2C3ED3002E \
  --domain-type appDataContainer --domain-identifier com.finecoach.app \
  --source "Library/Application Support/FineCoachT116/t116-results.json" \
  --destination ios/ValidationEvidence/t116-results.json
```

原始样本：`ios/ValidationEvidence/t116-results.json`。启动记录：`ios/ValidationEvidence/t116-launch.json`（`startStopped: false`）。

| 指标 | P50 (ms) | P95 (ms) | 预算 | 结果 |
| --- | --- | --- | --- | --- |
| 恢复 `reconcileOnLaunch` | 9.64 | 10.01 | ≤ 1000 | 通过 |
| Exercise 搜索 `"深蹲"`（146 条文字库） | 2.20 | 2.26 | ≤ 200 | 通过 |
| `confirmSet`（signpost 包住确认到会话状态写回） | 13.94 | 17.21 | ≤ 100 | 通过 |

这三项测量的是生产 signpost 包住的恢复/搜索/确认路径，到 SwiftUI 可发布的会话状态为止，不是 Core Animation 帧时间。Set 确认预算按「命令到可见确认」的应用层完成来验收；下一帧绘制通常另加 ≤16 ms，仍低于 100 ms。

T116 通过。
