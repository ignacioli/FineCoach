# FineCoach 组件规格（Component Anatomy Spec）

> 状态：v1.0（2026-10-05 产品负责人批准；同日按其决定删除 2 个废弃组件、补登记保存状态、裁决 CG-7、减少人工走查）。类型：**已有设计的规范补齐**——目标设计（设计系统 v1.0 + M1-B 批准画稿 01–43）不变，本文只把它们写成文字化的组件结构，并映射到代码。本文不批准任何新的视觉决定。
> 作用：组件结构（anatomy）的唯一入口。[`README.md`](README.md) 仍然是 token 和组件数值的唯一权威；本文规定**每个组件由哪些部件组成、按什么顺序排列、有哪些变体和状态、哪些规则不能破坏、对应哪段代码、由什么检查保证**。

## 0. 为什么需要本文

token、截图和画稿都齐全时，界面仍会偏离设计，原因通常是：

- token 只规定数值，不规定结构。Agent 拿着正确的颜色和字号，仍然可能拼出错误的层级、顺序、状态或点击区域。
- 截图只展示一个状态。空态、禁用、错误、长文本、动态字体放大都没有画出来，Agent 只能自己猜。
- 逐页对照截图验收成本高，每页都要人工看；同一个组件的错误会在每一页重复出现。

本文把验收从「每个页面」前移到「每个组件」：组件按本文的规格做对一次，并由自动检查锁住；页面只需用已有组件拼装，再抽查组合结果。人工只在需要判断的地方介入（§1.4）。

## 1. 视觉工作流（Agent 必须执行）

### 1.1 权威顺序

1. [`README.md`](README.md) §2–§9：token、排版、间距、圆角、图标、组件数值。数值冲突时以它为准。
2. 本文：组件 anatomy、变体、状态、不变量、代码映射、复用边界。
3. 各里程碑的高保真目录（如 `design/m1-b-hifi/`，以后的 `design/m2-hifi/`）里的批准画稿和 feature 级实施映射（§6）：只定义该 feature 自己的页面组合和 feature 专有组件。
4. 生产代码 `ios/FineCoachApp/DesignSystem/`：表示当前实现所在位置。代码与 1–3 冲突时**修代码**，不能反过来修改设计来迁就错误实现。

Penpot「M1-B G5 Design」是 1 和 3 的设计源，画板图层已按本文 ID 标注（README §1.3：图层名「DS-xxx · 部件」与 shared plugin data `finecoach.component`）；文档、画稿导出和 Penpot 必须同轮保持一致（`CLAUDE.md` §Visual design authority）。

### 1.2 第一步：按设计变化分类（Agent 自行判断，不需要每次请人确认）

修改前先阅读相关画稿、README 对应章节和本文对应组件，再按**目标设计是否改变**分类。不能只看需求措辞（「修复」「优化」「新增」）或组件文件名来判断。一个任务涉及多个组件时，按组件分别分类。

| 类别 | 判断依据 | 流程 |
|---|---|---|
| A. 从 0 到 1 | 缺少适用的设计基础，需要新的视觉语言、新的页面类型或新的核心组件 | 需求与关键流程 → 低保真确认 → 高保真（先组件、后代表页面）→ 产品负责人 Review → 定稿 component spec 与代码映射 → 实现 |
| B. 设计修订 | 会改变已批准的布局、信息层级、视觉或交互，哪怕只涉及一个组件 | 核对现有规格与约束 → 高保真局部修订 → 产品负责人 Review → 同步 README / 本文 / Penpot / 导出图 → 实现 |
| C. 规范补齐 | 目标设计已批准且不变，只缺文字 anatomy、状态说明或代码映射 | 从批准画稿抽取 spec → 核对来源一致 → 实现；**不重复视觉审批** |
| D. 实现偏离修复 | 目标设计不变，代码没有遵守画稿或本文 | 对照画稿 / 本文定位偏差 → 修代码 → 组件级定向验证；**不修改设计迁就错误实现** |

新的 feature 不等于类别 A。现有设计系统能表达时，按实际变化选 B、C 或 D。M2 的大部分页面预期属于「复用现有组件 + 少量扩展 / 新增」。

Component spec 必须在**依赖它的代码**开始实现前定稿，但不需要早于高保真定稿。设计前可以先写简短约束草案，但草案不能当作已批准的视觉方案。

### 1.3 第二步：按组件判断复用、扩展还是新增

| 范围 | 定义 | 要求 |
|---|---|---|
| 复用 | 现有 anatomy、变体、状态已能覆盖需求，只换数据或使用允许的参数 | 直接使用本文列出的组件；页面里不得复制它的样式 |
| 扩展 | 需要新的 slot、变体、状态或行为 | 先更新本文对应条目（列出受影响的现有消费者），属于 B 类时同时更新画稿；再改组件；现有消费者的表现不得意外改变 |
| 新增（共享） | 现有组件无法合理表达，且至少两个 feature 有相同需求 | 先在本文新增条目（稳定 ID、anatomy、状态、不变量、来源画板），再写 `DesignSystem/Components/` 代码 |
| 新增（feature 专有） | 只有一个 feature 用到的结构 | 写在该 feature 的实施映射（§6），引用本文 `DS-BASE` 和用到的子组件；第二个 feature 需要时再提升为共享组件 |

注意：
- 页面里出现两处以上相同的「`HStack` + 字体 + 颜色」组合，就是缺共享组件的信号，应先登记到 §5 缺口，不要继续复制。
- 只把代码挪到一个新 Swift 文件，不等于新增了设计系统组件；只复用了 token，也不能证明结构不需要扩展。
- 不要因为名字相近就假设已有同名组件；以 §3 索引为准。

### 1.4 第三步：验证——组件优先，页面抽检，人工按需

验证按层级进行。较低层级的检查必须先通过，才进入更高层级。

| 层级 | 检查对象 | 方式 | 现有手段 |
|---|---|---|---|
| L0 token | 颜色、字号、间距、圆角、图标、对比度 | 自动 | `VisionHarnessTests`、`ContrastHarnessTests`、`TypographyHarnessTests`、`IconConsistencyTests` |
| L1 组件合同 | 本文每个条目的「不变量」 | 自动优先：纯逻辑测试或组件源码静态断言；组件目录与代码一致 | `TouchTargetComponentTests`、`FCStatusTests`、`FCStepperTests`、`ComponentCatalogTests` |
| L2 页面组合 | 页面只用 token 和组件；组件顺序、页面边距、单屏规则 | 自动静态扫描 + 执行记录中的组合清单 | `DesignValueScanTests`（feature 源码不得出现原始颜色 / 字体 / 间距 / 圆角） |
| L3 人工 | 只检查结构化手段无法判断的事实 | 产品负责人对照 `design/*/screens/*.png` 抽查 | 只在下方触发条件下进行 |

L1 规则：
- 新增或扩展组件时，要为它在本文写下的每条「可自动验证」不变量增加或更新测试。只用纯逻辑测试或组件源码断言，不引入 ViewInspector 或新依赖，不做 Feature 页面结构断言（`CLAUDE.md`）。
- 无法自动验证的视觉事实（例如虚线圆的观感）在组件条目里标为「人工」，在**组件**引入或修改时看一次；之后复用该组件的页面不再重复检查这一项。

L2 的检查点证据（Agent 负责，替代逐个检查点的人工走查）：每个检查点在执行记录里附「入口与布局清单」，每个新的交互一行：

