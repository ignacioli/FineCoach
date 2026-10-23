# FineCoach 设计系统（G5「暖炭黑素雅」）

> 状态：v1.0（2026-09-22 产品负责人批准）。修订历史：v0.2 按产品负责人决定修复了评分卡的定量扣分项（O1/O2/O3/O5、C10），全部待确认项已关闭；v0.3 已把全部画稿修改回填到 Penpot 源文件，并在本仓库重新导出 17 屏（§1.1）。
> 作用：FineCoach iOS 界面视觉的**唯一实现依据**。后续 spec / plan / tasks 与代码（`ios/FineCoachApp/DesignSystem/`）都引用本文，不再各自转述设计数值。
> 组件结构（anatomy、变体、状态、不变量、代码映射）与视觉工作流见 [`components.md`](components.md)；数值仍以本文为准。

## 1. 权威来源与优先级

本设计系统逐项提取自已批准的 M1-B 高保真设计（12 维评分卡 88/100）。提取方式是通过 Penpot MCP 直接读取源文件的 token、图层几何与文字样式，不是看截图估值。

| 优先级 | 来源 | 说明 |
|---|---|---|
| 1 | 器材图标 SVG：`design/m1-b-hifi/icons/*.svg`（App 内副本：`ios/FineCoachApp/Resources/Assets.xcassets/equipment-*.imageset`） | 重新绘制后的定稿版本，**优先于**任何屏幕里的图标画法 |
| 2 | Penpot 文件「M1-B G5 Design」的 17 屏画稿（`01 今日` … `17 器材 icon 库`） | 除器材图标外，一切视觉以画稿为准 |
| 3 | 同一文件的 token 集 `FC Primitives`（回填后 25）+ `FC Semantic Color`（回填后 17）与 Foundations 样张 | 画稿没有覆盖的地方以 token 和样张为准 |
| 4 | `design/m1-b-hifi/screens/*.png`（§1.1）、`design/m1-b-hifi/README.md`、[`design/12d-visual-scorecard.md`](../12d-visual-scorecard.md) | 导出物、设计过程说明与评分卡，与上面各项冲突时以上面为准。这些物料 2026-09-22 前存放在私有 specs 仓，已全部迁入本仓库；specs 仓只保留设计 discovery 证据（`design/prototypes/evidence/`） |

各来源之间的冲突和裁决见 §10「来源冲突裁决记录」。

**修复原则**（产品负责人，2026-09-22）：以 12 维评分卡为质量标准。字号、对比度等可以定量判断的扣分项，即使肉眼看不出问题，也要在设计系统层面修复。每一处修复都登记在 §10，注明原值，并回填到 Penpot 源文件，让设计源、导出图和本文保持一致。

### 1.1 Penpot 回填与导出记录（2026-09-22）

- Penpot 版本快照：改动前 `before-design-system-v0.2-backfill 2026-09-22`（revn 103），改动后 `design-system-v0.2-backfill 2026-09-22 (O1 O2 O3 O4 C1 C2 C5 C6 C7 C10, icons)`（revn 111）。`File.validate()` 报告 0 个错误。
- 回填内容：
  - token：`color.red.700` 改为 `#D4442A`；新增 `color.neutral.500`、`color.border.control`、`color.surface.page`、`color.text.onActionSecondary`。
  - 画稿：O1（08）、O2（11、13）、O3（08）、O4（11）、C10（01、15）。
  - 图标：17 屏 15 个图标和 11 屏 2 个图标换成 `icons/` 目录的重绘版。
  - Foundations 样张：C1、C2、C5、C6、C7，并在色板中新增 `border.control`。
- 导出：本仓库 `design/m1-b-hifi/screens/`，文件名沿用旧版（`01-today.png` … `17-icons.png`）。2 倍图，01–16 为 780×1688，17 为 1120×1200（2026-09-23 新增一行 3 个图标后重新导出，原为 1120×1040）。04、06、07、08、12 这 5 块画板上的展示投影在导出时临时去掉、导出后立即恢复，所以导出图不含投影边距。

### 1.2 T063 审核后的新增画稿（D1–D9，2026-09-26 产品负责人批准）

Phase 6.5 人工审核（T063）发现 8 个核心界面需要结构调整，并提出 D1–D9 新增设计需求（`specs/002-m1-b-coach-operations/checklists/design-review-8-screens.md`）。初稿在 Penpot「M1-B G5 Design」Foundations 页右侧绘制，经产品负责人 2026-09-26 审稿修改后批准：

- 快照：`before-D1-D9-drafts 2026-09-26` → `D1-D9-drafts 2026-09-26 (pending approval)` → `D1-D9-drafts r2 …` → `D1-D9 approved 2026-09-26 (D8 variant B)`。
- 导出：`design/m1-b-hifi/screens/18`–`32`（2 倍图）；2026-09-27 补 `33`、`34` 并重新导出 `20`（Penpot 快照 `before-T069c-filter-sheet 2026-09-27` → `T069c library filter + options sheets 2026-09-27 …`，画板 D2c、D2d）；2026-09-28 按 T069j 重新导出 `28`、`29`（快照 `before-T069j-share-settings 2026-09-28` → `T069j share settings: …`）；2026-09-28 按 T069i 审核重新导出 `32`（画板 D9 加入比较选择、相同动作明细、个人最佳日期与次数；快照 `before-T069i-review 2026-09-28` → `T069i review: …`）。**新画稿取代原画稿中的对应界面**：

| 新画稿 | 需求 | 取代 / 补充 |
|---|---|---|
| `18-course-action-sheet` | D1 课程操作面板；日历入口放在「今日」标题行右侧 | 补充 01 |
| `19-resource-hub`、`20-exercise-library` | D2 资料库入口页、动作库列表 | 新增 |
| `21-student-list-v2`、`22-archived-students` | D3 资料库入口、训练中提示条、「已归档 · N ›」、已归档列表 | 取代 10 |
| `23-new-appointment-v2`、`24-edit-occurrence-scope` | D4 重复规则（不重复 / 每隔一天 / 每隔两天 / 每隔一周）、训练重点部位多选、改期范围 | 取代 02 |
| `25-calendar-v2` | D5 有课日期圆点；课程行整行可点 | 取代 03 |
| `26-student-detail`、`27-edit-profile` | D6 学员详情页；归档与永久删除移到编辑资料页 | 新增 |
| `28-share-settings-v2`、`29-share-preview` | D7 分享报告设置页（单次训练）与预览页。走查修订 2026-10-22（C15）：预览页卡片之后常驻整宽次按钮「完成」，点了回到今日页（Penpot `D7b-r`） | 取代 12 |
| `30-training-v2`、`31-add-exercise-sheet` | D8 方案 B：「＋ 新建分区」就地入口；「应用模板」并入添加动作面板；「另存为模板」移到训练结束后的总结页 | 取代 11 |
| `32-training-history-v2` | D9 训练历史筛选结果列表 | 取代 07 |
| `33-exercise-filter-sheet`、`34-exercise-options-sheet` | T069c（2026-09-27 产品负责人选定「筛选面板」方案）：动作库搜索框右侧筛选图标 → 筛选面板（器械、显示已隐藏）；点动作行 → 动作选项面板（收藏 / 隐藏 / 辅助器械）。`20-exercise-library` 同步加上筛选图标并重新导出 | 补充 20 |
| `35-session-detail` | D12 训练记录（训练历史 → 点日期行；页头 2026-10-23 改为行内 `‹` + 页面内「训练记录」，§10 C18）：复用 `29-share-preview` 的分区（日期 / 标题 / 学员、三项统计、训练部位、动作每行 3 组、课后总结），不带页脚；下方「编辑训练重点 ›」「另存为模板 ›」操作行（另存为模板用底部面板命名）、只读说明，底部固定「生成训练报告」（2026-09-28 产品负责人反馈原页面像表格、字体不齐） | 补充 32 |
| `36-new-package-stepper`、`37-manual-adjustment-stepper` | D13 数字步进器（2026-09-29 产品负责人批准方案 C「整体胶囊」，T064 发现新建课包「总课时数」与人工调整「课时数」仍为 iOS 系统 `Stepper`）；两页页头同时改为 `‹` + 页面内 `titleLarge`（与 04、训练趋势一致）。新建课包的开始 / 结束日期行与 02 相同：标签-值两栏行，值为 `body`「yyyy年M月d日」（课包有效期可能跨年，保留年份）+ `›`，点行在下方展开日历（2026-09-29 产品负责人审核时要求，快照 `D13a date row as 02 (value + ›) 2026-09-29`）。Penpot 快照 `before-D13-stepper 2026-09-29` → `D13 stepper capsule (option C) 2026-09-29`，画板 D13a、D13b | 新增 |
| `38-backup-restore-v2` | D14 备份与恢复 v2（T071，2026-09-29）：08 原画稿把「密码 + 再次确认密码」画在「恢复」下，但设置并确认口令属于**导出**，恢复只需「选择备份文件」+ 一次口令；按功能摆放，其余照 08（页面内标题与副标题、导出 / 恢复分区与分割线、失败状态 `status.destructive` 文字 + 22×22「!」徽标 + 说明 + 居中「重试」）。恢复区直接显示，去掉原「从备份恢复」展开按钮与底部整宽「取消」（改用返回）。说明文字 `caption`，口令框为输入框（08）的遮蔽输入。快照 `before-T071-backup-v2 2026-09-29` → `T071 backup-restore v2 (D14) 2026-09-29` | 取代 08 |
| `40-today-header`、`41-student-list-header`、`42-settings`、`43-settings-notification-denied`，并重新导出 `19-resource-hub` | D15 设置页与页头入口（2026-09-29 产品负责人批准，T079 起）：CoachOps 缺一个设置页，通知权限被拒后没有「前往系统设置」出口（M1B-FR-009）。今日页头右侧从左到右为「＋ 新建预约、日历、设置」，学员页头为「资料库、设置」；设置页三行：通知（副标题「提醒已开启」；被拒绝时为状态标签 + 「前往设置」，点击打开系统设置）、备份与恢复（副标题「上次备份 …」，入口从资料库移到这里）、关于（版本号，无 `›`）；资料库只保留动作库与模板，说明文字同步去掉「备份」 | 补充 01、21；修改 19 |
| `39-backup-restore-success` | D14b 恢复完成状态（T072，产品负责人 2026-09-29）：恢复成功后在「恢复」按钮下方就地显示，与失败状态对称——22×22 `action.primary` 圆底白色 ✓ 徽标（信息性状态，§7.2）+「恢复完成」`callout` 600 `text.primary` + `caption` `text.secondary`「本机数据已替换为备份中的版本。请到学员、课包、模板等页面检查数据是否正确。」；只有文字提示，不加跳转链接。快照 `before-T072-restore-success 2026-09-29` → `T072 restore success state (D14b) 2026-09-29` | 补充 38 |

