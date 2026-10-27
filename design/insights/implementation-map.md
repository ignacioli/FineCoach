# 阶段 E 洞察：设计改动与实施映射

> 状态：**已实现，集中走查与左滑复看通过（2026-10-27）；待合并。**画稿 E-a1、E-a2、E-b、E-c 2026-10-24 批准，E-d 与 B-b、B-c 修订 2026-10-27 批准。本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
> 行为权威：`specs/005-stage-e-insights/spec.md`（`1.1-approved`）、`plan.md`、`tasks.md`。视觉权威：`design/design-system/README.md`、`components.md`；本轮记录见 README §1.11、§10 C26；走查修订（左滑取代「…」）见 README §1.12、§10 C27。
> Penpot：E-a1、E-a2、E-b 在 Foundations 页（x=13090 / 13530 / 13970）；E-c 在「M2 G7 Design」页（x=4960，M2-15 右侧）。快照 `before-stage-e-boards 2026-10-24` → `stage E boards aligned to implementation map (text fixed) 2026-10-24 b`。走查修订：E-d 在 Foundations 页 x=14410；快照 `before swipe revision (retire DS-MORE-MENU) 2026-10-27` → `swipe capsules redrawn to iOS 26 look (E-d, B-b) 2026-10-27`。

## 1. 按设计变化分类（`components.md` §1.2）

| 组件 / 位置 | 分类 | 范围 | 理由与依据 |
|---|---|---|---|
| 今日页「需要留意」区块（E-a1） | **B** 修订 | 页面组合：复用 `FCSectionLabel`、`FCListRow`、`FCListRowDivider`、`FCUndoRow`、`FCGroupEntryRow`（2026-10-27 起不再用 `FCMoreMenu`）；不新增共享组件 | 已批准的今日页（01 / W08-a）多了一个区块 |
| 「需要留意」完整列表页（E-a2） | **B** 新页面，组合现有组件 | `DS-PAGE-SECONDARY`（`FCPageHeader`）+ 按类型分组的同一提示行 | 新的二级页，没有新视觉语言 |
| 学员详情提示区（E-b） | **B** 修订 | 同一提示行，主文字不带学员名 | 已批准的学员详情（M2-03）多了一个区块 |
| 训练趋势指标切换第 4 段「估算 1RM」（E-c） | **B** 修订 | `DS-SEGMENTED` 使用范围扩到 4 段（README §10 C26）；`TrendLineChart` 外观不改 | 已批准的 M2-15 多一个指标与一行说明 |
| 提示行暂不提醒改左滑 + 撤销 + 首次轻推（E-d，2026-10-27） | **B** 修订 | 左滑操作扩展（`components.md` §4.8）；`DS-UNDO-ROW` 复用边界扩到暂不提醒；`DS-MORE-MENU` 退役 | 集中走查：「…」系统菜单在 iOS 26 / 18 都太大（README §10 C27） |
| 分区标题左滑删除、指标停用移到底部（B-b、B-c 修订，2026-10-27） | **B** 修订 | 训练中、模板编辑、记录指标三页；复用 `DS-CONFIRM-DIALOG`、`DS-ACTION-ROW` | 同上，`FCMoreMenu` 的另外两处用法 |

不涉及 A 类，没有新 token、新图标、新颜色。趋势线沿用 `action.primary`（README §2：大面积强调只用深色或中性色；虚线已表示「数据点稀疏」，不能再用来表示「估算」）。

## 2. 页面组合

### 2.1 提示行 `InsightRowView`（feature 专有，E-a1 / E-a2 / E-b 共用）

- **部件**：`FCListRow`（`titleStyle: .body`，主文字 + `subtitle`，`showsDisclosure: false`，整行是一个跳转按钮），`.frame(maxWidth: .infinity)` 撑满。行与行之间的 `FCListRowDivider` 由区块放置。没有 `›`，也没有「…」（2026-10-27 起）。
- **容器**：三个页面的提示行放在不滚动的 `List` 里（左滑只在 `List` 中可用），去掉 `List` 自带的背景、分割线与行内边距，外观与改之前一致（plan §3.10）。
- **左滑**：`.swipeActions(edge: .trailing, allowsFullSwipe: true)`，按钮「暂不提醒」+ `bell.slash`，`.tint(FCSemanticColors.textSecondary)`，非破坏性，不弹确认（E-d，spec E-FR-014 Rev 1.1）。
- **撤销**：左滑后原位置换成 `FCUndoRow`「<学员名> · 已暂不提醒 14 天」（学员详情不带学员名）+「撤销」，`FCUndoRow.undoWindow`（4 秒）后移除；今日页随后补上下一条。
- **首次轻推**：今日页第一次出现提示时第一行向左轻推 72 pt、露出装饰性的灰色胶囊，停 0.6 s 后弹回；每台设备一次；「减弱动态效果」时不播（README §10 C27）。
- **无障碍**：跳转部分读作「主文字，副文字」，trait 按钮；「暂不提醒」是该行的自定义操作（AC-E10）；轻推露出的胶囊对无障碍隐藏。
- **最大字体**：主文字与副文字都可换行，不截断数字。
- **不变量**：文字只用 §3 文案键拼出；不出现「请」；数字与单位之间有空格（README §13）。