```text
页面 → 可见控件（文字或图标）→ accessibilityIdentifier → 是否修改数据（是则不得只靠长按 / contextMenu）→ 宽度由哪个组件或容器撑满
```

清单里每一行都必须能在代码中找到对应位置；找不到入口、只有手势入口、或宽度不是由组件 / 容器撑满的，按缺陷处理，不交给人工去发现。这三类正是 Phase 4 走查发现的缺陷（缺少 `.frame(maxWidth: .infinity)`、入口藏在手势里、逻辑有测试但没有界面入口）。

L3 只在以下情况触发：
1. A 类或 B 类出现了新的视觉决定——产品负责人审的是 Penpot 画稿，不是代码截图；
2. feature spec 指定的核心页面（通常每个里程碑 1–3 个）**第一次实现完成**时，对照画稿看一次；之后只在它再次发生 B 类修订时复看；
3. 里程碑实现验收门（M1-B 对应 G6）之前**一次集中走查**：Agent 在模拟器准备好数据，并给出只包含「新交互 + 核心页」的走查清单，人工一次走完，不按检查点分批；
4. Agent 写明了具体疑点、且结构化证据无法给出结论的单个事实（例如某段文字在最大字号下是否可读）。

除此之外，检查点不需要人工走查。不能用这条规则声称界面「已视觉验证」：没有人工看过时，报告必须写明。

截图循环（截图 → 判断 → 修改 → 再截图）不能作为验收手段（`CLAUDE.md`）。需要人工查看时，准备好模拟器数据，再交给人工操作。

### 1.5 最小执行记录

每次视觉任务都在 plan / tasks、feature 实施映射或本轮执行说明中写下这五行。不另建一套文件，也不复制权威规格。

```text
分类与依据：A/B/C/D；目标设计是否改变；适用的批准来源（文件路径 / 画板编号 / Penpot 快照）。
影响范围：组件 ID；复用 / 扩展 / 新增；受影响的现有消费者与状态；需要同步的文件。
设计决定：沿用了哪些已批准决定；新的决定及其 Review 状态；真实缺口或冲突。
实施与验证：组件不变量及其测试；代表状态；页面组合抽检范围；入口与布局清单（§1.4）；是否触发 L3 及原因。
结果：实际 PASS / FAIL / BLOCKED、证据位置、剩余项。不能用计划代替执行结果。
```

Agent 负责分类、影响分析和整理证据；人类主要负责审阅新的设计决定，以及必要的最终体验抽查。只有在以下三种情况才向产品负责人提一个具体问题：权威来源冲突；无法判断目标设计是否改变，且这会影响方案；出现了未经授权的实质性新设计决定。提问时，不依赖答案的工作继续进行。

## 2. 共享基线 `DS-BASE`

适用于所有组件和 feature 页面：

- 颜色、字体、间距、圆角只能使用 `FCSemanticColors` / `FCPrimitives` / `.fcFont(_:)`。feature 源码中出现原始值会让 `DesignValueScanTests` 失败。组件内部的 SF Symbol 字形尺寸可以使用 `.font(.system(size:weight:))`，前提是该尺寸来自 README §7.2（`FCSymbol`、`FCStatusBadge`、`FCSetStateCircle`）。
- 可见文案用 `Text(String(localized: "key"))`（或 verbatim 字符串），不要写 `Text("key")` 字面量：字面量是 `LocalizedStringKey`，与随包 Noto Sans SC 一起排版时会在「、」后多出约半个字宽的空隙（模拟器实测 16pt，画稿 9.5pt；M2-02 排除说明的症状，2026-10-10）；仅用于无障碍标签的 `Text("key")` 不受影响。
- 页面底色为 `surface.page` 白色；`surface.canvas` 只用于小面积填充（README §2.2、C4）。页面左右边距为 `space.4`。不使用阴影（§6）。每屏最多一个深色 hero（§2.4）。
- 状态必须同时用文字和图标表达，不能只靠颜色（§2.4、constitution V）。
- 所有可交互元素的点击区不小于 44×44；视觉尺寸较小时，向外补足点击区，不放大视觉本身（参见 `FCConfirmationDialog`、`FCFilterChip` 的做法）。
- 文字必须随动态字体缩放（`.fcFont` 已实现）。固定宽度的容器必须说明内容变长时的处理方式（换行、截断或加宽），见各条目。
- 修改数据的操作必须有可见的入口，不能只能通过 `.contextMenu` 或长按触发（`CLAUDE.md`）。
- 装饰性部件（图标、头像、徽标）对无障碍隐藏，由旁边的文字或所在行承担可访问名称。

## 3. 组件索引

「消费者」由 `grep` 统计（2026-10-05，`ios/FineCoachApp/Features` 与 `App`），只用于评估影响范围，不代表这些页面已经通过视觉验收。`ComponentCatalogTests` 校验：本表「代码」列与 `DesignSystem/` 中的公开类型逐一对应。

