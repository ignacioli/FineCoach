# 阶段 F 系统级入口：设计改动与实施映射

> 状态：**Phase 5 完成（2026-10-29）：US1 小组件、US2 Live Activity、US3 快捷指令与 T032 设置说明段均主机门禁全绿并取得真机证据（§4.1）。R1 已按 T-03 降级（学员名只在解锁后的主屏显示）。下一步 Phase 6：T033 设计记录与 Penpot 回填、T034 隐私安全审查、T035 集中走查。**本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
> 行为权威：`specs/006-stage-f-system-entry/spec.md`（`1.0-approved`）、`plan.md`、`tasks.md`、`research.md`、`data-model.md`。字段白名单只认 spec §2.2。视觉权威：`design/design-system/README.md`（§8「系统入口」、§10 C28）、`components.md`。
> 分支：本文件在设计文档分支 `topic/docs-stage-f-system-entry-590290`；代码在实现分支 `feature/stage-f-system-entry`（worktree `.worktrees/stage-f-system-entry`）。

## 1. 按设计变化分类（`components.md` §1.2）

分类沿用 spec §7.1。小组件与实时活动只有本阶段使用，而且代码在扩展 target `FineCoachWidgets`，不在 `DesignSystem/` 下，按 `components.md` §1.3 记为 **feature 专有组件**（ID 前缀 `SE-`），anatomy 写在本文 §2，不进 `components.md` 索引（`ComponentCatalogTests` 只认 `DesignSystem/` 的公开类型）。第二个 feature 需要时再提升。tasks T008 原写「anatomy 先写进 components.md」，按此改为写在本文。

| 组件 | 分类 | 范围 | 来源 |
|---|---|---|---|
| `SE-LOCK-RECT` 锁屏矩形 | C 新组件 | 新增（feature 专有） | F-a |
| `SE-LOCK-INLINE` 锁屏单行 | C | 新增 | F-a |
| `SE-HOME-SMALL` 主屏小号（StandBy 复用） | C | 新增 | F-a |
| `SE-HOME-MEDIUM` 主屏中号 | C | 新增 | F-a |
| `SE-ACTIVITY` 实时活动锁屏 + 灵动岛（紧凑 / 最小 / 展开） | C | 新增 | F-b |
| 设置页说明段 | A/B 文案 | 复用 `DS-SECTION`（`FCSectionLabel`）+ 正文 `Text`，放在现有设置页最后一组之后 | F-c |

## 2. 组件 anatomy（feature 专有，2026-10-28 随 F-a～F-c 批准）

格式同 `components.md` §4。数值引用 README token；系统决定的尺寸、圆角、锁屏着色不写死。

#### `SE-LOCK-RECT` 锁屏矩形

- **部件**：「下一节 HH:mm」（`callout` 600）→「今天还有 N 节」（`caption`，降低不透明度）。**不放学员名**：2026-10-28 真机 R1 显示锁着时系统没有打码，按 spec §8 T-03 降级（§4.1）。底为系统 `AccessoryWidgetBackground`，文字由系统着色（锁屏小组件不能用 App 颜色）。
- **状态**：有课（锁着、解锁相同）；今天没有课；今天的课都上完了；占位（快照缺失 / 损坏 / 日期不符，「打开 App 查看今天的课」）。
- **不变量**：只读快照白名单字段（spec §2.2；可自动：快照键集合测试）；源码不引用学员名字段（自动：`SystemEntryConfigurationTests`）；颜色由系统着色，不写 token 颜色（人工）；整块点击 → `finecoach://today`，无改数据控件（可自动：源码扫描无 `Button` / `AppIntent` 写入）。

#### `SE-LOCK-INLINE` 锁屏单行

- **部件**：一行文字「下一节 HH:mm」/「今天没有课」/「打开 App 查看」。**不放学员名**（Q-F1）。
- **不变量**：源码里该视图不引用学员名字段（可自动）。

#### `SE-HOME-SMALL` 主屏小号

- **部件**：「下一节课」（`sectionLabel`，`text.secondary`）→ 时间（`title` 22/600，`text.primary`）→ 学员名（`body`，`.privacySensitive()`）→ 弹性空白 →「今天还有 N 节」（`caption`，`text.secondary`）。底 `surface.page`，内边距 `space.4`。层级与今日页「下一节课」行相同。**2026-10-28 修订（负责人）**：底改为炭黑 `action.primary`，文字 `action.on`，次要文字 `text.onActionSecondary`，分割线 `surface.dividerOnAction`，与今日页深色 hero 卡、实时活动一致。
- **状态**：有课；StandBy（手机锁着、充电、横放时系统把主屏小号放大显示；2026-10-28 真机显示系统没有打码，按 spec T-03 降级为**不放学员名**，以 `showsWidgetContainerBackground == false` 识别，StandBy 去掉背景）；今天没有课；占位。主屏本身只在解锁后可见，所以主屏上没有「锁着」状态。
- **不变量**：同 `SE-LOCK-RECT`；StandBy 用同一视图（人工：真机 R1）。