新画稿中训练重点一律显示部位名（如「大腿、臀」），对应 spec Revision 1.2 的 M1B-FR-033。

### 1.3 组件规格回填 Penpot（2026-10-05）

- 快照：`before-component-spec-backfill 2026-10-05`（revn 179）→ `component-spec-backfill 2026-10-05 (DS-* layer names + plugin data, deprecated CG-2 comments)`（revn 180）。`File.validate()` 0 个错误。
- 内容：按 [`components.md`](components.md) 的组件 ID，用几何与填色特征（取自本文 §8）识别 43 块画板中的组件，730 个图层写入 shared plugin data（namespace `finecoach`：`component` / `part` / `spec` / `status`），其中 168 个原名为 `Rectangle` / `Ellipse` 等的图层改名为「DS-xxx · 部件」；02、15 画板的废弃设计加评论；「01 今日」上方加一条说明评论。
- 只改图层名、元数据和评论，不改任何视觉，因此不重新导出 `screens/*.png`。
- 未自动标注的组件（结构无法靠单个图层的几何可靠识别）：`DS-TITLE-ACTION`、`DS-ACTION-ROW`、`DS-LABEL-VALUE-ROW`、`DS-SYMBOL`、`DS-EQUIPMENT-ICON`、`DS-BODY-DIAGRAM`，以及页面组合模式 `DS-HUB-ROW`、`DS-INLINE-RESULT`、`DS-EMPTY-STATE`；`DS-SAVE-STATUS` 没有画稿。

### 1.4 M2 G7 设计载体（2026-10-08 绘制，2026-10-09 产品负责人批准）

- 同一 Penpot 文件新增页面「M2 G7 Design」，26 块画板（`M2-01` … `M2-20`）。快照：`before-M2-G7-design 2026-10-08`（revn 181）→ `M2-G7-design-draft r2 2026-10-08 (26 boards; …)`（revn 200）→ `M2-G7-design r3 2026-10-09 (review round 1: …)`，每次 `File.validate()` 0 个错误。Foundations 页没有改动。
- 画板图层按 §1.3 方式标注（图层名 + shared plugin data `finecoach.component` / `part`）；新组件用 `components.md` §4.7 的 ID，feature 专有组件用 `design/m2-hifi/implementation-map.md` 的 ID。
- 导出：`design/m2-hifi/screens/`，2 倍图（宽 780），2026-10-09 用画板上的 2 倍导出预设从 Penpot 批量导出。
- 2026-10-09 产品负责人 review 通过（G7 整体通过），核心页面 M2-02、M2-11。新的视觉决定（实施映射 §2）以 `components.md` §4.7 与实施映射为准；本文 §2–§9 的数值不变，没有新增 token。

### 1.5 P0 训练页回填（2026-10-15）

- 产品负责人 2026-10-14 已批准 Foundations 页 P0-a、P0-b。本轮只把标题从「待审」改为「已批准」，并给这两块画板上尚未标注的 `DS-*` 图层写入 shared plugin data（`finecoach.component` / `part` / `spec` / `status`）。`DS-STEPPER-FIELD` 的 spec 指向 `design/design-system/components.md`；`DS-REST-TIMER`、`DS-LAST-REF` 是 feature 专有，spec 指向 `design/experience-p0/implementation-map.md`。
- 快照：`before-P0-approved-sync 2026-10-15` → `P0-a P0-b approved 2026-10-14 (titles, DS plugin data)`（revn 320）。`File.validate()` 0 个错误。
- 两块画板没有展示投影，已有 2 倍 PNG 导出预设。没有重新导出 04、06、07、08、12。没有改任何几何或颜色。

### 1.6 W-08 多人训练 hero 卡（2026-10-22）

- 产品负责人 2026-10-22 选定方案 A（一张 hero 卡多行，§10 C14）。分类 B：修订已批准的 01 今日页 hero 卡。
- Penpot：Foundations 页 y=3750 一行末尾（x=11770，D-c2 右侧）新增画板「W08-a 今日 · 多人训练 hero（方案 A，2026-10-22）」，含 1 人 / 2 人 / 3 人三种状态。之前：该位置为空；之后：画板 390×772，字号、颜色取自 01 hero 卡原图层。
- 已知差异（本轮不处理，记录待查）：01 原图层的副文字是 13/400（`caption`），本文件 §8 和 `components.md` 写的是 `callout`。W08-a 照 01 原图层画；代码实现时副文字沿用 `FCHeroCard` 现有样式，不在本轮改。
- 导出：`design/w08-concurrent-sessions/W08-a-today-multi-hero@1x.png`（MCP 1x 参考图；2x 正式导出待做）。

### 1.7 分享预览「完成」（2026-10-22）

- 产品负责人 2026-10-22 选定（§10 C15）。分类 B：在已批准的 29 预览页上新增控件；组件复用 `DS-BUTTON` 次按钮，不新建。
- Penpot：Foundations 页 y=3750 一行末尾（x=12210，W08-a 右侧）新增画板「D7b-r 分享预览 · 底部「完成」（走查修订 2026-10-22）」，含未分享、已交给系统、取消或失败三种状态。D7b 原画板不改。快照 `before-share-done 2026-10-22` → `share-done D7b-r 2026-10-22`。
- 导出：`design/walkthrough-2026-10-22/D7b-r-share-preview-done@1x.png`（MCP 1x 参考图）。

### 1.8 阶段 D 新纪录与比上次进步重新定义（2026-10-23）

- 产品负责人 2026-10-23 裁定（§10 C16；specs 004 Revision 1.5）。分类 B：修订已批准的 D-a2、D-b、D-c2 画稿；组件全部复用（`FCListRow`、`FCNewRecordBadge`），不新建，不加 token。
- Penpot（Foundations 页）：快照 `before-gains-redefine 2026-10-23` → `gains-redefine D-a2 D-b D-c2 2026-10-23` → `… (fix)`。
  - D-b：深蹲由新纪录行改为动作行，副标题「上次 120 kg × 8 → 本次 125 kg × 5」，「新纪录」胶囊放在「深蹲」后；删去右侧「125 kg」「125 kg × 5」数值。
  - D-c2：卡片深蹲行同样改为「上次 → 本次」，删去右侧「125 kg × 5」。
  - D-a2：新增「⑤ 判定口径（2026-10-23 修订）」六行说明，画板高 772。
  - D-a 不改。
- 导出：三块画板均以 MCP 1x 导出看过（未入库）；2x 正式导出与其他 D 画板一并待做。
- 代码已按新口径修改（分支 `fix/gains-redefine`，2026-10-23）：`SessionGains` 主指标判定、每个动作一行、`DS-LIST-ROW` 新增新纪录胶囊 slot；确认触感改由训练页级确认事件触发（修复真机走查 D1/D2 无触感）。执行记录见 `design/progress-milestones/implementation-map.md` §4 Phase 7。

### 1.9 新纪录数值浮起与动效 token（2026-10-23）

- 产品负责人 2026-10-23 裁定（§10 C17；specs 004 Revision 1.6）。分类 B：修订已批准的 `DS-SET-ROW` 交互（D-a、D-a2）；新增 §14 动效与触感 token。
- Penpot（Foundations 页）：快照 `before-record-float 2026-10-23` → `record-float D-a3 + D-a2 haptic note 2026-10-23`。
  - 新增画板「D-a3 新纪录浮起（关键帧，2026-10-23）」，x=12650、y=3750（D7b-r 右侧）：0.1 / 0.3 / 0.6 s 三帧、参数标注、真机试选 A/B/C。
  - D-a2 ④ 触感说明改为「确认一组统一 light 触感；破纪录另有数字浮起，见 D-a3。」
- 导出：`design/progress-milestones/D-a3-record-float@1x.png`（MCP 1x 参考图）。
- 代码已实现（分支 `fix/record-float-motion`，2026-10-23）：`FCMotion` / `FCHaptic`（`ios/FineCoachApp/DesignSystem/FCMotion.swift`，internal：是 token 不是组件，不进 `components.md` §3 索引）；`DS-SET-ROW` 数值浮起；训练页、组圆圈、步进器迁移到 token；DEBUG 动效试验页。开发版试验页候选 A 8pt/0.5 s、B 12pt/0.6 s、C 16pt/0.8 s，负责人真机试后另加 D 档。执行记录见 `design/progress-milestones/implementation-map.md` §4 Phase 8。
- **已选定 D 档**（产品负责人 2026-10-23 真机试过 B、C 与 D 24pt/1 s 后定为 24pt / 1.5 s，「12pt / 0.6 s 太克制，氛围感不足」；数字浮起时略压到上一组可以接受，反正会渐隐）：浮起距离 `space.6`（24pt），`motion.duration.emphasis` 0.6 s → 1.5 s，已写回 §14 并更新 Penpot D-a3（快照 `before-record-float D tier 2026-10-23` → `record-float D tier 24pt 1.5s 2026-10-23`，重新导出 `D-a3-record-float@1x.png`；分支 `fix/motion-lab-option-d`）。

