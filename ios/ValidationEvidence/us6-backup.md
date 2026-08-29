# US6 备份与恢复证据

记录日期：2026-08-28

范围：T094–T111（`FineCoachBackup v1` 容器、口令、typed inventory 往返、intent/pointer 崩溃恢复、导出/恢复 UI）。未启动 T112+ Polish。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- 容器 magic 为 `FCBK`，header 固定 82 bytes 大端字段；`containerVersion` / `payloadSchemaVersion` / `minimumReaderVersion` / `kdfID` / `aeadID` 均为 1；`iterations` 严格 600000；未知版本/算法/迭代次数 fail closed，且不会为未知 iterations 派生密钥。
- 明文 payload 为 typed frames（`sectionID | length | RFC 8785 JCS UTF-8`），强制 manifest；不转储 SQLite/Core Data store。AES-256-GCM 分块（nonce = `noncePrefix[8] || chunkIndex:u32`，AAD = header || index || length || finalFlag）。
- 导出在 flow 目录写入不透明 `FineCoach-Backup-<UUID>.fcbackup` 后再复制到系统选择的目标；不产生完整明文 staging 文件。错误口令与篡改映射为 `authenticationFailed`，current generation 不变。
- `FileFlowLease` 只含 flow ID / kind / phase / 相对路径 / byte budget；janitor 冷启动删除不被 current pointer 与 restore intent 引用的 orphan generation/flow，且不触碰 App 根目录之外的用户副本。恢复后若恰有一个 `inProgress` Session 则重建 singleton `ActiveSessionPointer`。
- UI 可见文案为简体中文；口令提示含「不可恢复/无法找回」且不提 Keychain；导出成功不为「已发送」；恢复警告含「完整替换」并建议先备份。DEBUG 启动参数仅用于 Simulator UI 闸门。

独立 decoder：`BackupGoldenVectorTests` 用固定 salt/口令核对 PBKDF2-HMAC-SHA256 与 82-byte header 往返；JCS 按 RFC 8785 UTF-16 code unit 排序。

## Simulator 回归

设备：iPhone 17，iOS 26.5。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoachDD-US6-ReviewUnitAll/Logs/Test/Test-FineCoachTests-2026.08.28_23-35-41--0700.xcresult` | 69/69 通过（含 BackupGoldenVector 7 + BackupHostileInput 15） |
| FineCoachIntegrationTests | `/tmp/FineCoachDD-US6-ReviewIntAll2/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_23-45-18--0700.xcresult` | 66/66 通过（含 RoundTrip 7 + RestoreCrashRecovery 10 + RestoreFaultMatrix 3） |
| FineCoachUITests（BackupRestore） | `/tmp/FineCoachDD-US6-ReviewUI2/Logs/Test/Test-FineCoachUITests-2026.08.28_23-45-50--0700.xcresult` | 3/3 通过 |

`swift-format lint --strict` 已在 mobile-code-reviewer 修复后再次执行通过。本轮修复后的回归覆盖系统文件导出器、恢复文件选择、进程内 live stack 重绑、启动 verify-or-rollback、header-first 有界复制和 exclusive `FileFlowLease`。DEBUG 启动参数仍用于 UI 闸门。

## 实体设备

未在本轮执行。计划设备仍为 iPhone XS Max（iPhone11,6），iOS 18.7.10，id `00008020-000C5D2C3ED3002E`。Simulator 回归不是 Data Protection 或真实系统文件选择器证据。

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未对真实 Files/Share Sheet 交接做物理设备验收。
- 未启动 T112 及之后的 Polish 任务。