### 2.2 今日页区块（E-a1）

- 位置：`appointmentSections` 之后（「已处理 · N」分组入口行之后），今日页内容的最后一个区块（Q-E4）。
- 结构：`FCSectionLabel`「需要留意」→ `FCListRowDivider` → 最多 3 条提示行（每行之后一条分割线）→ 提示总数大于 3 时 `FCGroupEntryRow(title: "全部", count: N)`（显示「全部 · N ›」，与上方「已处理 · N ›」同一组件），进入完整列表。
- 区块间距沿用今日页现有区块间距；没有提示时整个区块（含标题）不出现（AC-E09）；提示到达前不占位（plan §3.6）。

### 2.3 完整列表页（E-a2）

- `FCPageHeader` 标题「需要留意」+ `‹` 返回。
- 按类型分组，顺序：课包 → 很久没来 → 进步停滞（E-FR-006）；每组 `FCSectionLabel` + 分割线 + 提示行；空的组不出现。
- 列表为空（例如刚把最后一条暂不提醒）时只显示一行 `caption` `text.secondary`「没有需要留意的事」，不放吉祥物空态。

### 2.4 学员详情提示区（E-b）

- 位置：头像与训练目标之后、「概览」之前。
- 结构：`FCSectionLabel`「需要留意」+ 分割线 + 该学员的全部提示行；主文字不带学员名（§3）。没有提示时不出现。

### 2.5 训练趋势第 4 段（E-c）

- `FCSegmentedSwitch` 选项：重量 / 次数 / 容量 / 估算 1RM。只有所选动作在 spec §12.1 清单中时出现第 4 段；其他动作仍是 3 段。
- 选中「估算 1RM」时，图下显示一行 `caption` `text.secondary` 说明（`trends.e1rmCaption`），位置与现有容量说明（`trends.volumeCaption`）相同。
- y 轴最大值标签沿用现有格式；点的取值见 plan §3.7。「个人最佳」区块不变。

## 3. 文案

| 键（建议） | 中文 | 用在 |
|---|---|---|
| `insights.section.title` | 需要留意 | 今日页、学员详情区块标题；列表页页头 |
| `insights.section.all` | 全部 | 今日页分组入口行（显示为「全部 · N」） |
| `insights.group.package` | 课包 | 列表页分组 |
| `insights.group.inactive` | 很久没来 | 列表页分组 |
| `insights.group.stagnant` | 进步停滞 | 列表页分组 |
| `insights.list.empty` | 没有需要留意的事 | 列表页空 |
| `insights.action.snooze` | 暂不提醒 | 左滑按钮（2026-10-27 前为「…」菜单项「暂不提醒 14 天」） |
| `insights.snoozed.withName` | %@ · 已暂不提醒 14 天 | 撤销行（今日页、列表页） |
| `insights.snoozed` | 已暂不提醒 14 天 | 撤销行（学员详情） |
| `trends.metric.e1rm` | 估算 1RM | 趋势指标第 4 段 |
| `trends.e1rmCaption` | 估算 1RM = 重量 × (1 + 次数 ÷ 30)，只算 1～10 次的组。这是推算值，不是实测的最大重量。 | 趋势图下 |

提示行文案。今日页与列表页的主文字前加「学员名 · 」；学员详情不加：

| 类型 | 主文字（不含学员名） | 副文字 |
|---|---|---|
| 课包已用完 | 课包已用完 | 余额 %d 节 |
| 课包已过期 | 课包已过期 | 有效期至 %@（「M月d日」） |
| 课包快用完（余额 ≤ 2） | 课包剩 %d 节 | 有效期至 %@；没有结束日期时不显示副文字 |
| 课包快到期（余额 > 2，≤ 7 天到期） | 课包 %d 天后到期；当天为「课包今天到期」 | 剩 %d 节 |
| 很久没来 | %d 天没来 | 也没约下次课 |
| 很久没来（从没上过课） | 建档 %d 天还没上过课 | 也没约下次课 |
| 停滞 | 今日页 / 列表：动作名；学员详情：「动作名 · 连续 3 节没有创新高」 | 今日页：「连续 3 节没有创新高」；列表：「连续 3 节没有创新高 · 〈数值〉」；学员详情：「〈数值〉」 |