#### `SE-HOME-MEDIUM` 主屏中号

- **部件**：「今天还有 N 节」（`sectionLabel`）→ 最多 3 行：时间（`callout` 600）+ 学员名（`body`，`.privacySensitive()`），行间 1pt `surface.divider`。底与内边距同小号。
- **状态**：有课（1～2 节时行数相应减少）；今天没有课 / 占位同小号。中号只出现在解锁后的主屏（StandBy 只用小号），没有锁着状态。
- **不变量**：最多 3 行（可自动：纯函数测试）。

#### `SE-ACTIVITY` 实时活动

- **锁屏部件**：左：动作名（`headline`，`action.on`）→ 次行（`caption`，`text.onActionSecondary`）；右：倒计时（`numeralLarge`，`action.on`，系统计时 `Text(timerInterval:)`），已超时时上方加「已超时」（`caption`）。底 `action.primary`（同今日页「进行中」深色 hero 卡）。
- **次行文案**（spec F-FR-020、Q-F2）：还没确认任何一组 → 无次行；不在休息 →「已完成 N 组」；休息中 →「第 N 组 · 休息」；已超时 →「第 N 组 · 休息结束」。
- **灵动岛**：紧凑 = 前部计时图标（SF Symbol `timer`）+ 尾部「1:45」/「3 组」/「+0:32」；最小 = 只有计时图标；展开 = 左上动作名、右上倒计时（已超时加「已超时」）、底部次行。
- **不变量**：ContentState 只有动作名、组序号、休息结束时刻（spec §2.2；可自动：键集合测试）；不出现学员名、重量、次数（可自动：渲染文本测试）；点击 → `finecoach://session/<id>`（可自动）。

## 2.1 页面组合

- F-c：设置页（现有 D15c）最后一组之后加区段标签「小组件与实时活动」（`DS-SECTION`）和一段说明（`callout` 400，`text.secondary`，宽度撑满 `space.4` 边距内）。不可点击，不改数据。

## 3. 画稿与文案

| 画稿 | 内容 | 状态 |
|---|---|---|
| F-a | 锁屏矩形 / 单行，主屏小 / 中号（含 StandBy 锁着打码、空态、占位） | 已批准（2026-10-28） |
| F-b | Live Activity 锁屏 + 灵动岛紧凑 / 最小 / 展开（休息中、已超时） | 已批准（2026-10-28） |
| F-c | 设置页说明行（spec F-FR-040） | 已批准（2026-10-28） |

Penpot「M1-B G5 Design」/ Foundations 页 y=3750：F-a（x=14850）、F-b（x=15850）、F-c（x=16850，复制 D15c）。快照 `before-stage-F boards 2026-10-28` → `stage-F boards F-a F-b F-c 2026-10-28 (pending approval)` → 批准后 `stage-F boards F-a F-b F-c approved 2026-10-28`。壁纸、主屏底色只是示意；系统决定的尺寸按 iPhone XS Max 近似。

**新决定（负责人 2026-10-28 全部批准）**：
1. 主屏小组件用白底，层级与今日页「下一节课」行相同。→ 2026-10-28 真机看过后负责人改为炭黑底（类 B），Penpot 快照 `before F-a revision charcoal + lock-rect no name 2026-10-28` → `F-a revised: charcoal home widgets, lock-rect without name (R1) 2026-10-28`。同日按负责人走查清理画稿：主屏只保留「有课」与 StandBy（小号）的锁着状态，删去中号的「锁着」变体；锁屏矩形去掉半透明底框（真机 iOS 不画）。快照 `before F-a cleanup (StandBy labels, lock-rect bg) 2026-10-28` → `F-a cleanup: StandBy-only locked state, lock widgets without bg 2026-10-28 (labels)`。**2026-10-28 修订（负责人）**：底改为炭黑 `action.primary`，文字 `action.on`，次要文字 `text.onActionSecondary`，分割线 `surface.dividerOnAction`，与今日页深色 hero 卡、实时活动一致。
2. 实时活动锁屏用深色 `action.primary` 底，与今日页「进行中」hero 卡一致。
3. 文案：空态「今天没有课」、全部上完「今天的课都上完了」、占位「打开 App 查看今天的课」（单行「打开 App 查看」）；超时锁屏 / 展开「已超时 0:32」，紧凑「+0:32」；不在休息时紧凑尾部「3 组」；最小形态只放计时图标。
4. 设置说明段文案（F-c 画稿）。
5. 字体：小组件与实时活动用系统字体（苹方），不在扩展里再打包约 15 MB 的 Noto Sans SC（扩展有严格内存上限，锁屏形态本来就由系统渲染）。

