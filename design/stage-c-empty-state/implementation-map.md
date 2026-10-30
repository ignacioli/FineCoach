# 阶段 C 空态环境动效与白屏开屏：实施映射

> 状态：**实现完成，主机门禁全绿；负责人模拟器与真机走查通过（2026-10-30）。**本文是 `components.md` §1.4 要求的执行记录，不重复 token 数值。
> 设计权威：`design/design-system/README.md` §9「咖啡兔」、§9.3 定稿、§10 C30 / C31、§14.1 第 6 条、§14.2 `motion.ambient.*`；`components.md` §4.9 `DS-AMBIENT-SCENE`、§4.6 `DS-EMPTY-STATE` / `DS-LAUNCH`。Penpot「M1-B G5 Design」Foundations 页 C-c 关键帧、G-b 说明。
> 分支：设计文档在 `topic/docs-stage-c-reference-library-ebfe5a`；代码在 `topic/empty-state-cafe-scene`。

## 1. 设计变化分类（`components.md` §1.2）

| 组件 / 页面 | 分类 | 范围 | 代码 |
|---|---|---|---|
| `DS-AMBIENT-SCENE` 空态环境场景 | B（扩展 `DS-EMPTY-STATE`） | 新增（共享，今日与课程日历两处用） | `DesignSystem/Components/FCAmbientEmptyScene.swift` |
| 今日空态 | B | 复用 `DS-EMPTY-STATE` 布局 + `DS-AMBIENT-SCENE` 220 | `TodayView.emptyState` |
| 课程日历空态 | B | `DS-AMBIENT-SCENE` 160 + 标题 | `CalendarView`（选中日无课分支） |
| 空态文案 | A 文案 | C30 ② 例外 | `Localizable.xcstrings` 三个 key |
| `DS-LAUNCH` 开屏 | B（C31 定稿） | 删除叠层与图标，只留白底 | `LaunchScreen.storyboard`、`AppRoot` |

## 2. 入口与布局清单（§1.4）

```text
今日 → 咖啡兔 220 / 「今天没课，休息一下吧～」/「有新课程时会显示在这里」→ today.emptyState → 否 → TodayView.emptyState VStack .frame(maxWidth: .infinity)
课程日历 → 咖啡兔 160 /「这天没课，歇一歇吧～」→ calendar.emptyState → 否 → CalendarView 空态 VStack .frame(maxWidth: .infinity)
开屏 → 白底，无控件 → 无（系统启动画面）→ 否 → storyboard 根 view 全屏
```

三处都没有新的可交互控件；插画对辅助功能隐藏且不响应点击（`FCAmbientEmptySceneTests` 源码断言）。今日的「＋」与课程日历底部「＋ 添加课程安排」保持原样。

## 3. 自动验证

主机门禁 `.handoff/gate.sh`（2026-10-30）：lint 0、Debug / Release 构建 0、build-for-testing 0；FineCoachTests 687 项 0 失败（1 项原有跳过）；FineCoachIntegrationTests 223 项 0 失败。

| 测试 | 规则 |
|---|---|
| `FCAmbientEmptySceneTests`（6 项） | §14.2 热气、呼吸、眨眼取值与静止帧；§9 素材尺寸与透明通道；§4.9 装饰性与暂停条件；数值只来自 `FCMotion` |
| `TrainingEntryScanTests.testChineseLocalizationsUseB7Tone`、`testEmptyStateToneExceptionDoesNotPermitOtherKeysOrSwiftLiterals` | C30 ②：例外只放过空态 key；「～」补进句末字符集 |
| `LaunchScreenConfigurationTests` | C31：storyboard 无图无字，叠层与 `launch-icon` 已删除 |

## 4. 人工（L3）

触发：新组件 `DS-AMBIENT-SCENE` 首次落地（L3 第 2 条）。2026-10-30 负责人在 iPhone 17 模拟器（空数据库，Debug 版）走查，**通过**：动效观感与原型一致；课程日历 160 不挤出首屏，确认采用；最大动态字号布局可接受；冷启动白屏直接进首页。同日 Release 版覆盖安装到负责人真机（iPhone XS Max，保留原有数据）走查，**通过**，符合预期。