| ID | 代码 | 来源 | 消费者（feature） | 状态 |
|---|---|---|---|---|
| `DS-BASE` | `FCPrimitives`、`FCSemanticColors`、`FCFont`、`FCTextStyle`、`FCFontWeightVariant` | README §2–§5 | 全部 | L0 全自动 |
| `DS-BUTTON` | `FCButton`、`FCSecondaryButton`、`FCLinkButton` | §8 主按钮 / 次按钮 / 链接式按钮 | 主按钮 27 个文件；次按钮 1 个；链接按钮 13 个 | 稳定 |
| `DS-TITLE-ACTION` | `FCTitleIconButton`、`FCTitleAddButton` | §8.1 标题行图标按钮、标题行「＋」、设置入口；40/41 | Today、StudentList、ExerciseLibrary | 稳定 |
| `DS-SEGMENTED` | `FCSegmentedSwitch` | §8 顶部分段切换；37；§10 C11 | RootNavigation、Trends、BodyMeasurementEntry、ManualCreditAdjustment | 稳定 |
| `DS-CHIP` | `FCFilterChip`、`FCBodyPartChip`、`FCBodyPartPicker`、`FCFlowLayout` | §8 筛选胶囊；§8.1 部位多选胶囊 | 筛选胶囊 7 个文件；部位选择 3 个 | 稳定 |
| `DS-TOGGLE` | `FCToggleStyle` | §8 开关；O7 | 4 个文件 | 稳定 |
| `DS-STEPPER` | `FCStepper`、`FCStepperField` | §8.1 数字步进器；36/37；P0-a/P0-b 可输入变体 | CoursePackageEditor、ManualCreditAdjustment、ActiveSession | 稳定（可输入变体已回填 README §8.1；Penpot P0-a/P0-b 2026-10-14 已批准） |
| `DS-TEXT-FIELD` | `FCTextField`、`FCSearchField` | §8 输入框、搜索框 | 输入框 14 个文件；搜索框 2 个 | 稳定 |
| `DS-LIST-ROW` | `FCListRow`、`FCListGroupRow`、`FCListRowDivider` | §8 列表行；§6 分割线；M2 扩展（§4.7） | 分割线 26 个文件；`FCListRow` 0 个（M2 新页面使用） | 扩展已实现（M2 T004）；其余见 CG-1 |
| `DS-SECTION` | `FCSectionLabel`、`FCGroupEntryRow` | §8 区段标签；§8.1 列表分组入口行 | 区段标签 14 个文件；分组入口 2 个 | 稳定 |
| `DS-LABEL-VALUE-ROW` | `FCLabelValueRow`、`FCLabelValueText` | §8.1 标签-值两栏行；23/26/27/36/37 | 6 个文件 | 见 CG-5 |
| `DS-PAGE-HEADER` | `FCPageHeader` | §4.7；§4.6 `DS-PAGE-SECONDARY` 的页头部分；26 | StudentDetail（M2 新页面全部使用） | 已实现（M2 T001），人工项待首次走查 |
| `DS-HUB-ROW` | `FCHubRow` | §4.7；19/42/43 | ResourceHub、Settings（M2 新页面使用） | 已实现（M2 T002），人工项待首次走查 |
| `DS-INLINE-RESULT` | `FCInlineResult` | §4.7；38/39 | BackupRestoreFlow | 已实现（M2 T003），信息变体待 M2 页面首次使用 |
| `DS-ACTION-ROW` | `FCActionRow` | §8.1 操作行；18/24；destructive 图标（§4.7） | 10 个文件 | 稳定；destructive 图标已实现（M2 T005） |
| `DS-SET-ROW` | `FCSetRow`、`FCSetStateCircle` | §6 组圆圈；11/30 | ActiveSession；圆圈另用于 ShareReport、History | 见 CG-4 |
| `DS-HERO-CARD` | `FCHeroCard` | §8 深色 hero 卡；01/18 | Today、StudentDetail | 见 CG-6 |
| `DS-HINT-BAR` | `FCHintBar`、`FCActiveSessionBar` | §8 提示条；§8.1 训练中提示条；21 | StudentDetail、StudentList | 稳定 |
| `DS-BOTTOM-SHEET` | `FCBottomSheet`、`View.fcBottomSheet` | §8.1 底部面板；18/31/33/34 | 8 个文件 | 稳定 |
| `DS-CONFIRM-DIALOG` | `FCConfirmationDialog`、`View.fcConfirmationDialog` | §8 确认弹窗；14 | CoursePackageList、CourseActionSheet、TemplateEditor | 内容变长规则已实现（M2 T006）；CG-6 |
| `DS-STATUS` | `FCStatus`、`FCStatusLabel`、`FCStatusBadge` | §7.2 状态图标；09；38/39 | 6 个文件 | L1 部分自动 |
| `DS-SAVE-STATUS` | `FCSaveStatusView` | §8 保存状态（无画稿）；§10 C12 | ActiveSession/SaveStatusView | 规格已补；代码已对齐（M2 T007，CG-3） |
| `DS-AVATAR` | `FCAvatar` | §8 头像 | StudentList、StudentDetail | 稳定 |
| `DS-CALENDAR-DAY` | `FCCalendarDayCell` | §8.1 月历有课圆点；25 | Calendar | 稳定 |
| `DS-SYMBOL` | `FCSymbol` | §7.2 系统图标 | 11 个文件 | 稳定 |
| `DS-EQUIPMENT-ICON` | `FCEquipmentIcon`、`FCEquipmentIconView` | §7.1；17 | 5 个文件 | L0 全自动 |
| `DS-BODY-DIAGRAM` | `FCBodyDiagram` | §9.1；29 | ShareReportCard | 稳定 |

页面组合模式（没有共享代码，由 feature 拼装）：`DS-PAGE-PRIMARY`、`DS-PAGE-SECONDARY`（页头部分已有共享组件 `DS-PAGE-HEADER`）、`DS-EMPTY-STATE`，见 §4.6。`DS-HUB-ROW`、`DS-INLINE-RESULT` 已提升为共享组件。

## 4. 组件 anatomy

每个条目的格式：**部件**（从上到下、从前到后的视觉与阅读顺序）→ **变体 / 状态** → **不变量**（标注检查方式：`自动` 已有测试；`可自动` 可以加测试但目前没有；`人工` 只在组件变化时看一次）→ **复用边界**。数值只写 anatomy 必需的部分，其余引用 README。

### 4.1 操作类

#### `DS-BUTTON` 按钮

- **部件**：单行文字标签；无图标 slot。
- **变体**：
  - `FCButton` 主按钮：`action.primary` 底、`headline` `action.on` 字、`radius.md`、最小高 52、宽度填满父容器（358 来自 390 屏宽减 2×16 边距，不是固定值）。状态：默认 / 按下（换成 `action.pressed`，不用透明度）/ 禁用（`surface.divider` 底 + `text.secondary` 字）。
  - `FCSecondaryButton` 次按钮：白底、1.5pt `action.primary` 描边、`headline` `action.primary` 字；禁用时描边和文字都改为 `text.secondary`。
  - `FCLinkButton` 链接式按钮：无底色，`callout` 600 `action.primary`；禁用时改为 `text.secondary`；最小点击区 44×44。
- **不变量**：点击区 ≥ 44（自动：`TouchTargetComponentTests`）；按下态使用 token 而不是透明度（可自动）；可访问名称等于标题（可自动）。
- **页面规则**：页面底部主按钮距屏幕底 32（`space.8`，README §4），每屏最多一个底部主按钮。破坏性操作不能用主按钮样式，应使用 `DS-ACTION-ROW` 的 destructive 变体并配合 `DS-CONFIRM-DIALOG`。
- **复用边界**：弹窗内的按钮不是 `DS-BUTTON`，属于 `DS-CONFIRM-DIALOG` 的内部部件（36 高、`radius.dialogAction`）。

#### `DS-TITLE-ACTION` 标题行操作

- **部件**：放在一级页大标题同一行的右侧，按从左到右排列：`FCTitleAddButton`（仅今日页）→ `FCTitleIconButton`（日历 / 资料库 / 筛选）→ 设置齿轮（`FCTitleIconButton`）。
- **变体**：图标按钮：22×20 线性 SF Symbol，`text.secondary`，`fontWeight(.light)`，无底色、无阴影；「＋」：22×22 `action.primary` semibold。
- **不变量**：点击区 ≥ 44×44（自动）；没有可见文字，所以必须提供 `accessibilityLabel`（构造器强制要求）；「＋」只表示「新建预约」（§8.1 D15a，人工）；图标中心间距 44（人工，40 画板）。
- **复用边界**：只用于一级页标题行。二级页的页头操作使用 `DS-PAGE-SECONDARY`。

#### `DS-SEGMENTED` 顶部分段切换

- **部件**：横向排列的选项，间距 `space.2`。选中项：50×32 胶囊、`action.primary` 底、`headline` 白字；未选中项：纯文字 `body` `text.secondary`，无底色。
- **状态**：选中项带 `.isSelected` 无障碍属性。
- **不变量**：点击区 ≥ 44（自动）；同时只有一个选中项（类型保证：`selection` 是单个 ID）。
- **用途**：一级页顶部「今日 / 学员」；页内 2–3 个互斥短选项（37「扣减 / 返还」、趋势指标、身体数据录入单位），通常放在 `DS-LABEL-VALUE-ROW` 的值 slot（README §10 C11）。
- **复用边界**：选项超过 3 个或文字较长时改用 `DS-CHIP`；不使用系统分段 `Picker`。

#### `DS-CHIP` 胶囊

- **部件**：单行 `chipLabel` 文字，放在胶囊底上。
- **变体**：
  - `FCFilterChip`：高 30、水平内边距 `space.3`，宽度随文字变化。
  - `FCBodyPartChip`：高 28、最小宽 48、水平内边距 `space.4`；`FCBodyPartPicker` 按 `BodyPart.allCases` 的 spec 顺序排出 8 个，通过 `FCFlowLayout` 自动换行。
