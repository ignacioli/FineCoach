# US3 恢复与保存状态证据

记录日期：2026-08-28

范围：T052–T065（中断后恢复且不误报保存）。未启动 T066。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- 保存顺序：Domain 下一聚合 + 递增 revision → 原子替换 `active-session-recovery-v1.json` → 同一 writer Core Data save。
- snapshot 成功且数据库失败时保留较新 snapshot，`saveStatus` 为 `failed(retryable: true)`，不得报告已保存，不得完成 Session；`retry()` 投影失败期间完整当前聚合。
- 启动：generation 必须匹配 pointer + store + snapshot；snapshot revision > DB 则重放；相等则一致；更旧则忽略；损坏/错代次 fail-closed 并隔离。
- 计时：非负 UTC 增量并入 elapsed；负跳变或单次中断 ≥30 分钟设 `durationNeedsReview`；不自动放弃、不改 Set 完成语义；结束前需确认时长。
- 保存状态：`SaveStatusView` 持续显示 保存中/已保存/保存失败，失败时提供「重试保存」并禁止完成。
- 生命周期：启动 `reconcileOnLaunch`；进入 `.background` 时 checkpoint 并记录中断起点。`.inactive` 只盖隐私遮罩，不写 checkpoint（避免键盘触发误写）。

## Simulator 回归

设备：iPhone 17，iOS 26.5。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoachDD-US3-Unit/Logs/Test/Test-FineCoachTests-2026.08.28_07-24-57--0700.xcresult` | 27/27 通过（含 US3 codec 6 + timing 6） |
| FineCoachIntegrationTests | `/tmp/FineCoachDD-US3-Int/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_07-25-13--0700.xcresult` | 27/27 通过（含 US3 投影 6；US2 ActiveSession 6 回归） |
| FineCoachUITests | `/tmp/FineCoachDD-US3-UI2/Logs/Test/Test-FineCoachUITests-2026.08.28_07-37-59--0700.xcresult` | 14/14 通过（US1 4 + US2 CoreTraining 4 + smoke 1 + US3 driver 2 + matrix 3） |

恢复覆盖：

- Codec：完整聚合 round-trip（completed/pending/draft、顺序、备注）；revision 比较重放/一致/忽略旧快照；generation mismatch 与损坏 JSON fail-closed。
- 投影：snapshot replace 失败阻断且不标已保存；writer save 失败保留较新 snapshot 并可 retry；失败期间后续命令后一次 retry 投影完整聚合；未解决失败禁止 finish；损坏/错代次启动 fail-closed；更高 revision 重启重放。
- 计时：UTC checkpoint、负跳变复核、≥30 分钟复核、24h 异常时钟不自动失败；复核后可完成。
- 进程：终止后 relaunch 同一 store（不带 `-FineCoachResetStore`）保留已确认 0×5 深蹲，草稿不升级为 completed；空 Session 仍可放弃。矩阵记录 ≥20 组 terminate/background × 内容/保存状态组合，`confirmedSetLoss == 0` 且 `draftPromotedToCompleted == false`。

`swift-format lint --strict` 已在本轮 US3 相关源码上执行通过。

## 实体设备

未在本轮对 US3 做实体设备回归。US1 设备证据见 `ios/ValidationEvidence/us1-accessibility.md`。契约要求的物理设备中断/Data Protection 证据仍为独立门。

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未覆盖设备丢失或全部可写介质同时失效。
- 未启动 T066 或任何 User Story 4 任务。