## 4. 执行记录

| 日期 | 阶段 / 任务 | 提交 | 闸门结果 | 备注 |
|---|---|---|---|---|
| 2026-10-27 | 建实现 worktree，分支 `feature/stage-f-system-entry`（基于 main `29ee636`）；T001 本文件 | — | — | — |
| 2026-10-27 | T002、T003：空壳扩展 `FineCoachWidgets`（占位小组件，只显示固定文字，不读数据）、App Group `group.com.finecoach.app`、`NSSupportsLiveActivities`；`SystemEntryConfigurationTests`。修正：`CapabilityManifestTests` 改为只放行这一个 App Group，import 扫描扩到 `FineCoachWidgets/`（负责人 2026-10-27 批准） | 未提交 | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 611（1 skip，既有）0 失败；Integration 212 0 失败；`FineCoach.app/PlugIns/FineCoachWidgets.appex` 存在。门禁构建关闭签名，签名能力看 §4.1 | Codex gpt-6.1-sol 两轮；无新 UI（占位小组件 US1 时替换） |
| 2026-10-28 | T005～T007：文件策略 `widgetSnapshot`、`SharedContainer`（App 与扩展共用）、R7 六个日志事件、`SystemEntryRouting`（只认两种 URL，「开始训练」→ 今日页，spec Rev 1.1）；新增 `SystemEntryInfrastructureTests`、`SystemEntryRoutingTests` 共 19 项 | 未提交 | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 630（1 skip，既有）0 失败；Integration 212 0 失败 | Codex gpt-6.1-sol 一轮 8 分钟；未注册 URL scheme，`widgetURL` 能否送达待 Phase 3/4 真机确认；画稿当天批准，Phase 2 checkpoint 完成（T010） |
| 2026-10-28 | T011～T017：`WidgetTodaySnapshot`（含 `finishedCount`，data-model §1 2026-10-28 修订）、`WidgetSnapshotReader`（两 target 共用的只读入口）、`WidgetSnapshotPublisher`（刷新挂点：预约、学员改名 / 归档、训练完成 / 放弃、回到前台）、`TodayWidget` 四种形态替换占位小组件；文案进同一份 `Localizable.xcstrings`（加入扩展资源），`Tokens.swift` 共享 target membership，系统字体 | 未提交 | 主机 `gate.sh`（改字重后重跑）：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 649（1 skip，既有）0 失败；Integration 218 0 失败 | Codex gpt-6.1-sol 一轮约 11 分钟，无报错无重试；Claude 审 diff 后修一处偏离 F-a：空态 / 占位文字字重改为 600（类 D）。R1 真机证据未取得 |
| 2026-10-28 | T018～T019：真机 R1 后的改动——锁屏矩形与 StandBy 不放学员名（`showsWidgetContainerBackground` 识别 StandBy）、主屏改炭黑底（负责人）、时间等宽数字；`SystemEntryConfigurationTests` 加两条断言 | 未提交 | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 649（1 skip，既有）0 失败；Integration 218 0 失败 | Claude 直接修改（每处几行）；Phase 3 checkpoint 完成 |
| 2026-10-28 | T020～T025：`SessionActivityAttributes`（Attributes 只有 `sessionID`；ContentState 为动作名、当前动作已完成组数、休息结束时刻）、`SessionActivityController`（本地 request，`pushType: nil`，`staleDate` = 休息结束，启动清理）、挂点（用例：开始 / 完成 / 放弃；VM：确认组、±15 秒、清除休息、切换动作、恢复休息，均在原通知调用旁，通知不变）、`SessionLiveActivity`（锁屏 + 灵动岛三形态，按 F-b）；新增 `SessionActivityContentTests` 6 项、`SessionActivityHookTests` 10 项 | `a7fa023` | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 666（1 skip，既有）0 失败；Integration 218 0 失败 | Codex gpt-6.1-sol 一轮；其内部 dsh-gate 一直 75，最终版本由主机 gate 补证。T026 真机证据未做，T027 待 T026 |
| 2026-10-28 | T028、T029、T032：三个无参数 `AppIntent`（`requiresAuthentication`、`openAppWhenRun`，`perform()` 只交页面请求给 `SystemEntryRouter.shared`，无对话文字）、`AppShortcutsProvider`（`AppShortcuts.xcstrings` 三条 zh-Hans 短语含 App 名）；设置页「小组件与实时活动」说明段（F-c 原文，`FCSectionLabel` + `callout`）；新增 `SystemEntryIntentsTests` 7 项与静态断言（无索引、捐赠、参数、对话） | `d26ce35` | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 674（1 skip，既有）0 失败；Integration 218 0 失败 | Codex gpt-6.1-sol 一轮，自报计数与主机一致 |
| 2026-10-29 | T026 真机修复：休息中 / 已超时锁屏整块空白——系统计时文字会占满可给的宽度，`.fixedSize` 把整行挤出可视区 → 计时放进隐藏模板「00:00」定宽的槽位；倒计时到点停在 0:00、要等系统按 `staleDate` 重绘 → 改用 `Text(_:style: .timer)`，到点后自行向上计时（research R4 已列此写法）。`SystemEntryConfigurationTests` 的计时断言由 `Text(timerInterval:` 改为 `style: .timer)`（意图不变：用系统计时） | `e3d9e45` | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 674（1 skip，既有）0 失败；Integration 218 0 失败 | Claude 直接修改（类 D：代码偏离 F-b）；Phase 4、Phase 5 checkpoint 完成（T027、T031） |
| 2026-10-29 | T033：README §1.13（画稿与实现回填）、§8「系统入口」行改为真机后规则、§10 C28 补 10-28 修订与 10-29 剩余限制；Penpot F-a～F-c 下方各加「实现回填」说明（快照 `before stage F implementation backfill 2026-10-29` → `stage F implementation backfill notes F-a F-b F-c 2026-10-29`） | 本文档分支 | 文档 | 2x 导出待 T035 走查后 |
| 2026-10-29 | T034：`mobile-privacy-security-reviewer`（只读，sonnet）审 `main..HEAD`，结论 **PASS WITH NOTES**，无高 / 中危。N1 覆盖式恢复后快照仍是旧学员名 → 恢复成功后立即重建（`BackupRestoreFlow`）；N2 重建失败保留旧快照 → 删除旧文件并刷新，小组件显示占位（`WidgetSnapshotPublisher`）；N3 跳转后训练页 `startOrOpen` 可能新建训练（阶段 F 前已有，通知入口同样）→ 负责人记待办（blueprint §6 第 11 项）；N4 扩展共享源文件不在静态扫描范围、N5 扩展无单独隐私清单 → 信息级，上架前处理。未采纳：viewer / 存储不可用时删快照（快照仍是本机真实数据，不是残留） | `76f87e2` | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 674（1 skip，既有）0 失败；Integration 219 0 失败 | 新增 `testFailedRebuildRemovesThePreviousSnapshotAndReloadsOnce`；`BackupRoundTripTests` 页面恢复断言快照刷新 1 次 |