- 〈数值〉= 这 3 节**之前**历史的最好值（没被超过的那个「新高」）：清单动作「估算 1RM %@」；其他动作按主指标「最大 %@」/「最多 %d 次」/「最长 %@」，辅助类「最轻辅助 %@」。格式按 README §13（kg 最多 1 位小数，整数不带 `.0`）。
- 画稿没画出的文案（已过期、快到期、从没上过课、非重量主指标）以本表为准。

## 4. 执行记录

| 行 | 内容 |
|---|---|
| 分类和依据 | 四处均为 B；画稿 E-a1、E-a2、E-b、E-c（2026-10-24 批准）；快照见文首 |
| 范围 | 复用 `DS-LIST-ROW`、`DS-SECTION`、`DS-MORE-MENU`、`DS-SEGMENTED`、`DS-PAGE-HEADER`、`FCGroupEntryRow`；feature 专有 `InsightRowView`、`InsightSectionView`；`DS-SEGMENTED` 使用范围扩到 4 段（C26）；`DesignSystem/` 下没有文件改动 |
| 设计决定 | 不做左滑；「全部 · N」复用 `FCGroupEntryRow`（画稿原为「全部 5 条」，已改）；趋势线保持 `action.primary`；说明文案改为「这是推算值，不是实测的最大重量」（负责人 2026-10-24 指出原句不清楚）；「估算 1RM」段不单独绑 identifier，用整个分段控件的 `trends.metricPicker`，不为此扩展共享组件（2026-10-24 编排方决定）；列表页返回沿用 `FCPageHeader` 自带控件 |
| 实现和检查 | 分支 `feature/stage-e-insights`：`c4ecde6`（判定、估算 1RM、暂不提醒存储）、`a412bb2`（界面）、`07dd5b9`（趋势预选按最近一节课的记录模式；T012 预览；T020 测试）。文案、导航、今日页最多 3 行的选取、估算 1RM 点和回落都是纯函数，有单元测试（`InsightPresentationTests`、`EstimatedOneRepMaxTrendTests`、`TrendsInitialSelectionTests`）；暂不提醒后今日页和学员详情的数据源都不再含该条，有集成测试。入口与布局见 §5 |
| 结果 | 主机门禁 PASS（2026-10-24，`07dd5b9` 的工作区）：lint、Debug、Release、build-for-testing 均 0；FineCoachTests 602（1 个原有跳过），FineCoachIntegrationTests 210，0 失败；日志 `.handoff/logs/2026-10-23-stage-e-patch-accept-*.log`。**界面还没人看过**，L3 集中走查待做；预览只验证了能编译 |

L3（spec §7.4）：集中走查看今日页区块（有 / 无提示）、完整列表、学员详情提示、三类直达、「…」菜单、趋势第 4 段。另点名一个疑问：最大字体下 4 段切换是否放得下（放不下按 C26 改用筛选胶囊）。

**走查与修订（2026-10-27）**

| 行 | 内容 |
|---|---|
| 走查结果 | 负责人在模拟器 EFE2D5A0（iOS 26）与 iPhone XS Max（iOS 18）上看完 `.handoff/2026-10-24-stage-e-walkthrough-checklist.md`：全部通过，只有「…」不行（iOS 26 弹出大胶囊、iOS 18 灰色菜单太大；训练页分区「…」同源，非回归）。最大字体下 4 段切换放得下 |
| 分类和依据 | B：E-d（新）、B-b、B-c 修订，2026-10-27 批准；README §1.12、§10 C27；快照见文首 |
| 范围 | 退役 `DS-MORE-MENU`（删除 `FCMoreMenu`）；`DS-UNDO-ROW` 复用到暂不提醒；左滑操作扩展（`components.md` §4.8）；训练中、模板编辑、记录指标三页同时改 |
| 设计决定 | 否决底部面板、行内文字按钮、自绘白底浮层；分区左滑用 `.tint` 不用 `role: .destructive`（否则行先被移走）；复看时补：模板编辑动作行的蓝色系统 `Menu`「移出分区」（M1-B 起就有）改为左滑「移入分区」，与训练页一致；今日页暂不提醒后学员详情同步消失，负责人确认符合预期 |
| 实现和检查 | `336f465`（Codex：左滑、撤销、轻推、分区左滑、指标底部行、删 `FCMoreMenu`；Claude 删掉误加的 en 文案并补撤销行等高）、`c368bcc`（Claude：模板编辑左滑移入分区）。新增测试：`InsightSnoozeStoreTests`（unsnooze）、`InsightPresentationTests`（撤销窗口、补位、轻推判定）、`InsightUseCasesTests`（撤销后重建一致）；`TrainingEntryScanTests`、`M2ComponentContractTests` 的「…」断言改为断言左滑与退役 |
| 结果 | 主机门禁 PASS（`c368bcc` 的工作区）：lint、Debug、Release、build-for-testing 均 0；FineCoachTests 608（1 个原有跳过），FineCoachIntegrationTests 212；日志 `.handoff/logs/2026-10-23-stage-e-tplmove2-accept-*.log`。负责人复看 `336f465`（`.handoff/2026-10-27-stage-e-swipe-recheck-checklist.md`）全部通过；`c368bcc` 的模板编辑左滑「移入分区」随后在模拟器上复看通过（2026-10-27） |