## 2. 颜色

### 2.1 原子色（FC Primitives）

| Token | 值 | 备注 |
|---|---|---|
| `color.brand.primary` | `#2A2822` | 暖炭黑，主操作色 |
| `color.brand.pressed` | `#1F1E1B` | 主操作按下态 |
| `color.brand.subtle` | `#EDE9E2` | 米色 tint |
| `color.brand.on` | `#FFFFFF` | 主操作色上的文字/图标 |
| `color.neutral.0` | `#FFFFFF` | |
| `color.neutral.50` | `#F7F4EE` | |
| `color.neutral.100` | `#F0EEE9` | |
| `color.neutral.200` | `#ECE9E2` | |
| `color.neutral.400` | `#A8A39A` | |
| `color.neutral.500` | `#8E897F` | O2 新增，已回填 Penpot |
| `color.neutral.600` | `#5C5A52` | |
| `color.neutral.900` | `#211F1B` | |
| `color.green.600` | `#2A2822` | 名字叫 green，值是炭黑（设计刻意统一状态图标颜色，见 README 优化项 3） |
| `color.amber.700` | `#B45309` | |
| `color.red.700` | `#D4442A` | 原值 `#D9563E`，为达到 4.5:1 压暗（O1），已回填 Penpot |

### 2.2 语义色（FC Semantic Color + 画稿补充）

| 语义 Token | 引用 | 值 | 画稿中的实际用途 |
|---|---|---|---|
| `color.action.primary` | brand.primary | `#2A2822` | 主按钮底、选中胶囊、深色 hero 卡、开关开启、已完成圆圈；链接式按钮文字（「＋ 添加动作」「重试」）；大标题文字（见 §3.3） |
| `color.action.pressed` | brand.pressed | `#1F1E1B` | 主操作按下态 |
| `color.action.on` | brand.on | `#FFFFFF` | 深底上的文字 |
| `color.surface.page` | neutral.0 | `#FFFFFF` | **页面底色**（17 屏全部为白底），弹窗底 |
| `color.surface.elevated` | neutral.0 | `#FFFFFF` | 弹窗 / 浮层 |
| `color.surface.canvas` | neutral.50 | `#F7F4EE` | **仅小面积填充**：搜索框底（10）、输入框底（08，O3）、深色 hero 上的徽标底（01） |
| `color.surface.subtle` | neutral.100 | `#F0EEE9` | 画稿未使用，保留 |
| `color.surface.divider` | neutral.200 | `#ECE9E2` | 1pt 分割线、关闭态开关底（仅作装饰，不作为唯一可辨识的控件边界） |
| `color.border.control` | neutral.500 | `#8E897F` | 可交互控件的描边：待完成组圆圈（O2）、关闭态开关轨道外圈（O7）；对白底 3.48:1。画稿原用 `#ECE9E2` |
| `color.surface.selected` | brand.subtle | `#EDE9E2` | 未选中的二选一/胶囊底、头像底、提示条底、弹窗次按钮底 |
| `color.text.primary` | neutral.900 | `#211F1B` | 正文、列表主文字、数值 |
| `color.text.secondary` | neutral.600 | `#5C5A52` | 辅助文字、字段标签、区段标签、箭头 |
| `color.text.disabled` | neutral.400 | `#A8A39A` | 画稿未使用，保留给禁用态 |
| `color.text.onActionSecondary` | —（画稿补充） | `#B0ABA2` | 深色 hero 卡内的次要文字（01「已训练 32 分钟」）。原不在 Penpot token 集中，已按画稿补入 |
| `color.surface.dividerOnAction` | —（2026-10-22 新增） | `#4C4A45` | 深色 hero 卡多行变体的行间 1pt 分割线（白色 16% 叠在 `action.primary` 上的不透明等值）。仅作装饰，不作为控件边界 |
| `color.status.success` | green.600 | `#2A2822` | 成功/完成状态 |
| `color.status.warning` | amber.700 | `#B45309` | 逾期、时间冲突图标底 |
| `color.status.destructive` | red.700 | `#D4442A` | 失败、破坏性操作文字（O1） |
| `color.overlay.scrim` | text.primary 40% 不透明度 | `#211F1B` @ 40% | 底部面板与弹窗背后的遮罩（D1、D4b、D8c）。2026-09-26 产品负责人批准新增 |

### 2.3 插图专用色

- `#E08A5C`（橙）只存在于吉祥物插图内部。Penpot token 集和 17 屏界面元素都**没有**使用它。**界面元素不得使用橙色。**

### 2.4 用色规则（评分卡维度 1、5）

- 约 60% 中性暖灰、30% 白/浅色面、10% 强调色。不使用饱和高亮色。
- 大面积强调只能用深色（`action.primary`）或中性色。tint 只用于小面积。**每屏最多一个深色 hero 面板。**
- 状态必须同时用文字和图标表达，不能只靠颜色（09 屏）。

## 3. 排版

### 3.1 字体

- 字体家族：**Noto Sans SC**（全部 428 个文字图层）。随 App 打包，使用 SIL OFL 1.1 许可。
- 需要的字重：400 Regular / 500 Medium / 600 SemiBold / 700 Bold。
- 打包方式（产品负责人 2026-09-22）：**官方可变字体单文件 `NotoSansSC-VF.otf`（notofonts/noto-cjk，约 15.1 MB），完整字表，不做子集化**。一个文件覆盖全部字重，且任何学员姓名都不会回退系统字体。官方静态字重没有 SemiBold 600，所以不采用静态字重方案；子集化只作为最后备选。MiSans 因许可协议禁止单独分发副本和改编而排除。
- 字距一律为 0。
- 动态字体（Dynamic Type）：每个样式必须随系统字体放大而缩放（09 屏「支持系统字体放大」）。实现上，每个样式绑定下表给出的「缩放基准」文本样式。

### 3.2 阶梯（7 级，来自 Foundations 样张）

| 样式 | 字号 / 字重 | 行高 | 允许的字重变体（画稿实测） | 缩放基准 | 画稿用途 |
|---|---|---|---|---|---|
| `display` | 34 / 700 | 1.2 | — | largeTitle | 一级页面大标题：今日、学员（01/10/16） |
| `titleLarge` | 28 / 700 | 1.3 | — | title1 | 二级页面标题：新建课程安排、课包详情等（02–09、12） |
| `title` | 22 / 600 | 1.3 | 700 → `titleEmphasis` | title2 | 下一节课时间（01） |
| `headline` | 17 / 600 | 1.4 | — | headline | 列表主标题、学员名、卡片标题、弹窗标题、按钮文字 |
| `body` | 17 / 400 | 1.4 | — | body | 字段值、列表正文、组行 |
| `callout` | 15 / 500 | 1.4 | 400、600 | callout | 400：字段标签、副标题、日期；600：时间、链接按钮、弹窗按钮、失败标题 |
| `caption` | 13 / 400 | 1.3 | 600 → `sectionLabel` | footnote | 元信息、单位、状态文字、说明 |

`body` 行高取画稿实测的 1.4（44 处）；Foundations 样张写的是 1.5（1 处）。见 §10。

### 3.3 具名例外（画稿中反复出现、阶梯外的字号）

| 样式 | 字号 / 字重 | 行高 | 缩放基准 | 画稿用途 |
|---|---|---|---|---|
| `numeralHero` | 44 / 700 | 1.1 | largeTitle | 课包剩余课时大数字（04） |
| `numeralLarge` | 24 / 600 | 1.2 | title2 | 身体数据数值（06）、有氧录入数值（15） |
| `titleEmphasis` | 22 / 700 | 1.3 | title2 | 训练中页面标题「训练中」（11/13/14/15）、个人最佳数值（07） |
| `exerciseTitle` | 20 / 700 | 1.3 | title3 | 训练中的动作名（11/13/14/15） |
| `sectionLabel` | 13 / 600 | 1.3 | footnote | 区段标签：下一节课、基本指标、包含内容（`text.secondary`）；星期表头；状态徽标「进行中」（01，画稿 12/600，C10） |
| `compact` | 14 / 400 | 1.2 | subheadline | 月历日期数字（03），选中/今天用 600 |
| `chipLabel` | 14 / 500 | 1.3 | subheadline | 胶囊、分段按钮文字（02 星期、07 筛选） |

零散用法的归并：
- 头像首字 18/600（10）→ 归入 `headline`。
- 12 号字不在评分卡字号阶梯内，一律升到 13（C10）：「进行中」12/600 → `sectionLabel`；「必填 / 选填」12/400（15）→ `caption`。
- `‹ › − + ✓ ▾` 等字符在画稿里是文字图层，实现时作为图标处理，见 §7.2。

### 3.4 文字颜色规则

- 页面大标题 `display` 在画稿中用 `action.primary #2A2822`（3/3 处）；其余标题用 `text.primary`。
- 次要文字一律 `text.secondary`。深色面上的文字用 `action.on`，次要文字用 `text.onActionSecondary`。
- 层级靠字号和字重区分，不靠颜色（评分卡维度 3）。

## 4. 间距

| Token | 值 |
|---|---|
| `space.1` | 4 |
| `space.2` | 8 |
| `space.3` | 12 |
| `space.4` | 16 |
| `space.6` | 24 |
| `space.8` | 32 |

规则：
- 只允许使用上表中的值。README 写的是「4/8/16/24/32」，token 集中还有 12，以 token 集为准。
- `0` 表示「不留空隙」（如 `VStack(spacing: 0)` 让列表行紧挨，行间只靠分割线），不是刻度值，允许直接写 `0`，设计值扫描（T062）不计为违规（产品负责人 2026-09-28，T068）。
- 页面左右边距 = `space.4`（16）：画稿中 215 个元素的左边距是 16，内容宽度 358（屏幕 390）。
- 底部主按钮距屏幕底边 32（`space.8`），画稿中按钮位于 y=760、高 52。
- 区块之间的间距要大于行内间距（评分卡维度 4）。
- 画稿用绝对定位，没有使用自动布局，卡片间距实测有 25/27/47 等非刻度值。实现时统一归到最近的刻度值，不照抄。

