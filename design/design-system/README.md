# FineCoach 设计系统（G5「暖炭黑素雅」）

> 状态：v1.0（2026-09-22 产品负责人批准）。修订历史：v0.2 按产品负责人决定修复了评分卡的定量扣分项（O1/O2/O3/O5、C10），全部待确认项已关闭；v0.3 已把全部画稿修改回填到 Penpot 源文件，并在本仓库重新导出 17 屏（§1.1）。
> 作用：FineCoach iOS 界面视觉的**唯一实现依据**。后续 spec / plan / tasks 与代码（`ios/FineCoachApp/DesignSystem/`）都引用本文，不再各自转述设计数值。

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
- 导出：本仓库 `design/m1-b-hifi/screens/`，文件名沿用旧版（`01-today.png` … `17-icons.png`）。2 倍图，01–16 为 780×1688，17 为 1120×1040。04、06、07、08、12 这 5 块画板上的展示投影在导出时临时去掉、导出后立即恢复，所以导出图不含投影边距。

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
| `color.border.control` | neutral.500 | `#8E897F` | 可交互控件的描边，例如待完成组圆圈；对白底 3.48:1。画稿原用 `#ECE9E2` |
| `color.surface.selected` | brand.subtle | `#EDE9E2` | 未选中的二选一/胶囊底、头像底、提示条底、弹窗次按钮底 |
| `color.text.primary` | neutral.900 | `#211F1B` | 正文、列表主文字、数值 |
| `color.text.secondary` | neutral.600 | `#5C5A52` | 辅助文字、字段标签、区段标签、箭头 |
| `color.text.disabled` | neutral.400 | `#A8A39A` | 画稿未使用，保留给禁用态 |
| `color.text.onActionSecondary` | —（画稿补充） | `#B0ABA2` | 深色 hero 卡内的次要文字（01「已训练 32 分钟」）。原不在 Penpot token 集中，已按画稿补入 |
| `color.status.success` | green.600 | `#2A2822` | 成功/完成状态 |
| `color.status.warning` | amber.700 | `#B45309` | 逾期、时间冲突图标底 |
| `color.status.destructive` | red.700 | `#D4442A` | 失败、破坏性操作文字（O1） |

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

- 共 15 个：barbell、bike、bodyweight、cable-crossover、cable-machine、dumbbell、hack-squat、jump-rope、kettlebell、pec-deck、resistance-band、rowing-machine、shoulder-press、smith-machine、treadmill。
- 规格：viewBox 24、描边 2、圆角端点与圆角转角、无填充、描边色 `#2A2822`。
- 已导入 `ios/FineCoachApp/Resources/Assets.xcassets/equipment-*.imageset`（2026-09-22 核对，与原件逐字节一致），并设置为 template 渲染，着色用 `action.primary`。
- 用途：动作库、训练中动作行。11 屏的动作行图标为 24×24，位于左边距 16 处，动作名右移到 x=48（O4）。
- 展示尺寸：24 画布下描边 2；放大显示时描边按比例放大（17 屏 36×36 的描边为 3）。

### 7.2 系统图标

画稿中用文字字符表示的图标，实现时换成对应的系统图标（SF Symbols），颜色和视觉尺寸按画稿：

| 画稿字符 | 画稿样式 | 用途 |
|---|---|---|
| `‹` | 22/400 或 20/400，`text.secondary` | 返回、上一月 |
| `›` | 20/400，`text.secondary` | 列表行进入、下一月 |
| `− / +` | 20/600 | 课时扣减/返还记录 |
| `✓` | 13/600 白色（圆内）或 15/600 `action.primary` | 已完成、已包含 |
| `▾` | 15/600 `action.primary` | 分区折叠 |
| `! / i` | 14/600 白色，放在 22×22 圆内（底色 `status.warning` 或 `action.primary`） | 状态图标 |

所有可点击图标的触控区域不小于 44×44。

## 8. 组件规格（来自 17 屏实测）

