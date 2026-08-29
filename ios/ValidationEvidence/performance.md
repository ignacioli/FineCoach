# T116 性能

记录日期：2026-08-29

SC-006 暂定：恢复 P95 ≤ 1 s；动作搜索反馈 P95 ≤ 200 ms；Set 确认视觉反馈 P95 ≤ 100 ms。协议：物理基准 iPhone、Release、无 debugger、5 次 warm-up + 30 个样本。

## 测量夹具

`PerformanceSignposts` 增加 `Recovery` 与 `ExerciseSearch` 区间；`AppLifecycleCoordinator.sceneDidBecomeActive` 包裹 `reconcileOnLaunch`，`ExerciseLibraryViewModel.reload` 包裹搜索。Set 确认仍走既有 `measureSetConfirm`。

`FineCoachIntegrationTests/Performance/PerformanceMeasurementTests.swift`：5 warm-up + 30 样本，线性插值 P50/P95。

## Simulator 诊断（不是 T116 通过）

设备：iPhone 17 Simulator / iOS 26.5。配置：Debug test host。结果包：`/tmp/FineCoach-T116-Int.xcresult`。

| 指标 | P50 (ms) | P95 (ms) | 预算 |
| --- | --- | --- | --- |
| 恢复 `reconcileOnLaunch` | 2.45 | 2.87 | ≤ 1000 |
| Exercise 搜索 `"深蹲"` | 0.08 | 0.13 | ≤ 200 |
| `confirmSet` 用例 | 8.61 | 19.70 | ≤ 100 |

这些数字测量仓储/领域路径，不是 Release 无 debugger 的视觉帧，也不是物理设备。

## 物理设备 Debug 诊断（不是 T116 通过）

设备：iPhone XS Max / iOS 18.7.10。配置：Debug test host，附加 debugger。`PerformanceMeasurementTests` 含在 `/tmp/FineCoach-Device-Int.xcresult`（67/67 通过）。预算断言通过，但测量路径仍是仓储/领域，不是 Release 无 debugger 的视觉帧。

## 未完成

未在 iPhone XS Max 上以 Release、不附加 debugger 采集 5+30 样本。Debug 真机通过不能勾选 T116。
