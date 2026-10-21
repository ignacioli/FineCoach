# 阶段 D 收获感：设计改动与实施映射

> 状态：**画稿已批准（2026-10-20），待实施**。本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
> 行为权威：`specs/004-stage-d-progress-milestones/spec.md`（`1.0-approved`，2026-10-20）。视觉权威：`design/design-system/README.md`、`components.md`。
> 画稿批准前，本文的组件结构只是约束草稿，不是已批准的设计。

## 1. 按设计变化分类（`components.md` §1.2）

| 组件 / 位置 | 分类 | 范围 | 理由与依据 |
|---|---|---|---|
| `DS-SET-ROW`（`FCSetRow`），训练页 | **B** 修订 | 扩展：新增「新纪录」标记，新纪录确认时换触感 | 已批准的组行（`components.md` §4.3、D8 / P0-a2 稿）没有这个状态；改的是已批准组件的视觉和交互 |
| 课程总结页「本节收获」区块 | **B** 修订 | 页面组合：复用 `FCSectionLabel`、`PersonalBestRowView`、`FCListRow`、`FCListRowDivider`，不新增共享组件 | 已批准的总结页（D8 变体 B）多了一个区块；组成部分都已有组件 |
| 分享设置「个人最佳」开关，分享卡片个人最佳区块 | **B** 修订 | 复用现有 `toggleRow` 与卡片 `section`；只改文案、可用条件，卡片区块加一行里程碑 | 已批准的 `28-share-settings-v2`、`29-share-preview` 文案和内容变了 |

不涉及 A 类（没有新的视觉语言），也没有新的 token。

## 2. 组件结构草稿

### D-a `DS-SET-ROW` 扩展：新纪录标记

- **部件顺序**：状态圆圈 → 「第 N 组」 → **「新纪录」标记** → 弹性空白 → 数值 → 状态文字 / 撤销 → 编辑按钮。
- **标记外观**：胶囊（`radius.capsule`），`surface.selected` 底，`sectionLabel` 字号、`action.primary` 字色，文字「新纪录」。复用 README §8「辅助器械徽标」的胶囊结构，字色从 `status.warning` 换成 `action.primary`：这是信息性的正面状态，不是需要教练处理的状态（README §7.2 规则）。不加图标，不加新颜色。
- **状态**：只在 `completed` 且持有本节该项纪录的组上出现（spec D-FR-013）。草稿组、待完成组都不出现。
- **触感**：确认时如果判为新纪录，`.impact(weight: .heavy)` 替代 `.success`，只响一次；重算（编辑、删除、撤销）不响（D-FR-010、D-FR-012）。
- **不变量**：
  - 整行仍然是一个无障碍元素，读作「标题，数值，新纪录，状态」（可自动）。
  - 标记不只靠颜色，必须有文字（可自动）。
  - 小屏和大字体下，标记不挤掉数值：先缩数值（现有最小缩放 0.8），仍放不下时标记换到标题下方另起一行（人工，画稿给出 375 宽和最大字体两种状态）。
- **受影响的现有使用方**：只有 ActiveSession。比较选择模式（32）只复用 `FCSetStateCircle`，不受影响。

### D-b 课程总结「本节收获」区块

- **位置**：总结页统计（时长、完成组数、训练重点）之后，「私人备注」之前。
- **结构**：`FCSectionLabel`「本节收获」→ 行，行间 `FCListRowDivider`：
  1. **新纪录行**：复用 `PersonalBestRowView`（名称 / 纪录类型 / 数值 / 「重量 × 次数」），日期栏不显示。
  2. **比上次进步行**：`FCListRow` 标题为动作名，副标题为「上次 80 kg × 5 → 本次 80 kg × 7」（`caption` `text.secondary`）。
  3. **里程碑行**：`FCListRow` 标题「第 25 节课」，副标题「累计完成的课程」。
- **排序**：新纪录 → 比上次进步 → 里程碑；同类按动作在本节出现的顺序。
- **空状态**：三类都没有时，整个区块（含标签）不出现（D-FR-020）。
- **不变量**：只读，没有可点控件；不改 `studentFacingSummary`（D-FR-024）；宽度由页面 `VStack` 的 `space4` 边距撑满（与其他区块一致）。

### D-c 分享设置与分享卡片（spec 1.2，PD-D5′）