## 5. 圆角

| Token | 值 | 画稿用途 |
|---|---|---|
| `radius.sm` | 8 | 搜索框（10）、密码输入框（08） |
| `radius.md` | 12 | 主按钮 358×52、提示条 358×44、44×44 触控示例 |
| `radius.lg` | 16 | 深色 hero 卡（01）、弹窗（14 屏 300×150，样张 320×168） |
| `radius.xl` | 20 | 画稿未使用，保留 |
| `radius.capsule` | 高度 / 2 | 胶囊、分段按钮、徽标、开关（画稿中 9/12/13/14/15/16 这些值全部等于高度的一半） |
| `radius.dialogAction` | 10 | 弹窗内的按钮（36 高）。不在 8/12/16/20 刻度内，但画稿（14 屏 2 处 + 样张 8 处）一致使用，按画稿登记 |

## 6. 表面、描边与层级

- **无阴影**：画稿中组件没有任何阴影。部分画板上的 4/4/4 黑色 20% 投影只是 Penpot 画板的展示效果，不属于产品。
- 层级靠底色、分割线和深色 hero 区分。
- 分割线：1pt，`surface.divider`（画稿中有 56 处）。
- 描边：
  - 待完成组圆圈 22×22：1.5pt `border.control`（画稿原为 `surface.divider`，O2）
  - 草稿组圆圈：1pt `text.secondary`（画稿画为虚线圆，11 屏）
  - 已完成组圆圈：`action.primary` 实心，内含白色 ✓
  - 次按钮（样张）：白底，1.5pt `action.primary` 描边，圆角 12

## 7. 图标

### 7.1 器材图标（权威：`design/m1-b-hifi/icons/`）

- 共 21 个：barbell、bike、bodyweight、cable-crossover、cable-machine、dumbbell、hack-squat、jump-rope、kettlebell、pec-deck、resistance-band、rowing-machine、shoulder-press、smith-machine、treadmill，以及 2026-09-23 为 T065 新增的 leg-extension（腿屈伸）、hip-adduction（髋内收/外展一体机）、tbar-row（胸托 T 杠划船）。T065 新增的 3 个已回填 Penpot「17 器材 icon 库」画板（快照 `before-T065-icons 2026-09-23` → `T065-icons 2026-09-23 (…)`）。
- 规格：viewBox 24、描边 2、圆角端点与圆角转角、无填充、描边色 `#2A2822`；例外：kettlebell 铃身为实心填充 `#2A2822`（CX-D13，2026-10-19）。
- 前 15 个已导入 `ios/FineCoachApp/Resources/Assets.xcassets/equipment-*.imageset`（2026-09-22 核对，与原件逐字节一致），并设置为 template 渲染，着色用 `action.primary`；新增 3 个在 T065 实现时导入。
- 2026-10-19 C′ 2b 新增 plate-loaded（悍马机）、suspension-trainer（悬挂带）、pull-up-bar（单杠），导入 3 个、替换 5 个（barbell、dumbbell、pec-deck、kettlebell、cable-crossover）；所有 imageset 与原件逐字节一致。`extras/` 为备选，不进图标库。Penpot「17 器材 icon 库」由 Claude 同轮回填。
- **动作 → 图标对应（产品负责人 2026-09-23 T065；2026-10-19 C′ 2b 扩展）**：按动作库的 `equipmentClass` 对应；`固定器械` 再按 `primaryMuscleGroup` 细分。**没有对应图标的动作不显示图标（留空），不用默认图标补位。**

  | 器材类别 | 主练部位 | 图标 |
  |---|---|---|
  | 杠铃 | 任意 | barbell |
  | 哑铃 | 任意 | dumbbell |
  | 徒手 | 任意 | bodyweight |
  | 绳索 | 任意 | cable-crossover |
  | 史密斯机 | 任意 | smith-machine |
  | 壶铃 | 任意 | kettlebell |
  | 哈克机 | 任意 | hack-squat |
  | 悍马机 | 任意 | plate-loaded |
  | 悬挂带 | 任意 | suspension-trainer |
  | 单杠 | 任意 | pull-up-bar |
  | 弹力带 | 任意 | resistance-band |
  | 固定器械 | 胸 | pec-deck |
  | 固定器械 | 肩 | shoulder-press |
  | 固定器械 | 大腿 | leg-extension |
  | 固定器械 | 臀 | hip-adduction |
  | 固定器械 | 小腿 | hack-squat |
  | 固定器械 | 背 | tbar-row |
  | 固定器械 | 臂、核心 | 留空 |
  | 其他 | 任意 | 留空 |
  | 自定义动作 | — | 留空 |

  bike、treadmill、rowing-machine、jump-rope、cable-machine 目前没有对应的器材类别，暂不使用。
- 用途：动作库、训练中动作行。11 屏的动作行图标为 24×24，位于左边距 16 处，动作名右移到 x=48（O4）。
- 展示尺寸：24 画布下描边 2；放大显示时描边按比例放大（17 屏 36×36 的描边为 3）。

### 7.2 系统图标

画稿中用文字字符表示的图标。**`‹ › ✓` 实现为随 App 打包的 Noto Sans SC 字形**（产品负责人 2026-10-10，T038 走查：SF Symbols 的通用对勾 / 箭头不是画稿的字形，被否决），字号、字重、颜色按下表，随动态字体缩放（`FCFont.uiFont` + `UIFontMetrics`，基准 `body`）；`− + ▾` 仍用系统图标（SF Symbols；随包字体没有 `▾` 字形），颜色和视觉尺寸按画稿：

| 画稿字符 | 画稿样式 | 用途 |
|---|---|---|
| `‹` | 22/400 或 20/400，`text.secondary` | 返回（22，与页面标题同一行，见 components.md `DS-PAGE-HEADER`）、上一月（20） |
| `›` | 20/400，`text.secondary` | 列表行进入、下一月 |
| `− / +` | 20/600 | 课时扣减/返还记录 |
| `✓` | 13/600 白色（圆内）或 15/600 `action.primary` | 已完成、已包含 |
| `▾` | 15/600 `action.primary` | 分区折叠 |
| `! / i` | 14/600 白色，放在 22×22 圆内（底色 `status.warning` 或 `action.primary`） | 状态图标 |

所有可点击图标的触控区域不小于 44×44。

**状态图标对应（spec NFR-005，产品负责人 2026-09-23）**：五类状态都用「22×22 圆底 + 白色字形 + 文字」表达，不只靠颜色。实现为 `FCStatus` / `FCStatusLabel`。

| 状态 | 字形 | 圆底 | 来源 |
|---|---|---|---|
| 逾期 | `!` | `status.warning` | 09 屏画稿 |
| 时间冲突 | `!` | `status.warning` | 09 屏画稿 |
| 课包异常 | `!` | `status.warning` | 产品负责人 2026-09-23，已回填 09 屏 |
| 权限拒绝 | `i` | `action.primary` | 09 屏画稿 |
| 不可比较 | `i` | `action.primary` | 产品负责人 2026-09-23，已回填 09 屏 |

规则：需要教练处理的状态用 `status.warning` 加「!」；只是信息提示的状态用 `action.primary` 加「i」。09 屏新增的两行已回填 Penpot（快照 `before-status-mapping-09 2026-09-23` → `status-mapping-09 2026-09-23 (课包异常 !, 不可比较 i)`），并重新导出 `09-accessibility.png`（尺寸不变）。

## 8. 组件规格（来自 17 屏实测）

