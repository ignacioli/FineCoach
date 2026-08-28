# US2 无障碍与 UI 回归证据

记录日期：2026-08-28

范围：T037–T051（课堂中快速记录并完成 Session）。未启动 T052。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- VoiceOver：动作卡片组合为「显示名称, 记录模式」，选中时带 selected trait；记录模式芯片有独立 label 与 selected trait；组行（`FCSetRow`）组合 title/数值/状态文字，图标对 VoiceOver 隐藏；统计、空 Session 提示、完成状态均有可访问标识。
- 触控目标：添加动作、结束训练、添加组、确认、模式芯片、侧别芯片、上移/下移/删除动作均为 `minHeight: 44`；`FCSetRow` 与 `FCButton` / `FCTextField` 保持 44 pt 下限。
- Dynamic Type：Active Session、Set 编辑、结束/删除确认均在 `ScrollView` 中；`scrollDismissesKeyboard(.interactively)` 避免键盘挡住录入。
- Reduce Motion：本切片未加入自定义动画或 transition；系统 Reduce Motion 不会被自定义动效覆盖。
- 简体中文：`session.*` 文案写入 `Localizable.xcstrings`。UI 测试以 `-AppleLanguages (zh-Hans)` 启动。
- 性能 signposts（T050）：`SetConfirm`、`SessionFinish`、`ExerciseReorder` 使用固定非敏感名称，不包含 Student/动作内容。

## Simulator 回归

设备：iPhone 17，iOS 26.5。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoachDD-US2-Unit/Logs/Test/Test-FineCoachTests-2026.08.28_06-33-19--0700.xcresult` | 15/15 通过（含 US1 8 + US2 domain 6 + smoke 1） |
| FineCoachIntegrationTests | `/tmp/FineCoachDD-US2-Int/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_06-33-32--0700.xcresult` | 21/21 通过（Foundation 9 + Student 6 + ActiveSession 6） |
| FineCoachUITests | `/tmp/FineCoachDD-US2-UI/Logs/Test/Test-FineCoachUITests-2026.08.28_06-33-52--0700.xcresult` | 9/9 通过（含 US1 4 + US2 CoreTraining 4 + smoke 1） |

UI 覆盖：

- 开始训练：重量×次数（含重量 0）、仅次数、时长、左右侧；复制上一组保持 pending 且不计入完成统计。
- 离开后从列表「训练中」横幅继续；动作上移/下移；删除含 completed 组需确认；撤销 completed → pending。
- 空 Session 结束必须放弃确认；未完成草稿阻断完成，需丢弃或返回处理。
- `UICTContentSizeCategoryAccessibilityXL` 下「添加动作」与「结束训练」仍可点且 ≥44 pt。
- US1 回归：首次说明、搜索/归档/恢复/确认删除、进行中阻断永久删除、AccessibilityXL 列表仍通过。

`swift-format lint --strict` 已在本轮源码上执行通过。

## 实体设备

未在本轮对 US2 做实体设备回归。US1 设备证据见 `ios/ValidationEvidence/us1-accessibility.md`。

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未启动 T052 或任何 User Story 3 任务。