### 4.1 真机证据

| 项 | 来源 | 结果 |
|---|---|---|
| 签名：带 App Group 的 Debug 版能装上并运行 | research R6，tasks T004 | **通过**（2026-10-27，iPhone XS Max）：自动签名（个人团队，描述文件 7 天，至 2026-11-04）为 App 与扩展签入 `group.com.finecoach.app`；首次启动需在手机上重新信任开发者；负责人确认 App 能打开，占位小组件能加到锁屏（矩形）与主屏（小号）。构建日志 `.handoff/logs/2026-10-27-stage-f-phase1-device-build.log` |
| 小组件锁着打码（各形态、StandBy、VoiceOver） | research R1，tasks T018 | **部分**（2026-10-28，iPhone XS Max）：主屏小 / 中号解锁显示正常、点击可用；**锁屏矩形锁着时学员名没有打码**（锁屏截图，锁头为关闭状态）→ 按 spec §8 T-03 降级为不放学员名，代码、测试、Penpot F-a 同轮修改。**StandBy 小号锁着时学员名也没有打码**（StandBy 截图）→ 同样降级：StandBy 不放学员名，只有解锁后的主屏显示学员名；代码、静态断言、Penpot F-a 同轮修改（快照 `before F-a StandBy without name 2026-10-28` → `F-a: StandBy small without name (R1) 2026-10-28`）。结论：本机上系统打码（F-P5）对锁屏与 StandBy 都不生效，学员名现在只出现在解锁后可见的主屏。VoiceOver 锁着朗读不再适用（锁着可见的形态都不含学员名）。点击进今日页（未注册 URL scheme）、缺席后课数变化未专门验证。负责人 2026-10-28 决定 R1 到此为止，不追查系统不打码的原因 |
| Live Activity 出现 / 更新 / 结束、划掉后倒计时、残留清理 | research R4，tasks T026 | **通过，有剩余限制**（2026-10-29，iPhone XS Max，负责人）：锁屏出现；未确认任何一组、不在休息两态正常；首轮休息中 / 已超时整块空白、超时停在 0:00（代码问题，`e3d9e45` 修复）；复验休息中显示动作名、「第 N 组 · 休息」、倒计时，到点后数字继续向上计时；两名学员各一条、各自显示。**剩余限制**：到点后「第 N 组 · 休息结束」与「已超时」文字依赖系统按 `staleDate` 重绘，本机休息结束 1 分钟后仍未出现，负责人接受（数字始终正确）。负责人另确认：点击进入对应训练页（未注册 URL scheme 也能送达）、划掉 App 后倒计时继续、完成 / 放弃后活动消失。启动残留清理：负责人多次试验未见残留，记为通过（需训练已结束而活动未结束才会触发，例如结束途中 App 崩溃，难以有意制造；逻辑由 `testLaunchCleanupReceivesOnlyPersistedActiveSessionIDs` 覆盖）。灵动岛三形态本机没有，留 T035 模拟器走查 |
| 快捷指令锁着先要求解锁、不朗读 | research R5，tasks T030 | **通过**（2026-10-29，iPhone XS Max，负责人验收） |
| 锁屏休息结束通知只显示「Notification」 | 负责人走查中发现，疑似回归 | **不是回归**：本分支通知代码改动 0 行；iOS「显示预览：解锁时」导致锁着不显示正文，解锁后正文为「休息结束 / 动作名 · 可以开始下一组了」，负责人改系统设置后符合预期 |

