# T124 独立隐私安全 gate

记录日期：2026-08-29

审查：[隐私审查](b16e8934-a9bb-49ad-9a5c-771ecfddadfe)（只读）。输入：`main` `ad81b08` 及当时未提交的 PrivacyInfo / UITest / 证据文件。

**结论：PASS WITH RESIDUALS。T124 可勾选。** 未发现已确认的 Critical / High 泄漏。本 gate **不是** TestFlight、Archive 隐私报告或 App Store Connect 豁免。

M1-A：一台设备上的一名 Coach 操作员；Student 是记录，不是 App 用户。

## 残留（不否决本 gate）

1. `LaunchArgumentSharePresenter` 在 Release 也会读 `-FineCoachSimulateShare*`；备份 UI 钩子已 `#if DEBUG`，分享 presenter 未对齐。零售安装上 Coach 碰不到这些参数。
2. 备份流程中 `exclusive-lease.json` 与 `staging.fcbackup` 写入后未立刻走 `ProtectedFileStore.apply`；父目录已按 `.business` 准备。窗口短，明文不落盘。
3. 系统任务切换器截图仍缺（T119）。进程级遮罩已有真机 UITest，不能把泄漏数记为已证明的 0。
4. Apple Developer Program / TestFlight / App Store 上架已从 M1-A 门移除。本审查不作加密豁免。
5. 失窃未锁设备、弱备份口令、Coach 在允许字段里手打敏感字、交接后系统副本，均在故障模型之外。

## 已核对

| 面 | 结果 |
| --- | --- |
| 持久化 DP / 排除备份 | T118 真机 9/9；WAL/SHM `completeUnlessOpen` |
| 恢复快照 / pointer / intent | `atomicReplace` + fail-closed |
| 备份容器 | FCBK、PBKDF2 600k、AES-GCM；文件名无学员词 |
| 报告 DTO 白名单 | 无 sex/injury/phone 等标识；PNG `report-%03d.png` |
| Entitlements | 空字典；无网络 / CloudKit / 遥测 |
| PrivacyInfo | DiskSpace **E174.1** 对应写入前空间检查 |
| 任务切换器遮罩 | 同步 `isCovered`；缺系统截图 |
| 日志 | 仅固定枚举；无业务字段 |
| Release fault-injection | T114 `nm` 无注入符号；本轮未重编 Release |

## 不因此勾选

T125 G4。T121 / T122 不再作为 M1-A 门。