- **状态**：未选中 `surface.selected` 底 + `text.primary` 字；选中 `action.primary` 底 + `action.on` 字，并带 `.isSelected` 属性。
- **不变量**：视觉高度保持 28/30，点击区补足到 ≥ 44（自动）；`FCBodyPartPicker` 胶囊之间的视觉行距为 8，通过负的布局行距抵消 44pt 点击区（`space.2 - (44 - 28)`，可自动）；部位顺序与 spec 一致（可自动）。
- **可访问性标识扩展**：`FCBodyPartPicker` 可选接收 `BodyPart -> String` identifier factory，默认 `nil`；非 `nil` 时将结果赋给对应的真实 `FCBodyPartChip` Button，`nil` 时不设置 identifier。该扩展只增加自动化定位能力，不改变视觉、布局或默认消费者行为。
- **复用边界**：多选与单选共用同一套外观；是单选还是多选由调用方的绑定决定。不要新造第三种胶囊尺寸；确实需要时按「扩展」流程处理。

#### `DS-TOGGLE` 开关

- **部件**：44×26 胶囊轨道 + 18×18 白色圆形滑块，**左关右开**。
- **状态**：开启：轨道 `action.primary`；关闭：`surface.divider` 底 + 1.5pt `border.control` 内描边（O7）。
- **不变量**：必须是系统 `Toggle` 加 `.toggleStyle(.fc)`，这样能保留系统开关的无障碍语义，样式本身不添加任何 `.accessibility*` 修饰（可自动）；点击区 ≥ 44（自动）；关闭态描边与页面的对比度 3.48:1（自动：Contrast）。
- **复用边界**：行内开关放在 `DS-LABEL-VALUE-ROW` 的值 slot，或放在 feature 行的尾部。

#### `DS-STEPPER` 数字步进器

- **部件**：一个 `surface.canvas` 胶囊（默认字号下 112×36）：`−` → 数值 → `+`。符号使用 `FCSymbol(.minus/.plus)`；数值使用 `numeralLarge` `text.primary`、等宽数字，最小宽 40。
- **状态**：到达下限或上限时，对应符号改为 `text.disabled` 并禁用。
- **不变量**：每次只能 ±1，结果限制在范围内（自动：`FCStepperTests`）；VoiceOver 把整体读作一个可调节元素（label + value，上下滑动调节）（可自动）；每个符号的点击区 ≥ 44（自动）；字号放大时胶囊随之加宽，不截断数值（人工）。
- **复用边界**：取代系统 `Stepper`。所有整数步进都必须用它。重量和次数的可输入步进用下面的变体，不要在页面里再拼一套「− 输入框 +」。
- **变体 `FCStepperField`**（P0-a、P0-b，2026-10-14 审核通过）：放在 `DS-LABEL-VALUE-ROW` 的值 slot，只有训练页使用。胶囊高 48、`radius.capsule`、`surface.canvas` 底，宽度填满值列。部件是 `−`、居中的可输入数值（`numeralLarge`）、`+`；符号用 `FCSymbol(.minus/.plus)`，每个点击区 ≥ 44。到达下限时「−」改为 `text.disabled` 并禁用。键盘输入中，胶囊加 1.5pt 内描边 `action.primary`，「− / +」仍可点。步长、下限和文本解析由调用方按 P0-D4 / P0-D6 传入（`SetValueStepping`），组件本身不决定 ±2.5 或 ±1。现有 `FCStepper` 和它的两个消费者不变。

### 4.2 输入类

#### `DS-TEXT-FIELD` 输入框与搜索框

- **部件**：`surface.canvas` 底、`radius.sm`、水平内边距 `space.4`；占位文字 `callout` 400 `text.secondary`；输入文字（输入框为 `body`，搜索框为 `callout`）`text.primary`。
- **变体**：`FCTextField`：最小高 48，`isSecure` 时显示遮蔽输入（口令）；`FCSearchField`：固定高 40，**不带放大镜图标**（以 10 画板为准）。
- **不变量**：不在白底上使用无边界的输入框（O3，人工）；可访问名称等于占位标题（可自动）。
- **复用边界**：输入框外面没有单独的标签行。需要「标签 + 值」两栏时，使用 `DS-LABEL-VALUE-ROW`，并在值 slot 放一个无底色的 `TextField`（例如 02 / 27 画板），而不是嵌入 `FCTextField`。

### 4.3 列表类

#### `DS-LIST-ROW` 列表行与分割线

- **部件**：主文字（`headline` 或 `body`，`text.primary`；行在页面自己的 16 边距内，不再额外缩进，标题起点 = 分割线起点 x=16）→ 可选元信息（`caption` `text.secondary`，在主文字下方，间距 `space.1`）→ 弹性空白 → 可选 `›`（`FCSymbol(.forward)`）。最小高 52（实测 M2-02a/02b/03：分割线间距 53 = 行 52 + 分割线 1；无对应间距 token，值见 `FCListRowGeometry.minHeight`）。
- **分割线**：`FCListRowDivider` 是 1pt `surface.divider`，由调用方放在行与行之间，不画在行内部。
- **不变量**：带 `action` 时整行可点；不可点时合并为一个无障碍元素（可自动）。
- **复用边界**：见 CG-1。目前 feature 中的列表行都是各自拼装。新的普通列表行优先使用 `FCListRow`；需要头像、图标、状态等额外 slot 时，按「扩展」流程增加 slot，不要在页面里再复制一套。

#### `DS-SECTION` 区段标签与分组入口

- **部件**：`FCSectionLabel`：`sectionLabel` `text.secondary`，单独一行，位于区块的第一个元素之前。`FCGroupEntryRow`：「标题 · N」（`sectionLabel` `text.secondary`）→ 弹性空白 → `›`，整行可点，最小高 44。
- **不变量**：区块之间的间距大于行内间距（README §4，人工）。

#### `DS-LABEL-VALUE-ROW` 标签-值两栏行

- **部件**：标签列（`callout` 400 `text.secondary`，宽 96，因此值从 x=112 开始）→ 值 slot（左对齐，任意视图）→ 可选 `›`。最小高 52；行与行之间由调用方插入 `FCListRowDivider`。
- **变体**：纯文字值（`FCLabelValueText`，`body` `text.primary`，整行合并为一个无障碍元素）；视图值（开关、日期、文字 + 尾部元素，子元素各自保持可访问）；带 `action` 时整行可点并显示 `›`；放在 `Menu` 的 label 里时可以只显示 `›`。
- **不变量**：标签列宽固定，值列对齐（人工，23/27）；带 action 的行显示 `›`（可自动）。
- **复用边界**：见 CG-5。CoursePackageEditor、ManualCreditAdjustment 还有各自私有的 `editorRow`。

#### `DS-ACTION-ROW` 操作行

- **部件**：标题（无副标题时为 `body`，有副标题时为 `headline`）→ 可选副标题（`caption` `text.secondary`）→ 弹性空白 → 可选说明（`caption` `text.secondary`）→ `›`（仅普通操作行）。最小高 52；有副标题时上下内边距 `space.3`。
- **变体**：`normal`；`destructive`（`status.destructive` 字、**没有** `›`）；禁用（文字和 `›` 都改为 `text.disabled`）。
- **不变量**：destructive 行自身不执行破坏性操作，调用方必须在 `action` 中弹出 `DS-CONFIRM-DIALOG`（§8.1，可自动：可以扫描调用方源码）；整行可点。
- **复用边界**：放在底部面板和编辑页的操作区。普通内容浏览列表使用 `DS-LIST-ROW`。

#### `DS-SET-ROW` 训练组行