## 5. 入口与布局清单（`components.md` §1.4）

画面 → 可见控件 → identifier → 改数据？→ 撑满宽度的组件 / 容器。本阶段所有新入口都是跳转、不改数据。

| 画面 | 可见控件 | identifier | 改数据？ | 撑满宽度 |
|---|---|---|---|---|
| 锁屏矩形 `SE-LOCK-RECT` | 整块小组件（下一节、还有 N 节 / 空态 / 占位；不放学员名）→ 今日页 | 系统小组件，无 identifier；`widgetURL finecoach://today`（`TodayWidget.swift`） | 否 | `RectangularTodayView` 的 `VStack` `.frame(maxWidth: .infinity)` |
| 锁屏单行 `SE-LOCK-INLINE` | 整行文字 → 今日页 | 同上 | 否 | 系统 inline 槽位 |
| 主屏小号 `SE-HOME-SMALL` | 整块 → 今日页（StandBy 不放学员名） | 同上 | 否 | `HomeTodayView` 的 `VStack` `.frame(maxWidth: .infinity, maxHeight: .infinity)` |
| 主屏中号 `SE-HOME-MEDIUM` | 整块 → 今日页（最多 3 行） | 同上 | 否 | `HomeTodayView`，每行 `HStack` `.frame(maxWidth: .infinity)` |
| Live Activity 锁屏 `SE-ACTIVITY` | 整块（动作名、次行、倒计时 / 已超时）→ 该训练页 | 系统实时活动，无 identifier；`widgetURL finecoach://session/<小写 id>`（`SessionLiveActivity.swift`） | 否 | `SessionActivityLockView` 的 `HStack` `.frame(maxWidth: .infinity)` |
| 灵动岛紧凑 / 最小 / 展开 | 计时图标、倒计时 / 组数 / 超时；展开含动作名与次行 → 该训练页 | 同上 | 否 | 系统槽位；展开底部 `.frame(maxWidth: .infinity)` |
| 快捷指令「今日」「开始训练」「继续训练」 | 系统快捷指令 / Siri 短语「精练教练 …」→ 今日页 / 今日页 / 唯一进行中训练或今日页 | 系统，无 identifier（`SystemEntryIntents.swift`） | 否 | 系统界面 |
| 设置页说明段 | 区段标签「小组件与实时活动」+ 两段说明（不可点击） | `settings.systemEntry.description`（`SettingsView.swift`） | 否 | 正文 `.frame(maxWidth: .infinity, alignment: .leading)`，父 `VStack` `space.4` 边距 |
