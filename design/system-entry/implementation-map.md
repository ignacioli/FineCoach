# 阶段 F 系统级入口：设计改动与实施映射

> 状态：**Phase 2 完成（2026-10-28）：共用基础（T005～T007）主机门禁全绿；画稿 F-a、F-b、F-c 负责人批准（§3）。下一步 Phase 3（US1 小组件）。**本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
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

- **部件**：「下一节 HH:mm」（`callout` 600）→ 学员显示名（`callout` 400，`.privacySensitive()`）→「今天还有 N 节」（`caption`，降低不透明度）。底为系统 `AccessoryWidgetBackground`。
- **状态**：解锁；锁着（学员名由系统打码）；今天没有课；今天的课都上完了；占位（快照缺失 / 损坏 / 日期不符，「打开 App 查看今天的课」）。
- **不变量**：只读快照白名单字段（spec §2.2；可自动：快照键集合测试）；学员名标 `privacySensitive`（可自动：源码扫描）；颜色由系统着色，不写 token 颜色（人工）；整块点击 → `finecoach://today`，无改数据控件（可自动：源码扫描无 `Button` / `AppIntent` 写入）。

#### `SE-LOCK-INLINE` 锁屏单行

- **部件**：一行文字「下一节 HH:mm」/「今天没有课」/「打开 App 查看」。**不放学员名**（Q-F1）。
- **不变量**：源码里该视图不引用学员名字段（可自动）。

#### `SE-HOME-SMALL` 主屏小号

- **部件**：「下一节课」（`sectionLabel`，`text.secondary`）→ 时间（`title` 22/600，`text.primary`）→ 学员名（`body`，`.privacySensitive()`）→ 弹性空白 →「今天还有 N 节」（`caption`，`text.secondary`）。底 `surface.page`，内边距 `space.4`。层级与今日页「下一节课」行相同。
- **状态**：解锁；锁着 / StandBy（打码）；今天没有课；占位。
- **不变量**：同 `SE-LOCK-RECT`；StandBy 用同一视图（人工：真机 R1）。

#### `SE-HOME-MEDIUM` 主屏中号

- **部件**：「今天还有 N 节」（`sectionLabel`）→ 最多 3 行：时间（`callout` 600）+ 学员名（`body`，`.privacySensitive()`），行间 1pt `surface.divider`。底与内边距同小号。
- **状态**：解锁；锁着（打码）；1～2 节时行数相应减少；今天没有课 / 占位同小号。
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
1. 主屏小组件用白底，层级与今日页「下一节课」行相同。
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

### 4.1 真机证据

| 项 | 来源 | 结果 |
|---|---|---|
| 签名：带 App Group 的 Debug 版能装上并运行 | research R6，tasks T004 | **通过**（2026-10-27，iPhone XS Max）：自动签名（个人团队，描述文件 7 天，至 2026-11-04）为 App 与扩展签入 `group.com.finecoach.app`；首次启动需在手机上重新信任开发者；负责人确认 App 能打开，占位小组件能加到锁屏（矩形）与主屏（小号）。构建日志 `.handoff/logs/2026-10-27-stage-f-phase1-device-build.log` |
| 小组件锁着打码（各形态、StandBy、VoiceOver） | research R1，tasks T018 | 未取得 |
| Live Activity 出现 / 更新 / 结束、划掉后倒计时、残留清理 | research R4，tasks T026 | 未取得 |
| 快捷指令锁着先要求解锁、不朗读 | research R5，tasks T030 | 未取得 |

## 5. 入口与布局清单（`components.md` §1.4）

画面 → 可见控件 → identifier → 改数据？→ 撑满宽度的组件 / 容器。本阶段所有新入口都是跳转、不改数据。

（各故事完成时填写。）