| 组件 | 规格 |
|---|---|
| 主按钮（页面底部） | 358×52，`radius.md`，底色 `action.primary`，按下 `action.pressed`；文字 `headline` 白色 |
| 次按钮（样张） | 白底，1.5pt `action.primary` 描边，`radius.md`；文字 `headline` `action.primary` |
| 链接式按钮 | 无底色，文字 `callout` 600 `action.primary`（例：「＋ 添加动作」「＋ 自定义指标」「重试」） |
| 顶部分段切换（今日 / 学员） | 选中项 50×32 胶囊，`action.primary` 底 + `headline` 白字；未选中项为纯文字 `body` `text.secondary`。同一外观也用于页内 2–3 个互斥短选项（37「扣减 / 返还」；趋势指标、身体数据录入单位），选项更多或文字较长时改用筛选胶囊（2026-10-05，§10 C11） |
| 筛选胶囊（07） | 高 30 胶囊；未选中 `surface.selected` 底 + `chipLabel` `text.primary`；选中 `action.primary` 底 + 白字 |
| 开关 | 44×26 胶囊，滑块 18×18 白色圆，**左关右开**（iOS 惯例，与画稿 02/12 一致）。开启：轨道 `action.primary`。关闭：轨道 `surface.divider` 底 + 1.5pt `border.control` 内描边（O7）。实现为系统原生 `Toggle` + 自定义外观样式，保留系统开关的无障碍语义；可点击区域不小于 44×44 |
| 深色 hero 卡（01） | 358×100，`radius.lg`，`action.primary` 底；内含徽标（高 24 胶囊，最小宽 56、随文字增长，`surface.canvas` 底，`sectionLabel` `action.primary` 字）、`headline` 白字标题、`text.onActionSecondary` 副文字、`callout` 600 白字操作。每屏最多一个。**多行变体（W08-a，2026-10-22）**：多名学员同时训练时仍是一张卡，徽标「进行中 · N」，每人一行（学员名 · 部位 / 已训练 N 分钟 / 「继续 ›」），行最小高 44，行间 `surface.dividerOnAction` 分割线，按开始时间升序；每行单独可点。1 人时与 01 相同 |
| 列表行 | 左 16；主文字 `headline` 或 `body`，元信息 `caption` `text.secondary`，右侧 `›`；行间用 1pt 分割线 |
| 区段标签 | `sectionLabel`，`text.secondary` |
| 头像 | 44×44 圆，`surface.selected` 底，首字 `headline` `action.primary` |
| 搜索框 | 358×40，`radius.sm`，`surface.canvas` 底，占位文字 `callout` 400 `text.secondary` |
| 输入框（08） | 358×48，`radius.sm`，`surface.canvas` 底（与搜索框一致）；占位文字 `callout` 400 `text.secondary`（对 `#F7F4EE` 6.29:1）。画稿原为白底无描边，边界不可见（O3） |
| 提示条 | 358×44，`radius.md`，`surface.selected` 底，`caption` `action.primary` 字 |
| 组状态圆圈 | 22×22，见 §6 |
| 确认弹窗 | 宽 300（屏内）/ 320（样张），`radius.lg`，白底；标题 `headline`，说明 `caption` `text.secondary`；两个 36 高按钮，`radius.dialogAction`：取消/保守选项 `surface.selected` 底 + `callout` 600 `action.primary`，确认选项 `action.primary` 底 + 白字 |
| 空态（16） | 吉祥物插图 220×220 居中 → 标题 `headline` `action.primary`「还没有学员」→ 说明 `caption` `text.secondary` → 底部主按钮「＋ 新建学员」 |
| 保存状态（训练中，无画稿） | 图标 + 文字横排，最小高 44：保存中 `arrow.triangle.2.circlepath`、已保存 `checkmark.circle`、保存失败 `exclamationmark.triangle`；文字 `body` 400；保存中 / 已保存 `text.secondary`，保存失败 `status.destructive`（图标同色）。整体读作一个无障碍元素。按 M1 已验收的实际呈现补登记，不出画稿（产品负责人 2026-10-05，§10 C12） |
| 通知预览（样张） | 36×36 圆角 9 炭黑图标；标题 `callout` 600，正文 `caption`；只写通用文案和时间，不写姓名/性别/课包 |

### 8.1 D1–D9 新增组件（2026-09-26）

| 组件 | 规格 |
|---|---|
| 底部面板（sheet） | 全宽，顶部两角 `radius.lg`，白底，背后 `overlay.scrim`；顶部居中拖动条 36×5（`surface.divider`，胶囊）；标题 `headline` 或 `title`，副标题 `callout` 400 `text.secondary`；操作行高 52，行间 1pt 分割线 |
| 操作行 | 左侧 `body` 文字；右侧可选 `caption` `text.secondary` 说明 + `›`；破坏性操作文字用 `status.destructive`，不带 `›`，点击后弹确认弹窗。破坏性操作暂不可用时文字改 `text.disabled`，右侧说明写原因（B-c「删除指标」「先清空记录才能删除」，2026-10-16） |
| 左滑删除（B-b，2026-10-16） | 列表单项的删除入口：行尾左滑露出「删除」，`status.destructive` 底 + 白字 `callout` 600，高度同行高。已完成的组不能一滑到底，必须点「删除」 |
| 删除后撤销行（B-b，2026-10-16） | 删除后原位置留一行，4 秒后消失：左侧 `body` `text.secondary`「第 1 组已删除」「10月12日 68.5 kg 已删除」，右侧「撤销」链接式按钮（`callout` 600 `action.primary`）；行高和分割线同被删的行 |
| 标题行「…」菜单（B-a / B-b，2026-10-16） | 分区标题行最右的 `ellipsis` 线性图标，`text.secondary`，点击区 ≥ 44×44，打开系统菜单；破坏性菜单项用 `status.destructive` 字，点了再弹确认弹窗 |
| 课程行（可点） | 01/03 屏的课程行整行可点，右侧状态文字后加 `›`，点击打开课程操作面板（D1）；左滑只作快捷方式 |
| 部位多选胶囊 | 8 个部位（胸、肩、背、大腿、小腿、臂、臀、核心），高 28，配色同筛选胶囊；自动换行，行距 8 |
| 月历有课圆点 | 日期数字下方 4pt 圆点，`action.primary`；选中日（实心圆）内不重复显示 |
| 训练中提示条 | 学员列表顶部，样式同提示条（`surface.selected` 底、`caption` `action.primary` 字），右侧「继续训练」`callout` 600 `action.primary` |
| 列表分组入口行 | 「已归档 · N ›」「已处理 · N ›」：`sectionLabel` `text.secondary` + 右侧 `›` |
| 标题行图标按钮 | 大标题同一行右侧，22×20 线性图标（描边 1.5，`text.secondary`），点击区 ≥ 44×44，不加底色与阴影（日历入口、资料库入口） |
| 标题行「＋」主入口（D15a，2026-09-29） | 仅今日页：无底色的 `action.primary` 加粗「＋」，18×18、线宽 2.5，点击区 ≥ 44×44（2026-09-29 产品负责人评审后由实心圆改为无底色），位于标题行图标组最左（`＋ 日历 设置`），图标中心间距 44；含义固定为「新建预约」（打开新建预约页，学员留空、日期默认今天），无障碍标签「新建预约」；不是「开始训练」，也不是学员页的「新学员」 |
| 设置入口（D15，2026-09-29） | 齿轮线性图标，规格同标题行图标按钮，放在今日页与学员页标题行最右，两页都进入同一个设置页 |
| 设置页列表行（D15c/d） | 沿用资料库入口页 `hubRow`：左 24 图标（`action.primary` 描边），标题 `headline` 600，副标题 `caption` `text.secondary`，右侧可选 `›`；通知被拒绝时副标题换成 `FCStatusLabel(.permissionDenied)`，行尾放「前往设置」`callout` 600 |
| 标签-值两栏行 | 标签 `callout` 400 `text.secondary` 在 x=16，值 `body` 在 x=112，行高 48–52，行间分割线（02 重画、学员详情资料区、编辑资料） |
| 动作库筛选入口与面板（20，2026-09-27 产品负责人批准） | 搜索框右侧放标题行图标按钮同款的筛选图标（有筛选时为实心），点击打开底部面板「筛选」：区段标签「器械」+ 筛选胶囊（全部 + 8 个器材类别，自动换行）、分割线、「显示已隐藏」行 + 开关、底部链接式按钮「完成」。主界面仍只显示部位筛选胶囊。用于保留 M1-A 的「按器械浏览」与「显示已隐藏」，不在主界面增加第二行胶囊 |
| 动作选项面板（20，2026-09-27） | 点击动作行（右侧 `›`）打开底部面板：标题为动作名，副标题同行内副文字；三行「收藏 / 隐藏 / 辅助器械」+ 开关；自定义动作多一行「编辑动作 ›」。已收藏的动作在行尾 `›` 前显示实心星标 |
| 训练历史 · 比较选择模式（32，2026-09-28 产品负责人批准） | 「N 次训练」区段标签同一行右侧放链接式按钮「选择」；进入选择模式后按钮变「完成」，结果行左侧出现组状态圆圈同款勾选圈（未选 `border.control` 描边，已选 `action.primary` 实心 + 白色 ✓），行尾 `›` 隐藏，点行为勾选；最多两条，勾第三条时替换最早勾的一条。「课程比较」标签在选择模式下显示「课程比较（已选 N / 2）」。两栏标题为静态文字「M月d日 · 部位」（不再用下拉选择器）。默认预选最新一次与部位相同的上一次 |
| 训练历史 · 个人最佳行（32，2026-09-28 产品负责人批准） | 三栏：左「动作名 `headline` / 类型 `caption` `text.secondary`」；中 `titleEmphasis` 最佳值（如「25 kg」）；右两行 `caption` `text.secondary` 右对齐：日期「9月17日」与该组「25 kg × 8 次」。最高重量取该重量下次数最多的一组，次数也相同取最近一次；时长、距离类只显示日期。区段标签「个人最佳」 |
| 训练历史 · 相同动作明细（32，2026-09-28 产品负责人批准） | 「课程比较」总计下方，区段标签「相同动作」；两次训练都有的动作（按名称，与「动作差异」口径一致）各一行：动作名 `headline` + 右侧展开/折叠符号（§7.2 `▾`，展开时朝上），行间分割线。展开后左右两栏各列该动作的已完成组，`callout` 400 `text.secondary`，连续相同的组合并为一行「25kg × 12次 · 6 组」。第一个默认展开，其余折叠；换选比较的两次训练后恢复默认 |
| 分享报告设置页（28，2026-09-28 产品负责人批准，T069j） | 自上而下：`‹` + `titleLarge`「分享报告」、副标题「学员 · M月d日 训练」；**实时缩略预览卡**（`surface.canvas` 底、`radius.lg`，内含日期、`title` 700 标题「部位训练」、三个数据、右侧白底小卡「训练部位」，右上链接「查看完整报告 ›」，随开关即时更新，点卡片等同预览）；区段「包含内容」三行「训练记录（日期、时长与部位）/ 动作与组数（含训练部位图）/ 课程总结」，右侧为组状态圆圈同款勾选圈（已选实心 + ✓，未选描边），可点击取消，切换时轻触感反馈；「个人最佳」行 + 开关（默认关闭，FR-030），本次刷新了个人最佳时左侧提示「本次刷新 N 项」（`caption` 600 `action.primary`），无刷新时开关不可用；「训练容量」行 + 开关（默认关闭，M1A-FR-036）；隐私说明：44×44 吉祥物头像（装饰，`radius.md` 圆角方形，完整显示不裁切；素材 `design/design-system/assets/mascot-avatar.png` = 产品负责人绘制的 `app-icon-02-warm.png` 整图缩为 264×264，2026-09-28）+ 锁图标 +「身体数据、伤病与联系方式 / 不会出现在报告里」（`caption` `text.secondary`）；底部主按钮「生成报告卡」 |
| 分享报告预览（29，2026-09-28 更新） | 数据行默认「总组数 / 总次数 / 分钟」；「训练容量」打开后第三项换为「总容量 kg」。副标题为学员称呼（时长移入数据行）。开启「个人最佳」时在动作列表后加「个人最佳」区（本次刷新的记录，同训练历史的行样式）。分享输出为一张 2 倍长图；报告超长（单张超过 8000 px）时按内容块（页头、数据、训练部位、每个动作、个人最佳、总结、页脚）拆成有序多张 2 倍图，动作不跨页，页脚只在最后一张，不降低清晰度（产品负责人 2026-09-29，T068） |
| 数字步进器（D13，2026-09-29 产品负责人批准，方案 C） | 行内右对齐的整体胶囊 112×36（`radius.capsule`，`surface.canvas` 底）；内含「−」数值「+」：符号按 §7.2 `− / +` 20/600 `text.primary`，数值 `numeralLarge`（24/600）`text.primary` 居中；到下限或上限时对应符号改 `text.disabled`，点击无效；每个符号的点击区 ≥ 44×44（可超出胶囊）。数值随动态字体放大时胶囊随之加宽。用于新建课包「总课时数」、人工调整「课时数」，取代 iOS 系统 `Stepper`（其灰色圆角块不在本色板内）。备选方案 A 圆钮 / B 圆角方块 / D 加号实心已比较并否决（D 违反 §2.4 深色只用于大面积重点，且两个方向本应同等）。训练页重量和次数用可输入变体（P0-a / P0-b，2026-10-14 批准）：同一胶囊填满值列、高 48；数值可点开键盘；只在到达下限时「−」变灰；键盘打开时加 1.5pt `action.primary` 内描边，「− / +」仍可点。步长由调用方决定（重量 ±2.5 kg，次数 ±1）。112×36 的整数步进和它的两个页面不变 |
| 训练趋势 · 辅助器械徽标（T068，2026-09-28，无画稿） | 胶囊，`surface.selected` 底，`sectionLabel` `status.warning` 字（原为 `status.warning` 15% 透明底，透明度调色不在 token 内） |
| 隐私遮罩（T068，2026-09-28，无画稿） | App 进入后台 / 多任务界面时的全屏遮罩用 `action.primary`（原为纯黑 `Color.black`，不在色板内） |

