# 阶段 E 洞察：设计改动与实施映射

> 状态：**画稿已批准（E-a1、E-a2、E-b、E-c，2026-10-24）；待实现。**本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
> 行为权威：`specs/005-stage-e-insights/spec.md`（`1.0-approved`）、`plan.md`、`tasks.md`。视觉权威：`design/design-system/README.md`、`components.md`；本轮记录见 README §1.11、§10 C26。
> Penpot：E-a1、E-a2、E-b 在 Foundations 页（x=13090 / 13530 / 13970）；E-c 在「M2 G7 Design」页（x=4960，M2-15 右侧）。快照 `before-stage-e-boards 2026-10-24` → `stage E boards aligned to implementation map (text fixed) 2026-10-24 b`。

## 1. 按设计变化分类（`components.md` §1.2）

| 组件 / 位置 | 分类 | 范围 | 理由与依据 |
|---|---|---|---|
| 今日页「需要留意」区块（E-a1） | **B** 修订 | 页面组合：复用 `FCSectionLabel`、`FCListRow`、`FCListRowDivider`、`FCMoreMenu`、`FCGroupEntryRow`；不新增共享组件 | 已批准的今日页（01 / W08-a）多了一个区块 |
| 「需要留意」完整列表页（E-a2） | **B** 新页面，组合现有组件 | `DS-PAGE-SECONDARY`（`FCPageHeader`）+ 按类型分组的同一提示行 | 新的二级页，没有新视觉语言 |
| 学员详情提示区（E-b） | **B** 修订 | 同一提示行，主文字不带学员名 | 已批准的学员详情（M2-03）多了一个区块 |
| 训练趋势指标切换第 4 段「估算 1RM」（E-c） | **B** 修订 | `DS-SEGMENTED` 使用范围扩到 4 段（README §10 C26）；`TrendLineChart` 外观不改 | 已批准的 M2-15 多一个指标与一行说明 |

不涉及 A 类，没有新 token、新图标、新颜色。趋势线沿用 `action.primary`（README §2：大面积强调只用深色或中性色；虚线已表示「数据点稀疏」，不能再用来表示「估算」）。

## 2. 页面组合

### 2.1 提示行 `InsightRowView`（feature 专有，E-a1 / E-a2 / E-b 共用）

- **部件顺序**：`FCListRow`（`titleStyle: .body`，主文字 + `subtitle`，`showsDisclosure: false`，整行是一个跳转按钮）→ 右侧 `FCMoreMenu`（独立可点，44×44 热区）。两者放在一个 `HStack`，`FCListRow` 以 `.frame(maxWidth: .infinity)` 撑满剩余宽度。行与行之间的 `FCListRowDivider` 由区块放置。
- **没有** `›`：行尾位置给了「…」。
- **「…」菜单**只有一项「暂不提醒 14 天」，非破坏性，不弹确认。**不做左滑**：今日页与学员详情是 `ScrollView`，SwiftUI 左滑只在 `List` 中可用；「…」已是可见入口（spec E-FR-014）。
- **无障碍**：跳转部分读作「主文字，副文字」，trait 按钮；「…」另为一个元素，标签沿用 `designSystem.moreActions`（AC-E10）。
- **最大字体**：主文字与副文字都可换行，不截断数字；「…」不缩小。
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
| `insights.action.snooze` | 暂不提醒 14 天 | 「…」菜单 |
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

## 4. 执行记录（五行，实施时填写）

| 行 | 内容 |
|---|---|
| 分类和依据 | 四处均为 B；画稿 E-a1、E-a2、E-b、E-c（2026-10-24 批准）；快照见文首 |
| 范围 | 复用 `DS-LIST-ROW`、`DS-SECTION`、`DS-MORE-MENU`、`DS-SEGMENTED`、`DS-PAGE-HEADER`；feature 专有 `InsightRowView`；`DS-SEGMENTED` 使用范围扩到 4 段（C26） |
| 设计决定 | 不做左滑；「全部 · N」复用 `FCGroupEntryRow`（画稿原为「全部 5 条」，已改）；趋势线保持 `action.primary`；说明文案改为「这是推算值，不是实测的最大重量」（负责人 2026-10-24 指出原句不清楚） |
| 实现和检查 | 待填 |
| 结果 | 待填 |

L3（spec §7.4）：集中走查看今日页区块（有 / 无提示）、完整列表、学员详情提示、三类直达、「…」菜单、趋势第 4 段。另点名一个疑问：最大字体下 4 段切换是否放得下（放不下按 C26 改用筛选胶囊）。

## 5. 入口与布局清单（`components.md` §1.4，实施时填写）

| 画面 | 可见控件 | identifier | 改数据 | 撑满宽度的组件 / 容器 |
|---|---|---|---|---|
| （实现后按报告回填） | | | | |
