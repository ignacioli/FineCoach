# US1 无障碍与 UI 回归证据

记录日期：2026-08-28

范围：T025–T036（首次使用并安全管理 Student）。未启动 T037。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- VoiceOver：列表行与详情资料卡组合为「显示名称, 性别」；性别芯片有独立 label 与 selected trait；伤病/注意事项折叠控件有 collapsed/expanded value；删除确认输入框使用「输入显示名称以确认」label。
- 触控目标：`FCButton` / `FCTextField` 最小高度 44 pt；跳过首次说明、归档、永久删除、返回详情等文本按钮的 label 设为 `minHeight: 44` 并带 `contentShape`；性别芯片为两行布局，每枚 `minHeight: 44` 且允许文案缩放。
- Dynamic Type：首次说明、编辑、列表、详情、归档/删除确认均在 `ScrollView` 或可滚动栈中；性别芯片改为 2×2，避免超大字号横向溢出。
- 简体中文：`Localizable.xcstrings` 以 `text.json.xcstrings` 编译；工程 `developmentRegion` 与 `CFBundleDevelopmentRegion` 为 `zh-Hans`。UI 测试以 `-AppleLanguages (zh-Hans)` 启动。

## Simulator 回归

设备：iPhone 17，iOS 26.5。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoachDD-US1-Unit/Logs/Test/Test-FineCoachTests-2026.08.28_04-43-43--0700.xcresult` | 9/9 通过 |
| FineCoachIntegrationTests | `/tmp/FineCoachDD-US1-Int/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_04-43-45--0700.xcresult` | 15/15 通过（含 Foundation 9 + Student 6） |
| FineCoachUITests | `/tmp/FineCoachDD-US1-UI/Logs/Test/Test-FineCoachUITests-2026.08.28_04-41-25--0700.xcresult` | 5/5 通过 |

UI 覆盖：

- 首次说明与本机边界、跳过创建、空列表中文文案。
- 同名「林林」搜索、归档、恢复、名称确认永久删除。
- 进行中训练阻断永久删除（无名称输入框）。
- `UICTContentSizeCategoryAccessibilityXL` 下首次说明跳过与列表「添加学员」仍可点。

`swift-format lint --strict` 已在本轮源码上执行通过。

## 实体设备

- 设备：iPhone XS Max（iPhone11,6），iOS 18.7.9，id `00008020-000C5D2C3ED3002E`。
- 结果包：`/tmp/FineCoachDD-US1-Device/Logs/Test/Test-FineCoachUITests-2026.08.28_05-02-45--0700.xcresult`。
- 结果：FineCoachUITests 5/5 通过（含首次说明、搜索/归档/恢复/确认删除、进行中阻断、AccessibilityXL）。
- 为安装 UI test runner 给 `FineCoachUITests` 补了与 App 相同的 Automatic signing team；安装使用 `-allowProvisioningUpdates`。这不是 Data Protection 设备证据。

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未启动 T037 或任何 User Story 2 任务。
