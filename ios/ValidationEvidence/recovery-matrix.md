# T117 恢复矩阵

记录日期：2026-08-29

## 已记录的 24 组结局

`RecoveryMatrixTests.testMatrixRecordsTwentyCombinations` 断言 ≥20 组，当前 24 行，每组 `confirmedSetLoss == 0` 且 `draftPromotedToCompleted == false`。背景行在注释中标明为元数据（Simulator home 键不稳定）；18–24 行对应 T053 投影语义。

## Simulator 进程级

T112 FineCoachUITests：

- `testTerminateRelaunchKeepsCompletedAndDraft`
- `testRelaunchEmptySessionStaysAbandonable`
- `RecoveryProcessDriverTests.testTerminateAndRelaunchRestoresConfirmedSetAndKeepsDraft`

均通过。这覆盖 terminate/relaunch，不覆盖后台与设备重启。

## 物理设备进程级（不是 T117 通过）

设备：iPhone XS Max / iOS 18.7.10。结果包：`/tmp/FineCoach-Device-UI.xcresult`。

通过：

- `RecoveryMatrixTests.testTerminateRelaunchKeepsCompletedAndDraft`
- `RecoveryProcessDriverTests.testTerminateAndRelaunchRestoresConfirmedSetAndKeepsDraft`
- `testMatrixRecordsTwentyCombinations`

`RecoveryMatrixTests.testRelaunchEmptySessionStaysAbandonable` 记为 `Test crashed with signal kill`（runner 被杀，未完成断言）。Backup/CoreTraining 等套件同样被杀，见 `ios/VALIDATION.md`。

未执行设备重启组合。terminate/relaunch 真机通过不能勾选 T117。
