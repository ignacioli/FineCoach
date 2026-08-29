# US5 历史、总结与训练报告隐私证据

记录日期：2026-08-28

范围：T078–T093（完成后总结、历史只读/显式编辑、allowlist 训练报告、临时文件与系统分享边界）。未启动 T094。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- DTO 仅含 `schemaVersion`、`studentDisplayName`、`sessionDateUTC`、`durationSeconds`、`trainingFocus`、`studentFacingSummary`、`trainingVolume`、`exercises`。Mirror 属性集与 `ShareReportPolicy.allowedDTOPropertyNames` 锁定一致。
- `ShareReportPolicy.forbiddenIdentifierTokens` 含 sex / injury / phone / wechat / privateCoach / actionPrivate / recipient / delivery / sent / revoked / bodyMass / bodyFat / StudentMO；这些 token 不出现在 DTO 类型名、属性名或嵌套 set DTO 标识上。
- 三类备注隔离：教练私有备注、课后可见总结、动作私有备注不进入 DTO。伤病、电话、微信、档案私有备注同样不映射。
- 训练容量默认关闭且不粘滞。预览文案与 PNG 只来自 allowlist DTO；文件名为 `report-%03d.png`，目录为不透明 `share-report-flows/{flowUUID}`。
- OSLog 仍只输出固定 `event` / `operation` / `error_category`，未新增业务字段。系统分享只记录「已交给系统分享」，文案不含「已发送」「已投递」「外部副本已撤回」。
- 完成后编辑与新报告写入在同一 PersistenceWriter 事务内将既有 current 报告标为 stale；handoff timestamp 与 freshness 正交。取消/失败不写 handed-to-system。

扫描结果：永久禁止字段在 DTO、预览行、PNG 文件名、OSLog 事件面和 UITest 可见文案上的泄漏计数为 **0**。`forbiddenIdentifierTokens` 自身及 UITest identifier `shareReport.notSentStatus` 含 token 字面量，不构成业务字段泄漏。

## Simulator 回归

设备：iPhone 17，iOS 26.5。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoachDD-US5-Unit/Logs/Test/Test-FineCoachTests-2026.08.28_19-57-59--0700.xcresult` | 47/47 通过（含 HistoryReport 4 + ShareReportPolicy 5） |
| FineCoachIntegrationTests | `/tmp/FineCoachDD-US5-Int/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_19-58-16--0700.xcresult` | 46/46 通过（含 Renderer 7 + TempReport 5） |
| FineCoachUITests（HistoryShare） | `/tmp/FineCoachDD-US5-UI4/Logs/Test/Test-FineCoachUITests-2026.08.28_20-43-03--0700.xcresult` | 5/5 通过（AC-008/009/010） |

UI 覆盖：结束训练进入总结并分离三类备注；跳过分享回到学员详情/历史；显式编辑后报告已过期且无撤回/已发送声明；预览默认关闭训练容量且不含电话/微信/伤病/私有备注；取消/失败保留预览与重试；完成只记录已交给系统分享；Accessibility XL 下跳过/生成/历史仍可点且 ≥44×44。

`swift-format lint --strict` 已在本轮 iOS 源码上执行通过。

## 实体设备

未在本轮执行。计划设备仍为 iPhone XS Max（iPhone11,6），iOS 18.7.10，id `00008020-000C5D2C3ED3002E`。Simulator 回归不是 Data Protection 专项证据。

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未启动 T094 或任何 User Story 6 任务。