**导航**：画稿中一级页面（今日 / 学员）通过顶部胶囊切换，17 屏里没有底部 Tab 栏；二级页面左上角是返回 `‹` 加 `titleLarge` 标题。

## 9. 插图资产

| 资产 | 文件 | 来源核验 |
|---|---|---|
| App 图标 | `assets/app-icon-{light,dark,tinted}.png`，1024×1024 | 见 §9.2 |
| 吉祥物（空态） | `assets/mascot-empty-state.jpeg`，1024×1024 | 与 Penpot 内嵌原图 `inset-warm2.jpeg` 逐字节一致（276383 字节，SHA-256 `aca587ee…d87395b`） |
| 吉祥物贴纸「比心」（阶段 D） | `assets/mascot-heart-sticker.png`，1254×1254，RGBA 透明底 | 产品负责人 2026-10-20 用 ChatGPT image 以 `mascot-avatar`、`mascot-empty-state` 为参考生成（提示词见产品仓 `.handoff/prompt/2026-10-20-stage-d-mascot-heart-sticker-prompt.md`）：胸像，耳朵下垂，比心手势加一颗小橙色心，无道具无文字。SHA-256 `7b697f1b…09064bc24`。Penpot D-c2 内嵌 80×80 缩小版 |

吉祥物只用于空态插图，画稿显示尺寸为 220×220。例外：28 分享设置页隐私说明与 M2 首次说明页 W-01b 使用 `mascot-avatar` 头像（装饰），分别为 44×44（`radius.md`）与 64×64（`radius.lg`）；M2-07 首次启动二选一使用全身吉祥物 220×220（见 `m2-hifi/welcome-redesign.md` §2）。阶段 D：分享报告卡片「本节收获」区块的里程碑行使用 `mascot-heart-sticker` 贴纸，40×40，无底色无圆角裁切，只用于分享卡片，教练端页面不用（spec 004 D-FR-034）。贴纸内的橙色属于插图，同 §9.2 规则，不得用于界面元素。

### 9.1 训练部位示意图（D7，方案 A，2026-09-26 批准）

- 用途：分享报告预览（`29-share-preview`），展示本次训练练到的部位。
- 画法：正面 + 背面两个简化人形，由圆角矩形与椭圆组成的几何色块（产品负责人评价「柔和、简洁」）。只按 8 个部位分区：正面为肩、臂、胸、核心、大腿、小腿；背面为肩、臂、背、臀、大腿、小腿；头与骨盆为不计分区块。
- 着色：主练部位 `action.primary`；次要部位 `text.disabled`（`#A8A39A`）；其余 `surface.subtle` 填充。所有区块 1pt `border.control` 描边。图下方用两个 10pt 圆点加 `caption` 文字做图例（「主练 · …」「次要 · …」）。
- 数据：由本次训练各动作的主练部位与次要部位汇总，不新增数据；自定义动作没有部位信息，不参与着色。
- 细分肌群图不在本次范围（specs 仓 `ideas.md` §9.31）。

### 9.2 App 图标（2026-10-11 批准；2026-10-14 改版）

- 来源（2026-10-14 修订）：light 版为产品负责人绘制的 `mascot-avatar` 原稿（`app-icon-02-warm.png`，1254×1254，即 `assets/mascot-avatar.png` 的原分辨率版：吉祥物胸像加六边形徽章、记事本与笔），缩放为 1024×1024；dark 版由产品负责人用 ChatGPT image 以 light 版为版式参考重绘（深色底，夹克、徽章、笔加浅灰描边），缩放为 1024×1024；tinted 版由 dark 版去饱和得到。取代 2026-10-11 批准的无道具胸像版（该版问题：单独一只中性兔子看不出 App 用途）。小尺寸下只要求能识别「兔子教练加健身和记录」的意图，不要求看清道具细节。
- 文件：`assets/app-icon-light.png`（米色底约 `#F8F0E3`，SHA-256 `65f84996…0bd0463`）、`assets/app-icon-dark.png`（暖炭黑底约 `#1E1A17`，`14a3b703…f44f519`）、`assets/app-icon-tinted.png`（灰度，`4029ed42…97eb`）。均为满版方形、无透明通道、无圆角，圆角由 iOS 遮罩。工程内副本在 `Assets.xcassets/AppIcon.appiconset`（单张 1024 universal + dark + tinted 外观）。dark 与 light 的版式有 1–2% 的轻微错位，仅在用户切换外观的瞬间可见，已接受。
- 吉祥物插图内的橙色（§2.3）在图标中保留，仍不得用于界面元素。
- dark / tinted 只是 iOS 18 主屏图标外观，随用户在主屏「自定」中的选择切换；App 界面本身仍未适配深色模式，不因此引入界面深色主题。
- Penpot：「M1-B G5 Design」Foundations 页画板「AppIcon options (2026-10-11) — REJECTED A / B / C」底部的 `AppIcon / approved / {light,dark,tinted}` 已于 2026-10-14 回填为新三张图（快照 `before-app-icon-v2 2026-10-14` → `app-icon v2 backfill 2026-10-14 (mascot original, light/dark/tinted)`，`File.validate()` 0 个错误），并更新了画板内的「已批准」说明；上方几何兔头 / 「练」字标 / 哑铃片三案为 2026-10-11 否决方案，保留作记录。
- 验收：2026-10-14 产品负责人在真机体验，反馈审核通过（light / dark / tinted 三个外观）。

## 10. 来源冲突裁决记录