- **部件**：组状态圆圈（22×22，点击区 44）→ 一行内：标题「第 N 组」（`body`；已完成为 `text.primary`，其余为 `text.secondary`）→ 弹性空白 → 数值（`body` `text.primary`，单行，最小缩放 0.8）→ 状态文字（`callout` 400 `text.secondary`），刚确认的一组在 4 秒内换成「撤销」（`FCLinkButton`，P0-D11）→ 可选编辑按钮（铅笔，44）。2026-10-15 起由上下两行改为一行，与已批准的 D8 / P0-a2 稿一致（implementation-map Δ5）。
- **`FCSetStateCircle` 状态**：待完成：1.5pt `border.control` 描边；草稿：1pt `text.secondary` 虚线（3/2）；已完成：`action.primary` 实心 + 白色 ✓。
- **不变量**：长按编辑只作用于标题/数值区域，不能覆盖确认按钮和编辑按钮的点击（代码注释记录了真机上发生过的回归，人工）；每个可修改数据的操作都有可见按钮（✓ 确认、铅笔编辑），长按只是快捷方式（`CLAUDE.md`）；整行是一个无障碍元素，读作「标题，数值，状态」，并提供「确认」「编辑」两个动作，撤销窗口内另有「撤销」动作（可自动）。
- **复用边界**：比较选择模式（32）里的勾选圈复用 `FCSetStateCircle` 的外观（README §8.1）。

### 4.4 容器与浮层

#### `DS-HERO-CARD` 深色 hero 卡

- **部件**：徽标（56×24 胶囊、`surface.canvas` 底、`sectionLabel` `action.primary` 字）→ 标题行：左侧标题（`headline` `action.on`）+ 下方副文字（`callout` `text.onActionSecondary`）；右侧可选操作文字（`callout` 600 `action.on`，与标题首行基线对齐）。整卡 `action.primary` 底、`radius.lg`、内边距 `space.4`、最小高 100。
- **不变量**：每屏最多一个（这是页面组合规则，组件本身无法保证；属于 L2 组合检查）；有 action 时整卡就是一个点击目标，操作文字是它的可见标签（人工）。
- **复用边界**：见 CG-6（徽标宽度固定）。

#### `DS-HINT-BAR` 提示条

- **部件**：`FCHintBar`：单段 `caption` `action.primary` 文字，`surface.selected` 底，`radius.md`，最小高 44，宽度填满。`FCActiveSessionBar`：同样的底，左侧说明文字填满剩余宽度，右侧「继续训练」（`callout` 600 `action.primary`），整条可点。
- **复用边界**：提示条只承载信息或单个继续操作；需要警示语义时使用 `DS-STATUS`，不要给提示条换颜色。

#### `DS-BOTTOM-SHEET` 底部面板

- **部件**：拖动条（36×5 `surface.divider` 胶囊，居中，距顶 `space.2`，对无障碍隐藏）→ 可选标题区：标题（`headline` 或 `title`，带 header 属性）+ 副标题（`callout` 400 `text.secondary`）+ 可选尾部 accessory（如 18 画板的状态文字）→ 内容（通常是 `FCActionRow` 与分割线）。白底、顶部两角 `radius.lg`、水平内边距 `space.4`、底部 `space.6`。
- **呈现**：必须用 `View.fcBottomSheet(isPresented:)`，由它绘制 `overlay.scrim`；不要用系统 `.sheet`，因为它的遮罩颜色不在色板内。点击遮罩、向下拖超过 80pt 或无障碍 escape 都会关闭面板。
- **不变量**：遮罩颜色为 `text.primary` 40%（自动：Vision）；面板带 `.isModal` 属性（可自动）。

#### `DS-CONFIRM-DIALOG` 确认弹窗

- **部件**：标题（`headline` `text.primary`）→ 说明（`caption` `text.secondary`，居中）→ 按钮行：保守 / 取消按钮在左（`surface.selected` 底 + `callout` 600 `action.primary`），确认按钮在右（`action.primary` 底 + 白字）；按钮视觉高 36、`radius.dialogAction` 10、间距 `space.2`。卡片宽 300、内边距 `space.4`、`radius.lg`、`surface.elevated`。
- **呈现**：`View.fcConfirmationDialog(isPresented:)`：居中显示，背后是 `overlay.scrim`，点击遮罩等于取消。
- **不变量**：按钮视觉保持 36 高，点击区补足到 44（自动：源码中有 `minHeight: 44`）；取消在左、确认在右（人工）；固定宽 300，见 CG-6。
- **复用边界**：所有破坏性或不可逆操作的确认都用它；不使用系统 `.alert` / `.confirmationDialog`。

### 4.5 状态、身份与图形

#### `DS-STATUS` 状态标签与徽标

- **部件**：`FCStatusLabel` = 22×22 `FCStatusBadge`（实心圆 + 白色字形）→ `caption` 文字（`text.secondary`），整体合并为一个无障碍元素，读出文字。
- **变体**：5 个具名状态（README §7.2 表）：需要教练处理的用 `status.warning` +「!」，只是信息的用 `action.primary` +「i」。自由文本构造器必须同时提供文字和字形。单独使用 `FCStatusBadge` 只限 38/39 画板的就地结果（`DS-INLINE-RESULT`），那里允许 `status.destructive` + 「!」（失败）和 `action.primary` + ✓（成功）。
- **不变量**：恰好 5 个具名状态，每个都有非空的文字和字形；每个状态只在登记的文件中通过 `FCStatusLabel` 展示（自动：`FCStatusTests`）。

#### `DS-SAVE-STATUS` 保存状态

数值来源：README §8「保存状态」（按 M1 已验收的实际呈现补登记，无画稿，§10 C12）。

- **部件**：图标 → 文字，横排；最小高 44（非交互，只为与训练页其他行对齐）。
- **状态**：保存中（`arrow.triangle.2.circlepath`）/ 已保存（`checkmark.circle`）/ 保存失败（`exclamationmark.triangle`）。文字 `body` 400；保存中、已保存为 `text.secondary`，保存失败为 `status.destructive`，图标与文字同色。
- **不变量**：恰好 3 个状态，每个都有图标和文字（可自动）；整体是一个无障碍元素，只读出文字，图标对无障碍隐藏（可自动）；失败时的说明和「重试」不属于本组件，由调用方 `SaveStatusView` 放在它下方（`caption` `status.destructive` 说明 + `FCButton`）。
- **复用边界**：只表示数据保存进度。需要教练处理的业务状态用 `DS-STATUS`；就地操作结果用 `DS-INLINE-RESULT`。代码已与规格对齐（M2 T007，CG-3）。

#### `DS-AVATAR` 头像

- **部件**：44×44 圆形 `surface.selected` 底 + 首字（`headline` `action.primary`）。装饰性，可访问名称由所在行提供。

#### `DS-CALENDAR-DAY` 月历日期格

- **部件**：日期数字（`compact`；选中时 600 `action.on`，放在 28pt `action.primary` 实心圆内；否则 400 `text.primary`）→ 下方 4pt 有课圆点（`action.primary`）。圆点的位置始终保留，所以有没有圆点时行高都一样；选中日不在圆内重复显示圆点。
- **不变量**：点击区 ≥ 44（自动）；有课信息通过 `accessibilityValue` 读出，不只靠圆点（可自动）。

#### `DS-SYMBOL` 系统图标