## 5. 入口与布局清单（`components.md` §1.4）

`K` 是该行 `Insight.id`。三个页面的行都由 `InsightSectionView` → `InsightRowView` 生成，点击目的地由 `InsightNavigation.destination(for:today:)`（`Features/Insights/InsightRowContent.swift:108`）决定：课包类 → 课包页；没来上课 → 新建预约，预填该学员和今天；停滞 → 训练趋势「动作趋势」页，预选该动作最近一节课的记录模式。

| 画面 | 可见控件 | identifier | 改数据 | 撑满宽度的组件 / 容器 |
|---|---|---|---|---|
| 今日页 | 「需要留意」区块（排在约课区块之后） | `today.insights` | 否 | `InsightSectionView` 的 `.frame(maxWidth: .infinity)`；`TodayView.swift:260` |
| 今日页 | 提示行（最多 3 行，整行可点） | `insights.row.K` | 否 | `FCListRow` + `.frame(maxWidth: .infinity)`；`InsightRowView.swift:13` |
| 今日页 | 「全部 · N」（超过 3 条才出现） | `today.insights.all` | 否 | `FCGroupEntryRow`；`TodayView.swift:254` |
| 今日页 | 首次轻推（第一行左移 72 pt，露出装饰胶囊） | 无（对无障碍隐藏） | 只写本机标记 | 同一行的容器；`InsightRowView.swift:106` |
| 完整列表 | 页面根，按课包 / 没来上课 / 停滞分组 | `insights.root` | 否 | 页面 VStack `.frame(maxWidth: .infinity)`；`InsightsListView.swift:41` |
| 完整列表 | 提示行 | `insights.row.K` | 否 | `InsightSectionView`；`InsightsListView.swift:55` |
| 完整列表 | 「‹」返回 | `FCPageHeader` 自带 | 否 | `FCPageHeader`；`InsightsListView.swift:20` |
| 学员详情 | 「需要留意」区块（排在「概览」之前） | `studentDetail.insights` | 否 | `InsightSectionView`；`StudentDetailView.swift:147` |
| 学员详情 | 提示行（不重复学员名） | `insights.row.K` | 否 | `FCListRow`；`StudentDetailView.swift:143` |
| 三个页面 | 左滑「暂不提醒」（可一滑到底） | `insights.snooze.K` | **是**（写暂不提醒文件，三个页面同时移除该行） | 不滚动的 `List`，行内边距为 0；`InsightRowView.swift:47`、`:74` |
| 三个页面 | 撤销行「撤销」（4 秒，与原行同高） | `insights.undo.K` | **是**（删掉暂不提醒记录，三个页面重新读取） | `FCUndoRow`（自带 `.frame(maxWidth: .infinity)`）；`InsightRowView.swift:51` |
| 训练中 | 分区标题左滑「删除分区」（不能一滑到底，弹确认） | `activeSessionDeleteSection(id)` | 确认后是 | 不滚动的 `List` + `.frame(maxWidth: .infinity)` 的 HStack；`ActiveSessionView.swift:584` |
| 模板编辑 | 分区标题左滑「删除分区」（不能一滑到底，弹确认） | `templateEditorDeleteSection(id)` | 确认后是 | 同上；`TemplateEditorView.swift:398` |
| 模板编辑 | 动作行左滑「移入分区」（有分区时才有） | `templateEditorMoveExercise(id)` | 选分区后是 | 动作行 `List`；分区选择 `TemplateEditorView.swift:272`；按钮 `:352` |
| 记录指标（自定义） | 「管理」里「停用指标」/「恢复指标」 | `bodyMeasurementArchive` / `bodyMeasurementRestore` | 是（可恢复，不确认） | `FCActionRow`；`BodyMeasurementEntryView.swift:404` |
| 训练趋势 | 第 4 段「估算 1RM」（仅 §12.1 清单动作） | 容器 `trends.metricPicker` | 否（只是视图状态） | `FCSegmentedSwitch`；`TrendsView.swift:273` |

所有改数据的操作都有可见按钮或左滑入口，没有只靠长按或 `.contextMenu` 的入口；App 里不再有「…」菜单。