| 组件 | 规格 |
|---|---|
| 主按钮（页面底部） | 358×52，`radius.md`，底色 `action.primary`，按下 `action.pressed`；文字 `headline` 白色 |
| 次按钮（样张） | 白底，1.5pt `action.primary` 描边，`radius.md`；文字 `headline` `action.primary` |
| 链接式按钮 | 无底色，文字 `callout` 600 `action.primary`（例：「＋ 添加动作」「＋ 自定义指标」「重试」） |
| 顶部分段切换（今日 / 学员） | 选中项 50×32 胶囊，`action.primary` 底 + `headline` 白字；未选中项为纯文字 `body` `text.secondary` |
| 筛选胶囊（07） | 高 30 胶囊；未选中 `surface.selected` 底 + `chipLabel` `text.primary`；选中 `action.primary` 底 + 白字 |
| 星期多选（02） | 64×28 胶囊，选中/未选中配色同筛选胶囊 |
| 开关 | 44×26 胶囊，开启 `action.primary`、关闭 `surface.divider`；滑块 18×18 白色圆 |
| 深色 hero 卡（01） | 358×100，`radius.lg`，`action.primary` 底；内含徽标（56×24 胶囊，`surface.canvas` 底，`sectionLabel` `action.primary` 字）、`headline` 白字标题、`text.onActionSecondary` 副文字、`callout` 600 白字操作。每屏最多一个 |
| 列表行 | 左 16；主文字 `headline` 或 `body`，元信息 `caption` `text.secondary`，右侧 `›`；行间用 1pt 分割线 |
| 区段标签 | `sectionLabel`，`text.secondary` |
| 头像 | 44×44 圆，`surface.selected` 底，首字 `headline` `action.primary` |
| 搜索框 | 358×40，`radius.sm`，`surface.canvas` 底，占位文字 `callout` 400 `text.secondary` |
| 输入框（08） | 358×48，`radius.sm`，`surface.canvas` 底（与搜索框一致）；占位文字 `callout` 400 `text.secondary`（对 `#F7F4EE` 6.29:1）。画稿原为白底无描边，边界不可见（O3） |
| 提示条 | 358×44，`radius.md`，`surface.selected` 底，`caption` `action.primary` 字 |
| 类型标签（15「有氧」） | 48×24 胶囊，`surface.selected` 底，`sectionLabel` `action.primary` 字 |
| 组状态圆圈 | 22×22，见 §6 |
| 确认弹窗 | 宽 300（屏内）/ 320（样张），`radius.lg`，白底；标题 `headline`，说明 `caption` `text.secondary`；两个 36 高按钮，`radius.dialogAction`：取消/保守选项 `surface.selected` 底 + `callout` 600 `action.primary`，确认选项 `action.primary` 底 + 白字 |
| 空态（16） | 吉祥物插图 220×220 居中 → 标题 `headline` `action.primary`「还没有学员」→ 说明 `caption` `text.secondary` → 底部主按钮「＋ 新建学员」 |
| 通知预览（样张） | 36×36 圆角 9 炭黑图标；标题 `callout` 600，正文 `caption`；只写通用文案和时间，不写姓名/性别/课包 |

**导航**：画稿中一级页面（今日 / 学员）通过顶部胶囊切换，17 屏里没有底部 Tab 栏；二级页面左上角是返回 `‹` 加 `titleLarge` 标题。

## 9. 插图资产

| 资产 | 文件 | 来源核验 |
|---|---|---|
| 吉祥物（空态） | `assets/mascot-empty-state.jpeg`，1024×1024 | 与 Penpot 内嵌原图 `inset-warm2.jpeg` 逐字节一致（276383 字节，SHA-256 `aca587ee…d87395b`） |

吉祥物只用于空态插图，画稿显示尺寸为 220×220。

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
| `#8E897F` border.control（非文本） | `#FFFFFF` | 3.48 | 通过（O2 修复后；原值 `#ECE9E2` 为 1.21） |
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
| 器材图标 | 已导入 15 个，代码中 0 处引用 | 接入动作相关界面（§7.1） |
| 吉祥物 | 不存在 | 空态使用（§9） |
| 自动化校验 | `VisionHarnessTests` 只锁定 9 个颜色和 2 个间距 | 扩展到 §2–§5 的全部 token 值和 §11 的对比度 |