- **部件**：README §7.2 列出的 8 种字形（pageBack、back、forward、minus、plus、check、checkOnFill、collapse），每种都有固定的尺寸、字重和默认颜色；只有画稿给出状态色时才允许覆盖颜色。`‹ › ✓`（pageBack、back、forward、check、checkOnFill）渲染为随包 Noto Sans SC 字形（`FCFont.uiFont`，随动态字体缩放；产品负责人 2026-10-10 否决 SF Symbols 的通用对勾 / 箭头）；`− + ▾` 为 SF Symbol。`FCSetStateCircle`、`FCStatusBadge` 的 ✓ 同样使用该字形。
- **不变量**：feature 中不手写 `‹ › − + ✓ ▾` 字符，也不自行设置这些符号的尺寸（可自动：扫描 feature 源码）；默认装饰性，可点击时必须放在 ≥ 44 的点击区里，并由调用方提供可访问名称。

#### `DS-EQUIPMENT-ICON` 器材图标

- 18 个模板渲染图标，`action.primary` 着色，默认 24×24；没有对应图标的动作留空，不使用默认图标补位。L0 全自动（`IconConsistencyTests`）。

#### `DS-BODY-DIAGRAM` 训练部位示意图

- **部件**：正面图与背面图并排（每个宽 104，图下方有 `caption` 标签）→ 图例行（10pt 圆点 + 「主练 · …」「次要 · …」）。整体是一个无障碍元素，读出主练部位和次要部位。
- **不变量**：着色规则见 README §9.1；视图本身不含数据规则，只接收 `TrainedBodyPartsSummary`。

### 4.6 页面组合模式（由 feature 拼装，没有共享代码）

这些模式在多个页面重复出现。M1-B 中由 feature 各自拼装；M2 中如果再次用到，应优先抽取为共享组件（「新增（共享）」流程），见 CG-8。

| ID | anatomy | 画板 | 当前实现 |
|---|---|---|---|
| `DS-PAGE-PRIMARY` 一级页 | 顶部 `FCSegmentedSwitch`（今日 / 学员）→ 标题行：`display` 大标题（`action.primary`）+ 右侧 `DS-TITLE-ACTION` → 内容；隐藏系统导航栏。**查看模式变体**（M2，2026-10-09 G7 批准）：没有顶部分段切换，标题行只有设置齿轮，其余相同 | 01/21/40/41；M2-11 | Today、StudentList 各自拼装 |
| `DS-PAGE-SECONDARY` 二级页 | 隐藏系统导航栏（`.fcSecondaryPage()`，同时保持边缘右滑返回可用）→ 紧贴状态栏下方的页头：小号 `‹`（22/400 `text.secondary`）与页面内 `titleLarge` 标题在同一行、紧靠标题左侧（标题起点 x=32），整体由 `FCPageHeader` 绘制（带 header 属性）→ 可选副标题（`callout` 400 `text.secondary`）→ 内容 → 可选底部主按钮 | 23/26/28/36/37/38 | 约 20 个 feature 文件各自拼装；页头部分已有共享组件 `FCPageHeader`（§4.7），StudentDetail 已迁移 |
| `DS-HUB-ROW` 入口行 | 24pt 图标（`action.primary`）→ 标题（`headline`）/ 副标题（`caption` `text.secondary`）→ `›`；最小高 64，间距 `space.4` | 19/42/43 | 已提升为共享组件 `FCHubRow`（M2 T002/T010，2026-10-10）；ResourceHub、Settings 已迁移，规格见 §4.7 |
| `DS-INLINE-RESULT` 就地结果 | 22×22 `FCStatusBadge` → 标题（`callout` 600；失败为 `status.destructive`，成功为 `text.primary`）→ 说明（`caption` `text.secondary`）→ 失败时显示居中「重试」`FCLinkButton` | 38/39 | 已提升为共享组件 `FCInlineResult`（M2 T003/T011，2026-10-10）；BackupRestoreFlow 已迁移，规格见 §4.7 |
| `DS-EMPTY-STATE` 空态 | 吉祥物 220×220 居中 → 标题（`headline` `action.primary`）→ 说明（`caption` `text.secondary`）→ 底部主按钮 | 16 | StudentList |

### 4.7 已定稿规格（M2 Phase 0，T001–T012 已实现）

状态：**已审定**（2026-10-08 起草，2026-10-09 随 M2 G7 设计载体 review 通过；来源 `design/m2-hifi/implementation-map.md` §2）。已在 M2 tasks Phase 0 实现（2026-10-10），对应行已进入 §3 索引（`ComponentCatalogTests` 要求索引与 `DesignSystem/` 公开类型一一对应）。人工项（标「人工」的不变量）尚未经人工视觉检查。

#### `DS-PAGE-HEADER` 二级页页头（新增共享，CG-8）

状态：**已实现**（`FCPageHeader`，`TrailingAction` 描述尾部操作）。把 §4.6 `DS-PAGE-SECONDARY` 的页头部分做成组件，外观不变（C 类）。

- **部件**：可选内联返回 `‹`（`back:`，22/400 `text.secondary`，Noto Sans SC 字形 `FCSymbol(.pageBack)`；与标题首行基线对齐，布局宽 16，所以标题从 x=32 开始，实测 M2-02a/02b/03、M1 26/36 的 PNG：`‹` 墨迹 x 17–21.5、y 74–82.5，标题墨迹 x 32.5–33、y 58；点击区 44×44 以 overlay 方式覆盖在字形周围，不占布局；无障碍名称「返回」（`common.back`），标识由调用方传入；`handler` 为空时执行 `dismiss`，流程内的「上一步」传自己的 handler）。调用页用 `.fcSecondaryPage(swipeBackEnabled:)` 隐藏系统导航栏并保持（或在流程步骤页关闭）边缘右滑返回——系统导航栏隐藏后 `interactivePopGestureRecognizer` 会拒绝开始，所以该修饰符换上自己的 delegate（有上一页即允许），页面消失时恢复。无标题（`title: ""`）时只画返回与尾部操作（29 分享预览）→ 页面内标题（默认 `titleLarge`，训练中页用 `titleEmphasis`；`text.primary`，带 `.isHeader`）→ 可选副标题（`callout` 400 `text.secondary`，与标题间距 `space.2`）→ 可选尾部操作（与标题首行同一行右侧，`callout` 600 `action.primary` 文字按钮，例如 26「编辑资料」）。
- **状态**：只有静态内容；尾部操作可禁用（`text.disabled`）。
- **不变量**：标题带 header 无障碍属性（可自动）；尾部操作点击区 ≥ 44（可自动：`TouchTargetComponentTests` 扩展）；标题与副标题随动态字体换行，不截断（人工，组件引入时看一次）；尾部操作存在时标题宽度让出操作文字，标题换行而不是与操作重叠（人工）。
- **页头位置**：页头行盒顶 = 安全区顶 + `space.2`（8pt，`FCPageHeader` 自带上边距），不伸进状态栏。画稿标题墨迹顶 y=58（行盒顶约 y=52，落在状态栏安全区内），这是画稿绘制时状态栏占位不准，不是设计意图；以实现为准（产品负责人 2026-10-10 授权由实施方定）。理由：①iOS 惯例，状态栏下方留白，不与状态栏争视觉；②44×44 返回点击区以 22pt 字形为中心向上延伸约 11pt，留白后不与状态栏触控区（点按回到顶部）重叠；③全部二级页统一一个值，灵动岛 / 非灵动岛机型都相对安全区计算。
- **复用边界**：所有二级页页头都用它；一级页（今日、学员、查看模式首页）不用，见 `DS-PAGE-PRIMARY`。35 训练记录详情把「训练记录」放在导航栏 inline 标题、页面内是日期与训练标题，这是 35 自己的组合，不属于本组件。
- **迁移范围**：M2 新页面全部使用；2026-10-10 产品负责人走查发现系统导航栏的返回按钮（iOS 26 液态玻璃大圆钮）单独占一行、标题被挤到下一行，与画稿不符，所有 `titleLarge` 二级页（动作库、设置、资料库、日历、课包、课时调整、预约编辑、学员编辑 / 详情 / 已归档、趋势、训练历史、模板、备份、身体数据、分享报告 2 页、M2 导出流程）统一迁移到 `FCPageHeader` + `.fcSecondaryPage()`。训练中（`ActiveSessionView`，11/30）同样改为内联返回，标题保持 22/700（`titleStyle: .titleEmphasis`，产品负责人 2026-10-10：返回方式全 App 一致，以后发现不一致直接改）。仍使用系统导航栏的只有标题放在导航栏的页面（35 训练记录详情等，返回与居中标题同一行）。