- **命名**：开关、卡片区块与总结页区块统一叫「本节收获」（负责人 2026-10-20）。历史页「个人最佳」不改名。
- **设置页开关行**：复用现有 `toggleRow`，保持单行。标题「本节收获」；右侧提示按「N 项新纪录」→「第 M 节课」→「N 项进步」取前两个非空项，用「 · 」连接，强调色（`emphasizedNote`）。三类都空时整行不出现，不显示不可用的开关（spec 1.2；取消 D7a 原有的「本次无新纪录」灰色状态）。
- **卡片**：现有个人最佳区块改名「本节收获」，行与总结页 D-b 一致：新纪录（名称 / 类型 · 新纪录 / 值）→ 比上次进步（名称 / 「上次 → 本次」）→ 里程碑（「第 M 节课」/「累计完成的课程」）。开关关闭时整个区块不出现。
- **卡片氛围元素（spec 1.3）**：只在分享卡片上。新纪录行名称后复用 D-a 的「新纪录」胶囊；里程碑行左侧放兔子教练「比心」贴纸（40×40，耳朵下垂，透明底），文字右移 52；进步行不加图标；不用 emoji。贴纸已由负责人用 ChatGPT image 按 `.handoff/prompt/2026-10-20-stage-d-mascot-heart-sticker-prompt.md` 生成（2026-10-20），入库为 `design/design-system/assets/mascot-heart-sticker.png`（1254×1254 透明底），已登记 README §9；Penpot D-c2 已换成 80×80 缩小版。App 实现时由原图生成 @2x/@3x 资源（80、120 px）。
- **待负责人看的一点**：卡片底色是 `surface.canvas`，「新纪录」胶囊的 `surface.selected` 底在上面对比很弱，主要靠文字识别。可接受；如嫌弱，可改为白底胶囊（新视觉决定，需批准）。
- **不变量**：DTO 不含身体数据（自动，沿用 M1B-FR-030 测试）；卡片区块与总结页区块的行来自同一个判定结果（自动，单元测试比较两者）。

## 3. Penpot 画稿计划

「M1-B G5 Design」Foundations 页，y = 3750 一行，B-c 右侧。画板名只用「编号 + 简短标题」（负责人 2026-10-20：名字要短）；状态记在 plugin data `finecoach.status = draft` 和版本标签里。

| 画板 | 内容 |
|---|---|
| `D-a 新纪录组行` | 训练页整屏（以 P0-a2 为底）：第 2 组 122.5 kg × 6 刚确认，带「新纪录」标记和「撤销」 |
| `D-a2 新纪录局部状态` | 纪录转移到第 3 组；第一次做的动作不标记；大字体时标记换行；触感与无障碍说明 |
| `D-b 本节收获` | 训练总结整屏：新纪录 1 行、比上次进步 2 行（重量、时长）、里程碑 1 行 |
| `D-b2 本节收获状态` | 只有里程碑；三类都没有时区块不出现 |
| `D-c 分享开关` | 分享设置整屏（以 D7a 为底）：开关改名「本节收获」，单行，提示在右 |
| `D-c2 开关提示与卡片` | 开关行一种状态＋两行规则说明（取前两项；三类都没有时整行不出现）；报告卡片「本节收获」区块（含进步、里程碑） |

Penpot 版本：`before-stage-D 2026-10-20` → `stage-D boards D-a D-a2 D-b D-b2 D-c D-c2 (pending approval) 2026-10-20` → `before-stage-D share 本节收获 2026-10-20` → `stage-D share 本节收获 D-c D-c2 (pending approval) 2026-10-20`（D-c、D-c2 按 spec 1.1 重画）→ `before-stage-D D-c2 compact states 2026-10-20` → `stage-D D-c2 note wording 2026-10-20`（D-c2 状态区收成两行加说明）→ `before-stage-D D-c2 hide empty row 2026-10-20` → `stage-D D-c2 hide empty row (pending approval) 2026-10-20`（去掉不可用状态）→ `before-stage-D card sticker 2026-10-20` → `stage-D card sticker placeholder + badge (pending approval) 2026-10-20` → `stage-D card padding 2026-10-20` → `before-stage-D sticker import 2026-10-20` → `stage-D card mascot sticker (pending approval) 2026-10-20`；`validate()` 0 错误。D-a、D-a2、D-b、D-b2、D-c、D-c2 均用 MCP `export_shape`（1×）导出看过渲染，未见文字变形。2× 定稿导出等批准后进行。

## 4. 执行记录（五行，实施时填写）

```text
分类和依据：D-a/D-b/D-c 均为 B；目标设计有变化；依据 spec 004 与本文 §1。
范围：DS-SET-ROW 扩展；总结页、分享页组合；受影响使用方见 §2。
设计决定：D-a～D-c2 已于 2026-10-20 批准；Revision 1.4 与 plan §3.8 已于 2026-10-21 确认（任务说明）。本轮执行已批准的 B 类扩展，不改 Penpot。
实现和检查：（待实施）
结果：（待实施）
```

## 5. 入口与布局清单（`components.md` §1.4，实施时填写）

每条新交互一行：画面 → 控件 → accessibility identifier → 是否改数据 → 宽度由谁撑满。每行必须指向真实代码。

| 画面 | 控件 | identifier | 改数据 | 宽度 |
|---|---|---|---|---|
| （待实施） | | | | |

### Phase 1

- 初始审计：产品仓与 specs 仓均干净（tracked/staged/untracked 均无）；specs 在 main，仅按任务授权修改 tasks.md，不提交。
- 实现和检查：T001–T003 已实现；本阶段无新交互。新纪录文字键随组件加入，保证组件可独立使用。
- 结果：PASS。strict lint、iphoneos Debug App build、Simulator build-for-testing 通过；FineCoachTests 508 项 / 507 passed / 1 既有 WCAG exemption skipped / 0 failed；FineCoachIntegrationTests 188 / 188 passed / 0 failed。日志：`DerivedData/StageD/evidence/phase1/{lint,app-build,build-for-testing,unit,integration}.log`。未经人工视觉检查。
