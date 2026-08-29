# T118 Data Protection 与备份排除

记录日期：2026-08-29

## 策略

`ProtectedFileStore`：业务与 backup candidate = `completeUnlessOpen`；临时报告 = `complete`。写入后回读保护级别与 `isExcludedFromBackup`。Simulator 不强制保护级别回读，只强制排除备份。物理设备上 `assertProtectionRawValue` 与期望值相等。

## 自动化

`FoundationIntegrationTests`：

- SQLite + WAL + SHM 存在，策略 `completeUnlessOpen`，排除备份
- 报告原子替换后 `complete` 且排除备份
- candidate `completeUnlessOpen` 且排除备份
- generation pointer / metadata 排除备份

备份恢复：`RestoreCrashRecoveryTests.testAttributeResetReappliesBackupExclusionOnKeptGenerations`（current/old/new generation、current pointer、restore intent 排除备份）；报告：`TempReportLifecycleTests.testWrittenReportFilesAreExcludedFromBackup`。

## 物理设备（iOS 18.7.10）

设备：iPhone XS Max `00008020-000C5D2C3ED3002E`。核验开发者证书后重跑。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FoundationIntegrationTests | `/tmp/FineCoach-T118-Device.xcresult` | 9/9 通过 |
| FineCoachIntegrationTests（含 RestoreCrashRecovery / TempReport） | `/tmp/FineCoach-Device-Int.xcresult` | 67/67 通过 |

物理设备上强制断言的保护类：

- SQLite / WAL / SHM：`NSFileProtectionCompleteUnlessOpen`，排除备份
- 业务目录与 backup candidate：`completeUnlessOpen`，排除备份
- 临时报告文件：`NSFileProtectionComplete`，排除备份
- generation pointer / metadata：排除备份（同 Foundation 用例）
- restore 保留 generation / intent / pointer：排除备份（RestoreCrashRecoveryTests）

T024 曾在同一台 XS Max（当时 iOS 18.7.9）上 9/9 通过。本轮在 18.7.10 刷新了上述回读。