#### `DS-HUB-ROW` 入口行（由组合模式提升为共享组件，CG-8）

状态：**已实现**（`FCHubRow`；`mode` 取 `.action` / `.informational` / `.unavailable(reason:)`，不可用态在类型上没有 action 与 `›`）。外观沿用 19/42/43（C 类）；新增尾部说明与不可用态（B 类，M2-11 首次使用）。

- **部件**：leading 24pt 线性图标（`action.primary`，装饰性）→ 标题（`headline`）/ 可选副标题（`caption` `text.secondary`，可换为 `FCStatusLabel`，如 43 通知被拒）→ 弹性空白 → 可选尾部说明（`caption` `text.secondary`，例如「24 次」）或尾部操作文字（`callout` 600 `action.primary`，如 43「前往设置」）→ 可选 `›`。最小高 64，图标与文字间距 `space.4`；行间由调用方放 `FCListRowDivider`。
- **变体 / 状态**：可点（带 `›`）；不可点（无 `›`，如 42「关于」）；**不可用**（新）：图标与标题改为 `text.disabled`，尾部说明写原因（如「档案未包含」），无 `›`，整行不可点，读作「标题，原因」。
- **不变量**：带 action 时整行可点（可自动）；不可用态没有点击动作（可自动）；整行合并为一个无障碍元素，读出标题、副标题与尾部说明（可自动）；点击区 ≥ 44（自动）。
- **复用边界**：用于入口列表页（资料库 19、设置 42、首次启动二选一 M2-07、查看模式首页 M2-11）。操作区里的单行操作用 `DS-ACTION-ROW`，普通内容列表用 `DS-LIST-ROW`。
- **迁移范围（Phase 0）**：ResourceHub `hubRow`、Settings `row` 改用本组件，外观不得改变。

#### `DS-INLINE-RESULT` 就地结果（由组合模式提升为共享组件）

状态：**已实现**（`FCInlineResult`；`Variant` 恰好 `failure` / `success` / `info`，`Retry` 描述重试）。失败 / 成功沿用 38/39（C 类）；新增信息变体（B 类）。

- **部件**：22×22 `FCStatusBadge` → 标题（`callout` 600）→ 说明（`caption` `text.secondary`，换行不截断）→ 可选居中「重试」`FCLinkButton`。图标与标题同一行，说明在标题下方左对齐。
- **变体**：失败：`status.destructive` +「!」，标题 `status.destructive`；成功：`action.primary` + ✓，标题 `text.primary`；**信息**（新）：`action.primary` +「i」，标题 `text.primary`，用于不是错误、但流程没有完成的结果（例如「已取消，未交付」）。三种变体都可以带或不带「重试」。
- **不变量**：恰好 3 个变体，每个都有字形和标题（可自动）；徽标对无障碍隐藏，标题与说明合并为一个元素，「重试」单独可访问（可自动）；「重试」点击区 ≥ 44（自动）。
- **复用边界**：只表示一次操作在当前页面的结果。需要教练处理的持续业务状态用 `DS-STATUS`；保存进度用 `DS-SAVE-STATUS`。
- **迁移范围（Phase 0）**：BackupRestoreFlow 的失败 / 成功状态改用本组件，外观不变。

#### `DS-LIST-ROW` 扩展（CG-1）

状态：**已实现**（`FCListRow` 三个入口：`showsDisclosure`+`action`、`isSelected`+`toggle`、`FCListRow.unavailable(…reason:)`；分组变体为 `FCListGroupRow`，三态由 `childSelections` 计算）。

在 §4.3 现有 anatomy 上增加 slot 与状态（B 类，M2 首次使用；`FCListRow` 目前 0 个消费者，无回归面）：

- **部件**（新增项标「新」）：左边距 16 →（新）可选 leading：24×24 `DS-EQUIPMENT-ICON`，与文字间距 `space.3`；leading slot 启用但该行没有图标时保留空位，使文字对齐 →（新）可选缩进：子行文字左移 `space.4`（x=32，子行分割线同样从 x=32 开始，`FCListRowGeometry.indent`）→ 主文字 → 可选元信息（新：允许多行，换行不截断，用于自由文本预览）→ 弹性空白 →（新）可选尾部说明（`caption` `text.secondary`）→ 尾部二选一：`›`，或（新）勾选圈（外观复用 `FCSetStateCircle`：未选为待完成描边、已选为实心 + ✓，与 28/32 一致）。
- **状态**（新）：已选 / 未选（勾选圈变体，整行点击切换，带 `.isSelected`）；**不可用**：主文字 `text.disabled`，尾部说明写原因，不显示勾选圈与 `›`，整行不可点，读作「标题，原因」。
- **分组变体**（新，M2-02）：主文字 `headline` → 尾部说明 → 展开符号（`FCSymbol(.collapse)`，展开时朝上）→ 三态勾选圈：全选（实心 + ✓）、**部分选中**（`action.primary` 实心 + 白色「−」，复用 `FCSymbol(.minus)` 字形）、全不选（描边）。两个点击区：勾选圈切换整组（≥ 44×44），行的其余部分展开 / 折叠；展开后子行用缩进变体排在分组行下方。无障碍：分组行读作「标题，说明，已全选 / 部分选中 / 未选，已展开 / 已折叠」，提供「切换选择」「展开 / 折叠」两个动作。
- **不变量**：部分选中只由子项状态推导，不能单独设置（类型保证：分组状态是计算值）；勾选圈变体的整行是一个点击目标（分组变体除外，见上），点击区 ≥ 44（可自动）；已选状态通过 `.isSelected` 读出，不只靠勾选圈外观（可自动）；不可用态没有点击动作（可自动）；`›` 与勾选圈不同时出现（类型保证）。
- **迁移范围（Phase 0）**：M2 新页面使用；M1 只迁移 M2 查看模式会复用的列表（训练历史结果行 32、身体数据指标行 06）。其余 CG-1 列出的私有行不迁移。

#### `DS-ACTION-ROW` 扩展：destructive 图标

状态：**已实现**（`FCActionRow(…, showsTrashIcon:)`，仅 `destructive` 生效，默认关闭）。

B 类，M2-18「删除本机档案」首次使用。spec NFR-005（M2）要求危险删除同时用文字和图标表达，现有 destructive 行只有红字。

- **部件**（新增）：destructive 变体可选 leading 图标：24×24 线性垃圾桶（SF Symbol `trash`），`status.destructive`，装饰性；标题右移到 x=48。普通变体不使用该 slot。
- **不变量**：图标对无障碍隐藏，可访问名称仍是标题（可自动）；图标与标题同色（可自动：源码断言）。
- **迁移范围**：现有 10 个消费者不传图标，外观不变；是否给 M1 的 destructive 行（如编辑资料「永久删除」）补图标，不在 M2 范围。