| # | 冲突 | 裁决 | 状态 |
|---|---|---|---|
| C1 | Foundations 色板的文字标签是旧的青绿色值（如 `#0F766E`、`#1E8A5A`、`#C0392B`），与 token 值不一致 | 标签已过期，以 token 值为准 | 已定 |
| C2 | `neutral.400` 色块画成 `#9A958C`，token 值是 `#A8A39A`；`brand.on` / `neutral.0` 色块画成 `#EDE9E2` | 以 token 值为准 | 已定 |
| C3 | README 写的间距刻度没有 12；token 集中有 `space.3 = 12` | 以 token 集为准 | 已定 |
| C4 | 页面底色：画稿全部为 `#FFFFFF`；token 名 `surface.canvas`（`#F7F4EE`）看起来像是页面底色，现有代码整页铺 `#F7F4EE` | 以画稿为准：页面底色为白色，`#F7F4EE` 只用于小面积填充 | 已定（产品负责人：除器材图标外一切以画稿为准） |
| C5 | `body` 行高：样张 1.5，画稿 1.4（44 处） | 以画稿为准，取 1.4 | 已定 |
| C6 | 大标题颜色：样张 `#211F1B`，画稿 `#2A2822` | 以画稿为准 | 已定 |
| C7 | 主按钮：样张 240×48，画稿 358×52 | 以画稿为准，高 52 | 已定 |
| C8 | 弹窗按钮圆角 10 不在 8/12/16/20 刻度内 | 画稿一致使用 10，登记为 `radius.dialogAction` | 已定 |
| C9 | 深色 hero 次要文字 `#B0ABA2` 不在 token 集中 | 以画稿为准，登记为 `text.onActionSecondary` | 已定 |
| C10 | 画稿中有 12 号字（「进行中」12/600、「必填 / 选填」12/400），不在评分卡维度 3 的阶梯 34/28/22/17/15/13 内 | 全部升到 13：分别归入 `sectionLabel`、`caption`；取消 `badge` 样式 | 已定（产品负责人） |
| O1 | 无障碍：`status.destructive #D9563E` 作 15/600 文字（08「恢复失败」）对白底对比度 3.92:1，低于评分卡维度 8 要求的 4.5:1 | 同色相压暗为 `#D4442A`（4.51:1） | 已定（产品负责人） |
| O2 | 无障碍：待完成圆圈描边 `#ECE9E2` 对白底对比度 1.21:1，低于非文本元素要求的 3:1（WCAG 1.4.11） | 新增 `border.control #8E897F`（3.48:1） | 已定（产品负责人） |
| O3 | 08 屏输入框白底无描边，放在白色页面上边界不可见 | 改用 `surface.canvas` 底，与 10 屏搜索框一致 | 已定（产品负责人） |
| O4 | 11 屏器材图标溢出画板左边缘（x<0） | 画稿绘制瑕疵：图标改为 24×24 放在 16pt 边距内，动作名右移到 x=48 | 已定，已回填 |
| I1 | Penpot 17 屏、11 屏里的器材图标是旧画法（描边 3pt/2pt 混用），与 `icons/` 目录的重绘版不一致 | 以 `icons/` 为准，已替换 | 已定，已回填 |
| O5 | 画稿只覆盖了空态和训练三种状态，缺少加载、错误、离线状态（评分卡维度 9 扣分项） | 不另出设计稿，用本文的组件与颜色组合实现，并在逐屏走查时人工确认 | 已定（产品负责人） |
| O7 | 关闭态开关轨道 `#ECE9E2` 对白底 1.21:1，开关状态只靠轨道体现，低于非文本元素 3:1（spec NFR-010；2026-09-23 对抗性审查 #1） | 保留画稿外观，轨道加 1.5pt `border.control` 内描边（3.48:1），与 O2 同一处理方式；已回填 Penpot 12 屏（快照 `before-switch-off-outline 2026-09-23` → `switch-off-outline 2026-09-23 (…)`）并重新导出 `12-share-report.png` | 已定（产品负责人 2026-09-23），已回填 |
| C11 | `FCSegmentedSwitch` 在 README 中只定义为「今日 / 学员」顶部切换，代码另用于人工调整、趋势指标、身体数据录入单位 | 37 画稿（D13b，2026-09-29 批准）已在页内用同一胶囊表达「扣减 / 返还」，属于已批准的复用；限定为 2–3 个互斥短选项。不用系统分段 `Picker`（色板外，与 D13 取代系统 `Stepper` 同理），也不用筛选胶囊（筛选 / 多选语义） | 已定（产品负责人授权 AI 裁决，2026-10-05） |
| C12 | 保存状态组件没有画稿行，组件代码也未显式声明字体（继承 App 根部 `body`） | 按 M1 已验收的实际呈现补规格（§8「保存状态」）；非核心链路，不出画稿 | 已定（产品负责人 2026-10-05） |
| C13 | §8「星期多选（02）」「类型标签（15「有氧」）」对应组件没有任何界面使用：02 已被 23（D4 重复规则）取代；15 的「有氧」标签从未实现，训练中用记录方式选择表达有氧 | 作为废弃设计删除这两行，并删除 `FCWeekdayChip`、`FCTypeTag` 代码；02、15 画板保留为历史画稿，其中这两处不再是实现依据，Penpot 已加评论标注。D6b 编辑资料的「男 / 女」也画成 64×28 胶囊，但实现为 4 个选项的 `FCFilterChip`（G6 已验收），按筛选胶囊对待，64 固定宽不作为规格 | 已定（产品负责人 2026-10-05） |
| C14 | 多名学员可同时训练（M1A-FR-018 2026-10-22 修订，W-08）后，今日页需要同时展示多节进行中的课；§2.4「每屏最多一个深色 hero 面板」不变 | 采用方案 A：一张 hero 卡的多行变体（见 §8 深色 hero 卡、`components.md` `DS-HERO-CARD`）；新增 `surface.dividerOnAction`；徽标改为最小宽 56、随文字增长（CG-6）。否决横向翻页（他人被隐藏、同屏露出两张深色卡）和 hero + 提示条（同为上课学员却主次不等） | 已定（产品负责人 2026-10-22） |
| C15 | 集中走查 2026-10-22：分享报告结束后没有直接回到首页的入口，要一步步返回（预览 → 设置 → 总结「跳过分享」→ 学员详情 → 今日），至少两步 | 预览页（29）卡片之后常驻整宽次按钮「完成」（`DS-BUTTON` 次按钮），未分享、已交给系统、取消或失败时都显示；「完成」和总结页「跳过分享」都直接回到今日页（清空导航栈并切到「今日」）。否决：只在分享成功后才出现（未分享就离开仍要多步）；放在页头右上角（与「分享」抢位置） | 已定（产品负责人 2026-10-22） |
| C16 | 集中走查 2026-10-22 D7/D8：总结页「上次 → 本次」几乎不出现（算新纪录的动作不再列进步，种子历史单调递增）；D2 同重量多做几次出现两个「新纪录」标记 | 新纪录只看主指标：重量严格高于历史最大（次数不限）、辅助重量更低、时长更长、次数更多；平手、第一次做、同重量多做几次、单组容量更高都不算。比上次进步：两节各取最好的一组（最重，同重量次数最多），一项更好另一项不变差算进步，一好一坏不列。每个动作一行「上次 … → 本次 …」，新纪录在同一行加胶囊；训练中每个动作只标一组。否决：加估算 1RM（PD-D6 维持）；容量纪录（日常「破纪录」指最大重量）。历史页「个人最佳」不变 | 已定（产品负责人 2026-10-23），已回填 Penpot D-a2、D-b、D-c2 |
| C17 | 真机走查 2026-10-23：确认一组时 `.success` 与破纪录的 `.impact(heavy)` 在真机上区别不明显；设计系统没有动效 token，动效数值散写在代码里 | 所有确认一组统一 `haptic.confirm`（light impact）；破纪录时该组数值的装饰副本上浮 `space.3`、0.6 s easeOut 渐隐（2026-10-23 真机选定后改为 D 档 `space.6`、1.5 s，见 §1.9），只播一次，「新纪录」胶囊不变；「减弱动态效果」时不浮起。新增 §14 动效与触感 token（取自现有代码数值）。最终参数在开发版动效试验页的 A/B/C 三档中由负责人真机选定。否决：保留 heavy 触感（不易区分）；浮起胶囊（胶囊保持静态标记）；为 Penpot 建动效 token（不支持该类型） | 已定（产品负责人 2026-10-23），已回填 Penpot D-a2、D-a3 |
| C18 | 真机走查 2026-10-23：训练历史 → 训练记录（35）的返回是 iOS 26 系统液态玻璃大圆钮，与其他二级页的行内 `‹` 不一致；35 与 M2-13 画稿是导航栏居中「训练记录」+ 左侧 `‹`，`components.md` 曾把它列为例外 | 35 与 M2-13 改用 `DS-PAGE-HEADER`：行内 `‹` + 页面内 `titleLarge`「训练记录」，`.fcSecondaryPage()` 隐藏系统导航栏、保留右滑返回；其下日期、训练标题等内容不变，内容与页头间距 `space.6`。全 App 二级页只剩一种页头，例外取消。否决：保留居中标题、只把系统返回换成行内 `‹`（仍是第二种页头写法） | 已定（产品负责人 2026-10-23），已回填 Penpot D12（35）、M2-13，快照 `before-header35 2026-10-23` → `header35 inline page title (35, M2-13) 2026-10-23` |
| O6 | 吉祥物造型与知名动画角色是否存在版权关联 | 产品负责人确认：吉祥物为其自行生成的原创形象，与该角色无关，不涉及版权问题 | 已定（产品负责人） |

## 11. 对比度核验（WCAG 2.x）

| 前景 | 背景 | 对比度 | 结论 |
|---|---|---|---|
| `#211F1B` text.primary | `#FFFFFF` | 16.45 | 通过 |
| `#5C5A52` text.secondary | `#FFFFFF` | 6.91 | 通过 |
| `#2A2822` action.primary | `#FFFFFF` | 14.74 | 通过 |
| `#FFFFFF` | `#2A2822` | 14.74 | 通过 |
| `#FFFFFF` | `#1F1E1B` pressed | 16.67 | 通过 |
| `#B0ABA2` onActionSecondary | `#2A2822` | 6.45 | 通过 |
| `#2A2822` | `#F7F4EE` canvas | 13.42 | 通过 |
| `#5C5A52` | `#F7F4EE` | 6.29 | 通过 |
| `#2A2822` | `#EDE9E2` selected | 12.18 | 通过 |
| `#5C5A52` | `#EDE9E2` | 5.71 | 通过 |
| `#FFFFFF` | `#B45309` warning | 5.02 | 通过 |
| `#D4442A` destructive | `#FFFFFF` | 4.51 | 通过（O1 修复后；原值 `#D9563E` 为 3.92） |
| `#8E897F` border.control：待完成组圆圈描边（非文本，状态边界） | `#FFFFFF` 页面 | 3.48 | 通过（O2 修复后；原值 `#ECE9E2` 为 1.21） |
| `#8E897F` border.control：关闭态开关轨道外圈（非文本，状态边界） | `#FFFFFF` 页面 | 3.48 | 通过（O7 修复后；原轨道 `#ECE9E2` 为 1.21） |
| `#2A2822` action.primary：开启态开关轨道（非文本，状态边界） | `#FFFFFF` 页面 | 14.74 | 通过 |
| `#ECE9E2` divider（装饰，非控件边界） | `#FFFFFF` | 1.21 | 纯装饰分割线，不适用 3:1 要求 |
| `#A8A39A` text.disabled | `#FFFFFF` | 2.51 | 禁用态，WCAG 豁免 |

触控目标：所有可交互元素不小于 44×44（09 屏）。

## 12. 与现有实现（`002-m1-b` @ `1ef606f`）的差距

