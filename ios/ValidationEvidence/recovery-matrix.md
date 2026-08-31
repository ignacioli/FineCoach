# T117 恢复矩阵

记录日期：2026-08-29

## 已记录的 24 组结局

`RecoveryMatrixTests.testMatrixRecordsTwentyCombinations` 断言 ≥20 组，当前 24 行，每组 `confirmedSetLoss == 0` 且 `draftPromotedToCompleted == false`。

## 物理设备

设备：iPhone XS Max / iOS 18.7.10。

进程级（`/tmp/FineCoach-Device-UI-retry.xcresult` 等）：

- `RecoveryMatrixTests.testTerminateRelaunchKeepsCompletedAndDraft`
- `RecoveryProcessDriverTests.testTerminateAndRelaunchRestoresConfirmedSetAndKeepsDraft`

**重启（人工）**：训练中至少 1 组已确认 + 1 组未确认草稿 → 关机再开机 → 打开精练教练继续训练。操作者确认：**重启后组在、草稿未升级**。已确认组未丢，草稿未变成已完成。

未在真机上重复 20 次独立重启；20 组组合由编码矩阵覆盖，真机补了终止重开与一次重启。