#### `DS-CONFIRM-DIALOG` 内容变长规则（CG-6）

状态：**已实现**（`FCConfirmationDialog` 内部实现，调用方不传尺寸）。

C 类，只补规则，默认字号下外观不变：

- 卡片宽度保持 300（屏宽不足 300 + 2×`space.4` 时取屏宽减 2×`space.4`）；高度随内容增长，超过屏高的 80% 时说明区内部滚动，标题与按钮行固定。
- 标题、说明换行不截断。
- 两个按钮文字在动态字体放大后任一放不下一行时，按钮行改为上下堆叠：确认在上、取消在下，各自占满卡片内宽，视觉高度随文字增长，最小点击区仍为 44。
- **不变量**：上述规则在组件内实现，调用方不传尺寸（可自动：源码扫描调用方没有 `.frame(width:)`）；堆叠时的视觉在组件修改时看一次（人工）。

## 5. 缺口与偏差登记

编号 CG-1–CG-9（Component Gap）是本文自己的登记编号（2026-10-05 盘点时建立），不来自 `roadmap.md` 或任何 spec / tasks；加前缀是为了不与路线图的评审门 G1–G7 混淆。处理方式按 §1.2 分类；需要改代码的条目安排在 M2 Phase 0（已写入当前交接文档）。

| # | 缺口 | 证据 | 状态 / 处理 |
|---|---|---|---|
| CG-1 | `FCListRow` 没有消费者；feature 中至少 10 个私有 `xxxRow` 各自拼装行结构 | Today `nextUpRow` / `compactRow`、Calendar `appointmentRow`、StudentList `activeRow` / `archivedRow`、TemplateList `templateRow`、BodyData `metricRow`、BodyMeasurementEntry `historyRow`、CreditAdjustmentTrail `adjustmentRow`、TemplateEditor `exerciseRow` 等 | **M2 Phase 0**：先扩展 `FCListRow` 的 slot（leading 图标 / 头像、trailing 状态），只迁移 M2 会读取或改动的页面（见下方「M2 影响」）；其余页面不动。扩展规格已起草（§4.7，2026-10-08，随 G7 review 审定） |
| CG-2 | `FCWeekdayChip`、`FCTypeTag` 没有消费者 | 02 的星期多选已被 23 取代；15 的「有氧」标签从未实现 | **已解决（2026-10-05）**：代码与 README §8 两行删除（README §10 C13） |
| CG-3 | `FCSaveStatusView` 未显式声明字体（继承 App 根部 `.fcFont(.body)`，渲染为 Noto Sans SC 17/400）；状态文字是写死的中文 `rawValue`，不是本地化键 | `FineCoachApp.swift:20`、`FCSaveStatusView.swift` | 规格**已补**（§4.5、README §8，§10 C12）。**已解决（M2 T007，2026-10-10）**：显式写 `.fcFont(.body)` 并改用本地化键（D 类，外观不变） |
| CG-4 | `FCSetRow` 的状态文字写死在 `rawValue` 中 | `FCSetRow.swift` | 本地化问题，与视觉无关；下次修改该组件时处理 |
| CG-5 | CoursePackageEditor、ManualCreditAdjustment 各有私有 `editorRow`，与 `FCLabelValueRow` 职责重叠 | 两个文件中的 `editorRow` | 只在这两个页面被修改时迁移；M2 不涉及课包，不安排 |
| CG-6 | `FCHeroCard` 徽标固定 56 宽、`FCConfirmationDialog` 固定 300 宽，字号放大时的规则没写 | 两个组件源码 | 下次涉及时先补「内容变长」规则（C 类）；M2 若使用确认弹窗（删除档案、替换档案），在 Phase 0 补规则。确认弹窗规则已起草（§4.7，2026-10-08）；M2 不使用 hero 卡，徽标规则不处理 |
| CG-7 | `FCSegmentedSwitch` 在页内使用超出 README 原定义 | 37 画稿 | **已解决（2026-10-05）**：裁决为已批准的复用，限 2–3 个互斥短选项（README §10 C11） |
| CG-8 | 二级页头 `DS-PAGE-SECONDARY` 约 20 处手工拼装；入口行 `DS-HUB-ROW` 有两份（ResourceHub、Settings） | 约 20 个 feature 文件直接写 `.fcFont(.titleLarge)` 页头；`hubRow` 与 Settings `row` | **M2 Phase 0**：抽取共享 `FCPageHeader`（及入口行，如 M2 设置页用到），补组件测试；只迁移 M2 改动的页面。`DS-PAGE-HEADER`、`DS-HUB-ROW` 规格已起草（§4.7，2026-10-08，随 G7 review 审定） |
| CG-9 | 组件文件中没有任何 `#Preview` | `ios/FineCoachApp` 中搜索不到 `#Preview` | 规则而非一次性任务：新增或扩展组件时，在组件文件里加覆盖代表状态的 `#Preview`（只在 DEBUG 下编译，不新增 target），供 L3 查看组件时使用 |

**M2 影响（CG-1 / CG-8 为什么需要处理）**：M1 已验收不等于 M2 不碰这些代码。M2 spec（`specs/003-m2-personal-training-archive/spec.md`）明确要求：
- 学员详情新增「导出个人训练档案」入口（M2-FR-006）——要改 `StudentDetailView`，它的各区块和页头都是手工拼装；
- 首次启动改为「Coach 使用 / 导入个人训练档案」二选一（M2-FR-025，spec 自述改写 M1-A 行为）——要改 `OnboardingView`；
- 档案查看模式只读浏览训练记录、身体数据、趋势与个人最佳（M2-FR-030）——要么给 `HistoryListView`、`BodyDataListView`、`TrendsView` 等加只读形态（改 M1 文件），要么新写一套查看页面（会再复制一遍上面那些私有行和页头）。

两条路都会落在 CG-1 / CG-8 的手工拼装代码上；第二条路的跑偏风险最高，因为它会产生「看起来一样、实际各写一份」的第三、第四份行结构。所以在 Phase 0 先把行和页头收进共享组件，M2 页面只做拼装。M2 不涉及的 M1 页面（课包、日历、模板、备份等）不在本轮迁移，以免改动已验收界面却没有收益。

## 6. Feature 实施映射（每个里程碑一份）

从 M2 开始，每个里程碑在它的高保真目录中维护一份 `implementation-map.md`（例如 `design/m2-hifi/implementation-map.md`），只写该 feature 自己的内容：

1. 本里程碑的设计来源：画板编号、Penpot 快照、导出图路径。
2. 页面 → 组件清单：每个页面由哪些 `DS-*` 组件按什么顺序组成；列出复用 / 扩展 / 新增的分类。
3. feature 专有组件的 anatomy（格式同 §4）。
4. 每个页面的代表状态（默认、空、错误、长文本、字号放大），以及每个状态由哪个组件负责呈现。
5. 核心页面清单（L3 触发条件 3）及其理由。
6. 执行记录（§1.5）和验证结果。

实施映射不复制 README 的数值，也不复制本文的共享 anatomy；需要时用 ID 引用。

新画板在 Penpot 中绘制时，组件图层按 README §1.3 的方式标注（图层名「DS-xxx · 部件」，shared plugin data `finecoach.component` / `part`），feature 专有组件用实施映射中的 ID。这样 Agent 读取 Penpot 时可以直接按 ID 找到对应的组件规格。