本节只记录差距，作为修订 plan/tasks 的输入，本轮不改代码。

| 领域 | 现状 | 设计系统要求 |
|---|---|---|
| 颜色 | 9 色；缺 `#2A2822`、`#1F1E1B`、`#F0EEE9`、`#A8A39A`、`#B0ABA2`；另有 UI 可用的 `brand #E08A5C` | 按 §2 补全；橙色移出 UI token |
| 页面底色 | `background = #F7F4EE`（41 处） | `#FFFFFF`（C4） |
| 主按钮 `FCButton` | 底色 `#211F1B`、圆角 8、高 44、按下态用透明度 0.82 | `#2A2822`、圆角 12、高 52、按下态 `#1F1E1B` |
| 排版 | 没有排版 token；系统字体 + `.footnote` / `.headline` 等约 20 种写法 | Noto Sans SC；§3 的 7 级阶梯 + 7 个具名例外 |
| 间距 | 8 / 16 | 4 / 8 / 12 / 16 / 24 / 32 |
| 圆角 | 8 / 14（14 不在刻度内） | 8 / 12 / 16 / 20 + 胶囊 + 弹窗按钮 10 |
| 器材图标 | 已导入 15 个，代码中 0 处引用；新增 3 个未导入 | 导入新增 3 个，按 §7.1 对应表接入动作相关界面 |
| 吉祥物 | 不存在 | 空态使用（§9） |
| 自动化校验 | `VisionHarnessTests` 只锁定 9 个颜色和 2 个间距 | 扩展到 §2–§5 的全部 token 值和 §11 的对比度 |

## 13. 文案与数字格式（T1，2026-10-14 产品负责人确定）

来源：体验评分卡 [`../11d-experience-scorecard.md`](../11d-experience-scorecard.md) 第 11 维的 T1。本节和颜色、字号 token 一样是权威值：代码、画稿和 Penpot 都按它写，三方不一致时按本节修。

| # | 规则 | 正确 | 错误 |
|---|---|---|---|
| N1 | 数字和拉丁单位（kg、lb、km、cm）之间加一个空格 | `120 kg`、`3.2 km`、`175 cm` | `120kg`、`3.2km` |
| N2 | 百分号紧跟数字 | `18%` | `18 %` |
| N3 | 数字和中文量词（组、次、分钟、分、秒、课时、天、个、节）之间加一个空格 | `12 组`、`32 分钟`、`5 分 30 秒`、`剩余 8 课时` | `12组`、`5分30秒` |
| N4 | 「重量 × 次数」的一组写成 `重量 单位 × 次数`，次数后不写「次」；`×` 两边各一个空格 | `120 kg × 8`、`左 8 kg / 右 9 kg × 10` | `120kg × 8次`、`120 kg × 8 次`、`120kg×8` |
| N5 | 只记次数的一组写「次」 | `20 次` | `20`、`20次` |
| N6 | 时长：记录里写 `分` 和 `秒`（`5 分 30 秒`、`5 分`、`30 秒`）；正在走的计时器用 `mm:ss`（`32:00`、`1:45`） | | `5分30秒`、`330 秒` |
| N7 | 课包的数量单位统一用「课时」，不用「次」 | `课包剩余 8 课时` | `课包剩余 8 次` |
| N8 | 并列的几项用两侧带空格的 `·` 分隔 | `20 分 · 3.2 km · 阻力 5` | `20分·3.2km` |

补充：
- 输入框的占位文字和示例也按本节写（`时长，如 5 分 30 秒`）。解析器同时接受带空格和不带空格的输入，教练怎么输入都可以。
- 学员或教练自己输入的内容（备注、课包名称）原样显示，不做格式化。
- 千位分隔符（`3,840 kg`）本轮不引入，需要时另行决定。
- 自动检查：`FineCoachTests/DesignSystem/NumberFormatScanTests.swift` 扫描 `Localizable.xcstrings` 的中文值和 `ios/FineCoachApp` 的 Swift 字符串，违反 N1、N3、N4、N7 时测试失败。违反的条数就是评分卡第 11 维「文案语气一致」的指标。

同步记录（2026-10-14）：
- 代码：`TrainingSetDisplayFormatting`（组行、分享报告和档案查看器共用）、`DurationTextParser.formatForEditing`、趋势页、分享报告的训练容量、课程总结时长（原来显示原始秒数「时长 3245 秒」，现在和训练历史一样显示「时长 54 分钟」），以及 `Localizable.xcstrings` 里的 7 个文案。
- Penpot「M1-B G5 Design」：两页共 64 处文字按本节改写（Foundations 50 处，M2 G7 Design 14 处）。M2-03 里教练手写的备注「第一次做到 90kg × 8」属于用户输入内容，保持原样。学员列表 3 个画板的「课包剩余 8 课时」变长后向左移，与「›」保持 8 pt 间距。
- **导出图已更新**（2026-10-14）：`design/m1-b-hifi/screens/` 的 10、11、13、14、21、29、30、31、32、35、41，以及 `design/m2-hifi/screens/` 的 M2-13、M2-15，已按新写法从 Penpot 重新按 2x 导出，尺寸不变。两页所有画板都已设好 2x 导出预设（`scripts/penpot/set-2x-export-presets.js`，被否决的 AppIcon 画板除外）；导出 zip 后用 `scripts/penpot/import-penpot-exports.py <zip> <画板编号 …>` 按编号覆盖。

## 14. 动效与触感（2026-10-23 产品负责人批准，§10 C17）

本节是动效和触感的唯一取值来源。Penpot 的设计 token 不支持时长和曲线类型（API `TokenType` 只有颜色、尺寸、间距、字体等），所以动效 token 只在本节和代码 `FCMotion` 里定义，Penpot 画板用文字标注 token 名。数值取自 2026-10-23 前代码里已在用的值，不是重新设计。

### 14.1 原则

1. 只在状态变化时动：每个动效都要说明它告诉用户什么（记上了、出现了、破纪录了）。没有信息的动画不加。
2. 克制：单个动效不超过 `motion.duration.emphasis`（1.5 s，只有新纪录浮起用到这么长；其他动效不超过 `gentle` 0.35 s）；不循环，不用彩带、弹窗、全屏庆祝。
3. 一套节奏：时长和曲线只用 14.2 的 token；位移距离用 §4 的间距 token。
4. 触感只说一件事：确认、选择、提醒三种，不在每次点击上加触感。
5. 「减弱动态效果」时一律降级：去掉位移和缩放，只保留淡入淡出或直接切换；触感不受影响。

### 14.2 时长与曲线

| Token | 值 | 用途（现有使用位置） |
|---|---|---|
| `motion.duration.instant` | 0.15 s | 很小的局部切换（历史列表内的展开项） |
| `motion.duration.fast` | 0.2 s | 状态切换：组圆圈描边 → 实心、确认框、编辑器内展开；「减弱动态效果」下的淡入淡出 |
| `motion.duration.standard` | 0.25 s | 面板和条：底部面板、休息条滑入与淡出 |
| `motion.duration.gentle` | 0.35 s | 页面内容出现（首次启动引导页） |
| `motion.duration.emphasis` | 1.5 s | 一次性的强调反馈：新纪录数值浮起（D-a3） |
| `motion.curve.standard` | `easeOut` | 默认：出现、离开、一次性反馈 |
| `motion.curve.symmetric` | `easeInOut` | 会来回切换的状态：组圆圈、休息条显隐 |
| `motion.spring.toggle` | `spring(response: 0.25, dampingFraction: 0.55)` | 开关类控件的回弹（分享设置的开关） |

- 数字滚动（步进器、休息倒计时）用系统 `.numericText` 与默认动画，不另设 token。
- 位移距离：内容出现上浮 `space.2`（8pt）；新纪录数值浮起 `space.6`（24pt）。
- 引导页的错峰延迟（0.25 / 0.35 / 0.45 / 0.55 s）是该页面的编排参数，不作为 token。

### 14.3 触感

| Token | 系统反馈 | 何时 |
|---|---|---|
| `haptic.confirm` | `.impact(weight: .light)` | 确认一组（含破纪录、进步）；每次确认一次 |
| `haptic.selection` | `.selection` | 步进 − / +、分享设置开关与勾选 |
| `haptic.attention` | `.warning` | 休息结束 |

- 2026-10-23 起不再使用 `.success` 和 `.impact(weight: .heavy)`：重触感与普通确认在真机上不易区分（集中走查 D1/D2），破纪录改由 D-a3 数值浮起表达。
- 编辑、删除、撤销、恢复后的重算不触发任何触感。

### 14.4 动效清单

| 时刻 | 表现 | 「减弱动态效果」时 |
|---|---|---|
| 确认一组 | 组圆圈 `fast` + `symmetric` 变为实心 ✓；`haptic.confirm` | 直接切换，保留触感 |
| 确认一组且破纪录 | 同上；另有该组数值的装饰副本向上浮起 `space.6`、透明度 1 → 0，`emphasis` + `standard`，只播一次；「新纪录」胶囊同时出现（D-a3） | 不浮起，只出现胶囊 |
| 步进 − / + | 数字 `.numericText` 滚动；`haptic.selection` | 直接切换数字 |
| 休息条出现与收起 | 从底部滑入、收起淡出，`standard` | 只淡入淡出 |
| 休息倒计时 | 每秒 `.numericText` 滚动 | 直接切换数字 |
| 休息结束 | 文字换成「✓ 休息结束」；`haptic.attention`；3 秒后收起 | 同左，收起不带位移 |
| 底部面板、确认框出现 | `standard` / `fast` + `standard` 曲线 | 只淡入淡出 |

迁移范围：本轮只有训练页（ActiveSession 与 `FCSetRow`、`FCSetStateCircle`）改用 `FCMotion`；其他页面的现有数值与 token 相同，改到哪页再迁哪页（`components.md` §1.3）。
