# M2 个人训练档案：高保真实施映射

> 状态：**已批准**（2026-10-08 起草；2026-10-09 产品负责人 review 通过，G7 整体通过）。本文按 [`components.md`](../design-system/components.md) §6 编写，只写 M2 自己的内容：设计来源、页面 → 组件清单、feature 专有组件、代表状态、核心页面候选与执行记录。数值以 [`README.md`](../design-system/README.md) 为准，共享组件结构以 `components.md` 为准，本文只用 ID 引用。
> 行为权威：`[specs] 003-m2-personal-training-archive/spec.md`（`1.1-approved`，2026-10-08 修订 1.1；PRD `1.2-approved`）。本文与 spec 的行为边界冲突时以 spec 为准；设计载体不增加字段、状态、流程、权限、角色或媒体（spec §12）。

## 1. 设计来源

| 项 | 位置 |
|---|---|
| Penpot 文件 | 「M1-B G5 Design」→ 新页面「M2 G7 Design」（与 Foundations 同文件，沿用同一套 token 与已标注的组件图层；决定见 2026-10-05 交接） |
| Penpot 快照 | 绘制前 `before-M2-G7-design 2026-10-08`（revn 181）→ `M2-G7-design-draft 2026-10-08 (24 boards, pending review)`（快照名中的「24」是笔误，实际 26 块）→ `M2-G7-design-draft r2 2026-10-08 (26 boards; 06d spacing; destructive trash icon)`（revn 200）→ review 第 1 轮后 `M2-G7-design r3 2026-10-09 (review round 1: …)`（重画 02a、02b、03、06a–d、08a、08b、19b）→ `M2 G7 design approved 2026-10-09 (core pages M2-02, M2-11)`（revn 215）。每次 `File.validate()` 均为 0 个错误 |
| 画板命名 | `M2-NN 页面名 · 状态`，与导出图文件名一一对应 |
| 导出图 | `design/m2-hifi/screens/M2-NN-*.png`，共 26 张。2 倍图（宽 780，规格同 README §1.1）。2026-10-09 由产品负责人在 Penpot 用画板上的 2 倍导出预设一次批量导出，按画板编号覆盖同名文件（Penpot MCP 的 `export_shape` 没有倍率参数，只能出 1 倍图） |
| 行为输入 | spec §12 输入范围 1–6；低保真原型 `design/prototypes/m2/01-archive-export`、`02-viewer-mode` 只作 discovery 证据，其中的英文领域词、「课程记录」、文件名含姓名、4 位密码、底部 Tab 栏、动作静态图占位一律不采用 |

### 1.1 产品负责人在起草时的决定（2026-10-08）

| # | 问题 | 决定 |
|---|---|---|
| H1 | 查看模式导航 | 档案首页是入口列表：大标题 + 标题行设置齿轮 + 入口行；各模块为二级页，带返回。**不引入底部 Tab 栏**（设计系统没有该组件，避免 A 类新组件） |
| H2 | 交付前确认（M2-FR-013 的 6 条事实） | 6 条逐条列出、每条带图标，底部**一次**明确确认「我已了解，设置密码」；不逐条勾选 |
| H3 | 首次启动二选一 | 吉祥物 + 标题 + 两个入口行（图标、标题、说明、`›`），两个选项视觉权重相同 |

**G7 设计载体 review 第 1 轮（2026-10-08）**：

| # | 问题 | 决定 |
|---|---|---|
| R1 | M2 字体看起来和 M1 不同 | 核实：Penpot 文字图层的字体、字号、字重、行高、字距与 M1 完全一致；差异来自导出倍率（M2 为 1 倍、M1 为 2 倍）和 13 号灰字过密。定稿后补 2 倍图；导出页按 R2 精简 |
| R2 | 导出页过于复杂 | 三组（基本资料、训练内容、身体数据）、默认折叠、**默认全部选中**，组内可逐项取消。行为修订：PRD 修订 1.2、spec 1.1（M2-FR-007、M2-FR-049、AC-001、D-015） |
| R3 | 线框次按钮与其他控件风格不一 | M2-06 只留一个主按钮「交给系统…」，打开 iOS 分享面板（含「存储到『文件』」）；M2-08 / M2-19b 把「选择档案文件」按钮与文件行合并为一行可点的 `DS-LABEL-VALUE-ROW`「档案文件 … ›」。M1 的 38 不改 |
| R4 | M2-09 的进入路径 | 支持从系统（「文件」App、AirDrop、其他 App）用 FineCoach 打开档案文件，按安装状态分流；Coach 模式显示 M2-09。spec D-010 已修订 |
| R5 | M2-13 页头与其他页面不一致是否符合预期 | 符合预期：M2-13 沿用 M1 已批准的 35 训练记录详情（导航栏 inline「训练记录」+ 页面内日期与训练标题），页面内大字是这次训练的标题而不是页面名，所以不用 `DS-PAGE-HEADER`；实现上复用 `SessionDetailView` 的只读形态，避免同一页面出现两种页头。不改 |
| R7 | 界面文案中的品牌名（2026-10-10，产品负责人） | 学员只读导入是「精练教练」App 的子功能，品牌统一：中文界面文案一律写「精练教练」（与主屏幕显示名 `CFBundleDisplayName` 一致），不写英文名 FineCoach。M2-03、M2-04 第 3 条、M2-06a–d、M2-07 标题、M2-09、导入失败「版本不兼容」文案已改；Penpot 快照 `welcome-r3-brand 2026-10-10 (…)`（revn 266）。对应 2 倍导出图待重新导出 |
| R6 | 整体 review | 2026-10-09 通过；核心页面定为 M2-02、M2-11。Penpot 画布布局由产品负责人手动调整过（M2-03 过长遮挡 M2-09），只改画板位置，不影响内容 |


## 2. 分类（`components.md` §1.2 / §1.3）

M2 整体属于「复用现有组件 + 少量扩展 / 新增」。没有页面属于 A 类（不需要新的视觉语言）。

| 组件 | 范围 | 设计变化类别 | 说明 / 受影响的现有消费者 |
|---|---|---|---|
| `DS-PAGE-HEADER`（新增共享，CG-8） | 新增 | C（把已批准的 `DS-PAGE-SECONDARY` 页头写成组件，外观不变） | 规格见 `components.md` §4.7。M2 全部二级页使用；M1 只迁移 M2 改动的 `StudentDetailView` |
| `DS-HUB-ROW`（由页面组合模式提升为共享组件，CG-8） | 新增 + 扩展 | C（外观沿用 19/42）+ B（新增「尾部说明」与「档案未包含」不可用态） | M1 消费者 ResourceHub `hubRow`、Settings `row` 在 Phase 0 迁移时外观不得改变 |
| `DS-INLINE-RESULT`（由页面组合模式提升为共享组件） | 新增 + 扩展 | C（失败 / 成功沿用 38/39）+ B（新增「信息」变体：`action.primary` +「i」，用于「已取消」） | M1 消费者 BackupRestoreFlow |
| `DS-LIST-ROW`（扩展，CG-1） | 扩展 | B（新增 leading 图标、尾部说明、尾部勾选圈与部分选中态、分组行（展开 / 折叠）、不可用态、多行副文字） | `FCListRow` 目前 0 个消费者，无回归面 |
| `DS-ACTION-ROW`（扩展） | 扩展 | B（destructive 变体新增可选 leading 图标，M2-18 首次使用） | 现有 10 个消费者不传图标，外观不变 |
| `DS-CONFIRM-DIALOG`（补规则，CG-6） | 扩展 | C（只补「内容变长」规则，外观不变） | CoursePackageList、CourseActionSheet、TemplateEditor：默认字号下外观不变 |
| `DS-PAGE-PRIMARY`（组合模式变体） | 扩展 | B（查看模式首页：去掉顶部分段切换，其余同一级页） | 无（只是新增变体） |
| 其余 `DS-*` | 复用 | C | 见 §3 各页清单 |

feature 专有组件见 §4。共享组件的新增 / 扩展条目写在 `components.md` §4.7（已定稿、待 Phase 0 实现）；它们的**代码**属于 M2 tasks Phase 0，G7 整体通过并完成 plan 之后才写。

## 3. 页面 → 组件清单

页面左右边距 `space.4`，底色 `surface.page`（`DS-BASE`）。「顺序」是从上到下的视觉与阅读顺序。没有写明的二级页页头都是 `DS-PAGE-HEADER`。

### 3.1 导出（Coach 模式，spec §12 输入 1–2）

| 画板 | 页面 | 组件顺序 | 代表状态 | 关键 FR |
|---|---|---|---|---|
| M2-01 | 学员详情 · 导出入口（修改 26） | 同 26；「记录」区段在「身体数据」之后加一行 `DS-ACTION-ROW`「导出个人训练档案 ›」 | 默认；已归档学员同样显示该行（D-006） | M2-FR-006 |
| M2-02a | 选择导出内容 · 默认 | `DS-PAGE-HEADER`（标题「导出个人训练档案」，副标题「王小明 · 档案只包含这名学员的数据」）→ `DS-SECTION`「包含内容」→ 3 行分组行（`DS-LIST-ROW` 分组变体：标题 `headline`、尾部说明、展开符号 `▾`、三态勾选圈）+ 分割线：基本资料「姓名、性别」、训练内容「24 次训练 · 4 项」、身体数据「3 项指标」→ `M2-EXCLUSION-NOTE`（一行）→ `DS-BUTTON` 主按钮「预览」 | 默认：三组全部选中、全部折叠 | M2-FR-007、049、010 |
| M2-02b | 选择导出内容 · 展开与部分选中 | 同 02a；「训练内容」展开为 4 个子行（缩进，`body` 标题 + 尾部说明 + 勾选圈）：训练记录「24 次」、趋势与个人最佳、学员课后总结「3 条」、动作资料「16 个动作 · 不含图片」；「身体数据」展开为 3 个指标子行，其中「肩宽（自定义）」取消，分组勾选圈显示部分选中「−」、尾部说明「2 / 3 项指标」 | 展开；部分选中；子项依赖不满足时的不可用态写法同前（D-005、D-009、D-015），本画板未画 | M2-FR-049；D-003、D-015 |
| M2-03 | 预览档案内容 | `DS-PAGE-HEADER`（「预览档案内容」，副标题「以下就是档案里的全部内容」）→ 每个已选模块一个区段：`DS-SECTION` + `DS-LABEL-VALUE-ROW`（姓名、性别；训练记录「范围」「条数」；动作资料「内置动作 N 个（名称、肌群、器材）」；趋势与个人最佳「计算范围：只用本档案的训练记录」（D-009）；身体数据每项指标「N 次测量 · 单位」）→ 自由文本逐条 `DS-LIST-ROW`（自定义 / 仅本次动作名称原文、学员课后总结原文；多行，不可点）→ `DS-STATUS` 自由文本（「i」+「精练教练 不会自动识别文字里的敏感内容，请逐条检查后再继续。」）→ 主按钮「继续」 | 与 M2-02b 一致：基本资料、训练内容全部、身体数据 2 项；未选动作资料时训练记录区段下方加占位说明「动作显示为「动作 1」「动作 2」…」 | M2-FR-008、012；D-001、D-009、D-014 |
| M2-04 | 交付前确认 | `DS-PAGE-HEADER`（「交付前确认」，副标题「请确认以下事实后再设置密码」）→ 6 行 `M2-FACT-ROW`（§4.3；前 3 条警示「!」`status.warning`，后 3 条信息「i」）+ 分割线 → 主按钮「我已了解，设置密码」 | 默认 | M2-FR-013、014；H2 |
| M2-05 | 设置档案密码 · 不一致 | `DS-PAGE-HEADER`（「设置档案密码」）→ `DS-TEXT-FIELD` 遮蔽输入「设置密码」→ `DS-TEXT-FIELD` 遮蔽输入「再次输入密码」→ `caption` 规则「至少 8 个字符。密码不会被保存，也无法找回，请通过其他方式单独告诉学员。」→ `DS-INLINE-RESULT` 失败（「两次输入的密码不一致」/「档案尚未生成」，无「重试」）→ 主按钮「生成档案」 | 两次输入不一致（同一位置也承载「少于 8 个字符」） | M2-FR-015～018 |
| M2-06a | 交付档案 · 已生成 | `DS-PAGE-HEADER`（「交付档案」，副标题「王小明的个人训练档案」）→ `DS-INLINE-RESULT` 成功（「档案已生成」/「文件名不含学员姓名或其他资料。」）→ `DS-BUTTON` 主按钮「交给系统…」（打开 iOS 系统分享面板，面板里可以「存储到『文件』」或交给其他 App）→ `caption`「在系统面板中可以存到「文件」或发给其他 App。精练教练 不托管文件，也不生成公开链接。」 | 已生成，未交付 | M2-FR-020～022 |
| M2-06b | 交付档案 · 已交给系统 | 同 06a，结果换为成功「已交给系统」/「这不代表学员已收到或已导入」；按钮换为主按钮「完成」（页面底部） | 已交给系统 | M2-FR-022；D-011 |
| M2-06c | 交付档案 · 已取消 | 同 06a，结果换为信息变体「已取消，未交付」/「临时文件已清理。可以重新交给系统。」；「交给系统…」保留，作为重试入口 | 系统面板被取消 | M2-FR-023 |
| M2-06d | 交付档案 · 交付失败 | 同 06c，结果换为失败变体「交付失败」/「系统没有接管文件，临时文件已清理。可以重新交给系统。」 | 系统写入或分享失败 | M2-FR-023 |

### 3.2 首次启动与导入（spec §12 输入 3）

| 画板 | 页面 | 组件顺序 | 代表状态 | 关键 FR |
|---|---|---|---|---|
| M2-07 | 首次启动二选一 | 无页头 → 吉祥物 220×220 居中（`DS-EMPTY-STATE` 的插图部件）→ `headline` `action.primary` 标题「你打算怎样使用精练教练？」→ `caption` 说明「两种方式互斥，之后不能直接切换」→ `FCListRowDivider` → `DS-HUB-ROW`「Coach 使用」/「管理学员，记录训练」→ 分割线 → `DS-HUB-ROW`「导入个人训练档案」/「只读查看教练交给你的档案」→ 分割线 | 默认；删除档案后也回到这里（M2-FR-050） | M2-FR-025；H3 |
| M2-08a | 导入档案 · 已选文件 | `DS-PAGE-HEADER`（「导入个人训练档案」，副标题「档案只读，导入后不能编辑」）→ 可点的 `DS-LABEL-VALUE-ROW`「档案文件 / 个人训练档案 · 9月25日 ›」（未选时值为「未选择」`text.secondary`，点击打开系统文件选择器；从系统打开文件进入时已预填）→ `DS-TEXT-FIELD` 遮蔽输入「输入档案密码」→ 主按钮「导入」 | 已选文件、待输入密码 | M2-FR-016、028 |
| M2-08b | 导入档案 · 失败 | 同 08a；主按钮下方 `DS-INLINE-RESULT` 失败「导入失败」/「密码错误或文件已损坏，没有建立档案。」+「重试」 | 失败（原因类别：密码错误或文件损坏 / 版本不兼容 / 文件无效 / 导入中断，文案见 §5） | M2-FR-028；AC-007 |
| M2-09 | 导入被阻止（Coach 模式下从系统打开档案文件，D-010） | `DS-PAGE-HEADER`（「无法导入档案」）→ `DS-STATUS` 自由文本警示（「!」+「这台设备上已有 Coach 数据」）→ `body` 说明「为避免和 Coach 数据混在一起，档案只能导入到没有 Coach 数据的精练教练。」→ `DS-SECTION`「可以这样做」→ 编号步骤 3 行 `DS-LIST-ROW`（不可点）：「先完整备份 Coach 数据（设置 → 备份与恢复）」「删除并重新安装精练教练，再导入档案」「或者在没有 Coach 数据的设备上导入」→ 主按钮「知道了」 | 默认；页面不提供任何清除 Coach 数据的入口 | M2-FR-026、027；AC-006 |
| M2-10 | 导入成功摘要 | `DS-PAGE-HEADER`（「档案已导入」）→ `DS-LABEL-VALUE-ROW` ×3：来源「来源 · 4821」、快照时间「2026年9月25日 18:30」、包含内容「训练记录、身体数据、趋势与个人最佳」→ `DS-STATUS` 自由文本「i」+「这是只读档案：不能编辑、添加训练或分享」→ 主按钮「开始查看」 | 默认 | M2-FR-029；D-007 |

### 3.3 查看模式（spec §12 输入 4–5）

| 画板 | 页面 | 组件顺序 | 代表状态 | 关键 FR |
|---|---|---|---|---|
| M2-11 | 档案首页 | `DS-PAGE-PRIMARY` 查看模式变体：标题行 `display` 大标题（导出了显示名称时为名称，否则「我的训练档案」）+ `DS-TITLE-ACTION` 设置齿轮 → `DS-STATUS` 自由文本「i」+「只读档案 · 来源 4821 · 9月25日」→ 分割线 → `DS-HUB-ROW` ×5：训练记录（尾部说明「24 次」）、身体数据（「3 项指标」）、趋势与个人最佳、动作资料（不可用态「档案未包含」）、关于本档案 | 未导出显示名称（通用标题）；动作资料未包含 | M2-FR-030、034；H1；spec §5 通用标题 |
| M2-12 | 训练记录列表 · 已筛选 | `DS-PAGE-HEADER`（「训练记录」）→（档案含动作资料时，此处多一个 `DS-TEXT-FIELD` 搜索框「搜索动作名称」，位置同 M2-16；本画板与 M2-11 一致，按未含动作资料绘制，所以没有搜索框）→ `DS-CHIP` 筛选胶囊「日期范围」「训练重点」→ `caption`「已筛选：…」→ `DS-SECTION`「N 次训练」→ `DS-LIST-ROW`（标题 `headline` 日期，副文字「部位 · N 组 · N 分钟」，`›`）+ 分割线 | 已筛选；空结果时为一行 `caption`「没有符合条件的训练记录」 | M2-FR-031、035 |
| M2-13 | 训练记录详情 · 动作占位 | 复用 35 的分区（导航栏 inline「训练记录」、日期 `caption`、训练标题、三项统计、动作块；学员名省略）；动作块名称为「动作 1」等占位、无器材图标；**去掉** 35 的「编辑训练重点」「另存为模板」和「生成训练报告」→ 末尾 `DS-STATUS` 自由文本「i」+「只读记录」。**未含动作资料时不显示「训练部位」示意图**：`DS-BODY-DIAGRAM` 的着色来自动作的主 / 次肌群，属于「动作资料」内容（M2-FR-045、M2-FR-009 的同理推论，产品负责人 2026-10-09 同意） | 未含动作资料（占位编号、无示意图）；含动作资料时同 35 显示名称、器材图标与训练部位示意图 | M2-FR-033、045；D-001 |
| M2-14 | 身体数据 | 复用 06 的结构（`DS-PAGE-HEADER` + `DS-SECTION` + 指标行：标签 `callout`、数值 `numeralLarge`、单位 `caption`）；**去掉**学员名和「＋ 自定义指标」；底部「单位 · kg / cm（可在设置中切换）」。单个指标的全部测量沿用 M1 身体数据历史列表的只读形态，不另画 | 只含已选指标（与 M2-02b 一致：体重、体脂率） | M2-FR-030、032 |
| M2-15 | 趋势与个人最佳 | `DS-PAGE-HEADER`（「趋势与个人最佳」）→ `DS-LABEL-VALUE-ROW`「动作 / 动作 1 ›」→ `DS-SEGMENTED`「重量 / 次数 / 容量」→ 折线图（沿用 M1 `TrendsView` 现有 Swift Charts 实现；M1 没有该图的高保真画稿，画板中的折线只示意位置，图层标为 `M2-TREND-CHART`，不构成新的视觉规格）→ `DS-SECTION`「个人最佳」→ 32 的个人最佳行 | 未含动作资料（占位编号） | M2-FR-030、009 |
| M2-16 | 动作资料 | `DS-PAGE-HEADER`（「动作资料」，副标题「本档案出现的 16 个动作」）→ `DS-TEXT-FIELD` 搜索框 → `DS-LIST-ROW`（leading `DS-EQUIPMENT-ICON`；标题 `headline` 动作名；副文字「主：胸 · 次：肩、臂 · 杠铃」；不可点）+ 分割线 | 内置动作与自定义动作混排；自定义动作没有器材图标时 leading 留空位 | M2-FR-045；AC-011 |
| M2-17 | 关于本档案 | `DS-PAGE-HEADER`（「关于本档案」）→ `DS-LABEL-VALUE-ROW` ×3（来源、快照时间、包含内容）→ `DS-SECTION`「动作资料来源」→ `caption` 汇总署名段（来源 wger.de + 本档案涉及的许可证名称与链接，例如「部分动作资料来自 wger.de，按 CC-BY-SA 3.0 / CC-BY-SA 4.0 许可使用」；不逐动作列出，spec Revision 1.1.3；许可证名称与链接各占整行、不跨行拆开；Penpot 已回填，快照「M2-17 attribution line breaks fix 2026-10-10」；`screens/` 中 M2-17 已于 2026-10-10 按 2 倍重导出替换） | 含动作资料与内置动作；未含动作资料时没有「动作资料来源」区段 | M2-FR-046；D-007、D-008 |
| M2-18 | 查看模式设置 | `DS-PAGE-HEADER`（「设置」）→ `DS-SECTION`「显示」→ `DS-LABEL-VALUE-ROW` ×3，值 slot 为 `DS-SEGMENTED`（C11）：重量「kg / lb」、围度与身高「cm / in」、列表密度「标准 / 紧凑」→ `caption`「只改变这台设备上的显示，不改变档案内容」→ `DS-SECTION`「档案」→ `DS-ACTION-ROW`「导入较新档案 ›」→ `DS-ACTION-ROW` destructive「删除本机档案」，**带 leading 垃圾桶图标**（`DS-ACTION-ROW` 扩展，NFR-005 要求危险删除同时用文字和图标） | 默认 | M2-FR-032、041；D-010 |
| M2-19a | 导入较新档案 · 确认替换 | `DS-PAGE-HEADER`（「导入较新档案」，副标题「新档案会整体替换当前档案，不会逐条合并」）→ `DS-SECTION`「当前档案」+ `DS-LABEL-VALUE-ROW` ×3 → `DS-SECTION`「新档案」+ `DS-LABEL-VALUE-ROW` ×3 → 主按钮「替换为新档案」 | 同来源同学员、较新（选择文件与输入密码复用 M2-08 的组件，不另画） | M2-FR-036～038 |
| M2-19b | 导入较新档案 · 被拒绝 | 同 19a 的页头 → 可点的文件行、密码框、「导入」（同 M2-08）→ `DS-INLINE-RESULT` 失败「无法替换」/「这份档案不比当前档案新。当前档案没有改变。」+「重试」 | 较旧 / 同时间；其他原因类别见 §5 | M2-FR-039 |
| M2-20 | 删除本机档案 · 确认 | M2-18 之上 `DS-CONFIRM-DIALOG`：标题「删除本机档案？」/ 说明「删除后这台设备上无法再查看档案，显示设置一并清除。不影响 Coach 的原始数据和档案文件本身。」/ 左「取消」右「删除」 | 默认 | M2-FR-041～044 |

后台遮蔽（NFR-003）沿用 M1 隐私遮罩（README §8.1「隐私遮罩」），不另画画板。

## 4. Feature 专有组件

### 4.1 `M2-EXCLUSION-NOTE` 永久排除说明

- **部件**：锁图标（SF Symbol `lock.fill`，`text.secondary`，与 28 隐私说明的锁同款，装饰性）→ `caption` `text.secondary` 文字：「伤病、联系方式、教练备注、课包等永远不会导出」（390 宽屏折成两行，产品负责人 2026-10-10 保留「教练备注」；Penpot M2-02a/02b 已同步，快照「M2-02 exclusion copy with 教练备注 (owner 2026-10-10)」，screens/ 导出图已随 Penpot revn 266 的 2 倍重导出更新）→ 可选尾部链接「查看全部」（`caption` 600 `action.primary`，展开完整清单：伤病与注意事项、教练备注、动作私有备注、课包、课程安排、课时调整、电话和微信、动作图片、训练模板）。换行不截断。
- **不变量**：只显示文字，**没有**开关、勾选圈或任何可点击部件（M2-FR-010「不提供临时解锁」，可自动：源码中不含 `Button` / `Toggle`）；文字使用 glossary 中文词，不直出英文领域词（M2-FR-035，人工）。
- **复用边界**：只用于 M2-02。28 分享报告的隐私说明另有吉祥物头像，不合并。

### 4.2 模块分组行（`DS-LIST-ROW` 分组变体的 M2 用法）

不另建组件，记录 M2 对扩展后 `DS-LIST-ROW` 的用法（规格见 `components.md` §4.7）：

- 分组行：标题 `headline`（基本资料 / 训练内容 / 身体数据）→ 尾部说明 `caption` `text.secondary`（组内概况，部分选中时写「2 / 3 项指标」）→ 展开符号 `▾`（README §7.2；展开时朝上）→ 三态勾选圈（全选 ✓、部分选中 −、全不选空圈）。点勾选圈切换整组；点行的其他部分展开或折叠。两个点击区各 ≥ 44。默认全部折叠、全部选中（M2-FR-007）。
- 子行：缩进 `space.4`（文字从 x=32 开始），标题 `body`，尾部说明 + 勾选圈；自定义指标显示名称原文。
- 不可用子行：标题 `text.disabled`，尾部说明写原因（「无数据」「需同时选择训练记录」），不画勾选圈（D-005、D-009、D-015；「趋势与个人最佳」与「动作资料」都只依赖训练记录，spec Revision 1.1.1）。整组都不可用时，分组行同样不可用。
- 至少保留一项才能「预览」（M2-FR-007）；全部取消时主按钮禁用。

### 4.3 `M2-FACT-ROW` 交付前事实行

- **部件**：22×22 `FCStatusBadge`（警示「!」`status.warning`，或信息「i」`action.primary`，装饰性）→ `body` `text.primary` 事实文字（x=46，换行不截断，多行时徽标与首行对齐）。上下内边距 `space.3`；行间由调用方放 `FCListRowDivider`。
- **为什么不直接用 `DS-STATUS`**：`FCStatusLabel` 的文字是 `caption` `text.secondary`，适合附在内容旁的状态说明；这 6 条是交付前必须读懂的主体内容，需要正文字号与主文字色。徽标外观与 `DS-STATUS` 完全相同。
- **不变量**：恰好 6 行、顺序与 M2-FR-013 一致（可自动：本地化键列表测试）；每行同时有字形与文字（可自动）；整行合并为一个无障碍元素，读出文字（可自动）。
- **复用边界**：只用于 M2-04。第二个 feature 需要「徽标 + 正文」时，提升为 `DS-STATUS` 的变体。

## 5. 文案与原因类别（本表只汇总界面文字，行为以 spec 为准）

| 场景 | 标题 | 说明 |
|---|---|---|
| 导入：密码错误或文件损坏 | 导入失败 | 密码错误或文件已损坏，没有建立档案。 |
| 导入：版本不兼容 | 导入失败 | 这份档案来自不兼容的精练教练版本，没有建立档案。 |
| 导入：文件无效 | 导入失败 | 这不是有效的个人训练档案，没有建立档案。 |
| 导入：中断 | （重启后回到首次启动或导入页，不显示半个档案） | — |
| 替换：较旧 / 同时间 | 无法替换 | 这份档案不比当前档案新。当前档案没有改变。 |
| 替换：其他来源 | 无法替换 | 这份档案来自另一个来源。当前档案没有改变。 |
| 替换：学员不匹配 | 无法替换 | 这份档案属于另一名学员。当前档案没有改变。 |
| 替换：密码 / 损坏 / 不兼容 | 无法替换 | 同导入对应原因，结尾为「当前档案没有改变。」 |

交付前确认的 6 条（M2-FR-013 顺序）：
1. 「!」档案不是完整备份，不能用来恢复你的数据。
2. 「!」档案会包含刚才预览中的全部资料。
3. 「!」文件交出并被接收后，你和精练教练都无法撤回。
4. 「i」学员只能删除自己设备上的副本。
5. 「i」学员删除不会影响你的原始数据、已保存的文件或其他副本。
6. 「i」请通过其他方式把密码单独告诉学员，不要和档案一起发送。

## 6. 核心页面（L3 触发条件 2，产品负责人 2026-10-09 确定）

| 页面 | 理由 |
|---|---|
| M2-02 选择导出内容（02a、02b） | 唯一的数据外流决策点；分组、三态勾选、子项不可用态与排除说明集中在这里，出错即隐私事故 |
| M2-11 档案首页 | 查看模式的入口与只读语义的第一印象；含查看模式首页变体与入口行不可用态 |

首次实现完成时各对照画稿看一次；之后只在发生 B 类修订时复看。M2-07 未入选，按普通页面走 L2 组合检查。

## 7. 执行记录（`components.md` §1.5）

```text
分类与依据：M2 无 A 类。B 类：DS-LIST-ROW 扩展、DS-HUB-ROW 尾部说明 / 不可用态、DS-INLINE-RESULT 信息变体、DS-ACTION-ROW destructive 图标、DS-PAGE-PRIMARY 查看模式变体、M2-01（26 加一行）、模块选择子行交互、M2-FACT-ROW；其余 C 类复用。批准来源：README v1.0、components.md v1.0、M1-B 画稿 01–43（Penpot「M1-B G5 Design」Foundations 页）。
影响范围：新增共享 DS-PAGE-HEADER；DS-HUB-ROW、DS-INLINE-RESULT 由组合模式提升为共享组件；扩展 DS-LIST-ROW；DS-CONFIRM-DIALOG 补内容变长规则。M1 消费者在 Phase 0 迁移时外观不变：ResourceHub、Settings、BackupRestoreFlow、StudentDetailView。需同步：components.md §4.7、本文、Penpot「M2 G7 Design」、screens/。
设计决定：沿用 H1–H3（产品负责人 2026-10-08）；新的视觉 / 交互决定（§2 的 B 类各项、§4.2 子行规则）待 G7 设计载体 review。
实施与验证：设计阶段，无代码。Phase 0 的组件不变量与测试见 components.md §4.7；入口与布局清单在实现检查点提交。绘制期间按画板导出图做过排版自查（文字重叠、换行溢出、间距），属于绘制过程中的检查，不是视觉验收；修正了 M2-03 长文本压日期、M2-09 编号换行、M2-10 多行值溢出、M2-06d 说明贴近按钮、M2-13 示意图越权、M2-18 危险删除缺图标。
结果：PASS。2026-10-09 产品负责人 review 通过 26 块画板与本文，G7 整体通过（spec `1.1-approved`）。review 中的行为调整已回修 PRD 1.2 / spec 1.1。导出图已于 2026-10-09 换成 2 倍图。剩余项：§4.7 组件代码在 M2 tasks Phase 0 实现。没有任何代码改动；没有人工视觉验收。
```

### 7.1 Phase 1（tasks T001–T013，设计系统组件，2026-10-10）

```text
分类与依据：D 类（规格已在 components.md §4.7 定稿，本阶段无新视觉决定）；目标设计不变。批准来源：components.md §4.7（2026-10-09 随 G7 审定）、M1-B 画稿 19/26/38/39/42/43。
影响范围：新增 FCPageHeader（DS-PAGE-HEADER）、FCHubRow（DS-HUB-ROW）、FCInlineResult（DS-INLINE-RESULT）；扩展 FCListRow 并新增分组变体 FCListGroupRow（DS-LIST-ROW）、FCActionRow showsTrashIcon（DS-ACTION-ROW）、FCConfirmationDialog 内容变长规则（DS-CONFIRM-DIALOG）、FCSaveStatusView 显式字体与本地化键（CG-3；Status 不再以 String 为 rawValue）。迁移消费者：ResourceHubView（私有 hubRow / hubSymbol 删除）、SettingsView（私有 row 删除）、BackupRestoreFlow（成功 / 失败结果，重试并入失败结果）、StudentDetailView 页头。components.md §3/§4.6/§4.7/CG-3 已同步；Swift 名称与 §4.7 拟定名一致，参数形态见 §4.7 各条「状态」行。
设计决定：沿用已审定规格，无新决定。FCStatusTests 的登记位置断言放宽为同时接受 `FCStatusLabel(.permissionDenied)` 与 FCHubRow 的 `.status(.permissionDenied)`，并新增断言 FCHubRow 的 `.status` 副标题经 FCStatusLabel 渲染——证明强度不变。
实施与验证：L1 不变量测试 M2ComponentContractTests（10 项）+ TouchTargetComponentTests 扩展；ComponentCatalogTests、DesignValueScanTests、FCStatusTests、PrivacyCoverTests 通过。入口与布局清单见下。L3：未触发（D 类、非核心页面）；§4.7 标「人工」的不变量（页头长标题换行、确认弹窗堆叠观感）在组件首次被人查看时看一次，列入 T069 集中走查。
结果：PASS（自动门）。xcodebuild build 成功；FineCoachTests 281 项，0 失败，1 项跳过（ContrastHarnessTests.testTextDisabledOnSurfacePageIsWCAGExempt，既有 WCAG 豁免）；FineCoachIntegrationTests 96 项，0 失败。模拟器 iPhone 17 Pro Max（iOS 26.5，按设备 id 指定；quickstart §2 的 name= 写法在本机匹配失败）。已知缺口：迁移页面（19/26/38/39/42/43）外观是否不变**未经人工视觉检查**；确认弹窗在大字号下的堆叠 / 80% 高度上限、分组行「部分选中」字形在 22pt 圆内的观感未经人工检查（列入 T069 L3 疑点）。
```

入口与布局清单（`components.md` §1.4）：

```text
资料库 19 → 「动作库」入口行（器材图标、计数副标题、›）→ FCAccessibilityID.exerciseLibraryEntry → 否（导航）→ FCHubRow .frame(maxWidth: .infinity, minHeight: 64)（ResourceHubView.swift:23）
资料库 19 → 「训练模板」入口行 → FCAccessibilityID.templatesEntry → 否（导航）→ FCHubRow（ResourceHubView.swift:31）
设置 42/43 → 「通知」入口行（被拒时 FCStatusLabel 副标题 +「前往设置」）→ FCAccessibilityID.settingsNotifications → 否（打开系统设置）→ FCHubRow（SettingsView.swift:63，用于 :22）
设置 42 → 「备份与恢复」入口行 → FCAccessibilityID.settingsBackup → 否（导航）→ FCHubRow（SettingsView.swift:24）
设置 42 → 「关于」行（版本号，无 ›，不可点）→ FCAccessibilityID.settingsAbout → 否 → FCHubRow（SettingsView.swift:31）
备份与恢复 39 → 「恢复完成」就地结果 → FCAccessibilityID.restoreSucceeded → 否 → FCInlineResult .frame(maxWidth: .infinity)（BackupRestoreFlow.swift:164）
备份与恢复 38 → 「恢复失败」就地结果 → FCAccessibilityID.restoreFailed → 否 → FCInlineResult（BackupRestoreFlow.swift:176）
备份与恢复 38 → 「重试」可见链接按钮（恢复中禁用）→ FCAccessibilityID.restoreRetry → 是（重新执行恢复；可见按钮，非手势）→ FCInlineResult 内 FCLinkButton .frame(maxWidth: .infinity)（BackupRestoreFlow.swift:186）
学员详情 26 → 页头标题（header 属性）→ 无（与迁移前相同）→ 否 → FCPageHeader .frame(maxWidth: .infinity)（StudentDetailView.swift:169）
学员详情 26 → 「编辑资料」尾部操作 → studentDetail.edit → 否（进入编辑页）→ FCPageHeader 标题行（StudentDetailView.swift:173）
```

### 7.2 Phase 2（tasks T014–T026，档案基础设施，2026-10-10）

```text
分类与依据：无视觉工作（档案容器、快照存储、身份 setting、恢复兼容、安装状态、启动分流）。批准来源：plan §4 D-M2-001/002/003/005/007、data-model §1–§6、contracts/archive-file-v1.md。
影响范围：无新组件、无新 Feature 页面。新增 AppRoot 作为场景根（根部 PrivacyCover 自 RootNavigation 移入）；ArchiveViewerRoot 仅为占位（两段静态文字，不接收 Coach 环境），由 US-2 T046 替换。
设计决定：无。产品负责人 2026-10-10 确认档案文件上限 = 明文 64 MiB + 容器开销（plan §7.3 已改）。
实施与验证：ArchiveFoundationTests、ArchiveFileCodecTests、PrivacyCoverTests、ArchiveFoundationIntegrationTests。入口与布局清单：ArchiveViewerRoot → 占位标题与说明（无控件）→ archive.viewer.root → 否 → 根 VStack .frame(maxWidth: .infinity, maxHeight: .infinity)（ArchiveViewerRoot.swift）。L3 未触发。
结果：PASS（自动门）。xcodebuild build 成功；FineCoachTests 351 项 0 失败、1 项跳过（既有 WCAG 豁免）；FineCoachIntegrationTests 106 项 0 失败。占位页未经人工查看；.fcarchive 的系统打开路由未在设备上验证（处理逻辑在 T044）。
```

### 7.3 US-1 导出（tasks T027–T037、T034a，2026-10-10）

```text
分类与依据：B 类按 §2 已审定（M2-01 加一行、模块选择子行交互、M2-FACT-ROW）；其余 C 类复用 Phase 1 组件。批准来源：本文 §3–§5、screens/M2-01～06d、spec 1.1.3（D-005「不透露」视为无数据、D-008 汇总署名）。
影响范围：新增 Features/ArchiveExport/（M2-02～06 单一 push 页面，页面由 ArchiveExportFlow.state 决定）、feature 专有 ArchiveFactRow（M2-FACT-ROW）、ArchiveExclusionNote（M2-EXCLUSION-NOTE）、ArchivePasswordField（唯一密码输入配置）；StudentDetailView 加 M2-01 行；RootDestination.archiveExport；DEBUG 种子 ArchiveExportDebugSeed。无新设计系统组件。
设计决定：文案在 PNG 与本文不一致处以已审定 PNG 为准（M2-05 规则与占位、M2-06b 说明）；交付失败 / 取消只保留单一「交给系统…」按钮作为重试入口（M2-06c/06d 画稿），不另加重试链接；M2-EXCLUSION-NOTE 的「查看全部」实现为只展开 / 收起文字清单的 Button（不改数据）。自拟文案待 T038 确认：密码过短「密码至少需要 8 个字符」、意外错误「操作没有完成」、清单前缀「永远不会导出：…」、展开后「收起」、「N / M 项指标」「X（自定义）」。
实施与验证：ArchiveExportPolicyTests、ArchiveExportScreenTests（12 项：密码配置唯一、排除说明无开关、离开流程调用 leave()、入口为 FCActionRow 无 contextMenu、本地化键齐全、事实行顺序、预览原文与排除值）、ArchiveExportIntegrationTests；PrivacyCoverTests、DesignValueScanTests、LogSurfaceTests 通过。L3：核心页面 M2-02 首次实现，T038 请产品负责人对照 M2-02a/02b 看一次。
结果：PASS（自动门）。xcodebuild build 成功；FineCoachTests 396 项 0 失败、1 项跳过（既有 WCAG 豁免）；FineCoachIntegrationTests 112 项 0 失败。
T038 L3 走查（产品负责人 2026-10-10，模拟器 iPhone 17 Pro Max，虚构数据）：M2-02、M2-03、M2-06 功能通过（含密码不一致、密码过短）；生成阶段出错经 DEBUG 参数 -FineCoachSimulateArchiveGenerationFailure 模拟，通过（首次失败进入 M2-06d，「交给系统…」重试成功）。UX/UI 不通过，三项缺陷：①二级页返回键为系统导航栏按钮、标题另起一行，与画稿「‹ 与标题同一行、紧凑」不符（M1 二级页同样，DS-PAGE-SECONDARY 规格须改）；②勾选圈 ✓ 为 SF Symbol，与画稿 Noto Sans SC 字形不符（README §7.2 须改）；③分组行 / 子行左侧多缩进 16、行高 44 小于画稿约 53，观感「压扁」（字体本身已确认为 Noto Sans SC）。产品负责人拍板：「查看全部」保留现做法；重试只保留「交给系统…」；自拟文案通过；生成失败沿用 M2-06d 文案。缺陷修复后 M2-02 需再看一次。
缺陷修复（合并 0004aea + 本提交）：二级页统一内联 `‹`（含训练中页，产品负责人：返回方式全 App 一致）、页头上边距 space.2（不伸进状态栏，实施方定，理由见 components.md DS-PAGE-HEADER）、‹ › ✓ 改 Noto 字形（产品负责人确认观感无问题）、FCListRow 行高 52 / 缩进 16、「、」间距（LocalizedStringKey 渲染所致，改 String(localized:)）。
T038 复查（产品负责人 2026-10-10，模拟器 iPhone 17 Pro Max，7 名虚构学员）：M2-02 通过；M1 回归走查通过。T038 结论：PASS。M2-02～06 **未经人工视觉检查**；密码框不出现钥匙串保存 / 强密码建议、真实分享面板取消后临时文件清理均为设备检查项，未验证。
```

入口与布局清单（`components.md` §1.4）：

```text
学员详情 M2-01 → 「导出个人训练档案 ›」→ studentDetail.exportArchive → 否（push 流程；已归档学员同样显示）→ FCActionRow（StudentDetailView.swift:333）
M2-02 → 系统返回 / 侧滑 → 无 → 离开流程（leave() 删除临时文件）→ 系统导航栏（ArchiveExportFlowView.swift）
M2-02 → 页头 → 无 → 否 → FCPageHeader（ArchiveSelectionView.swift:12）
M2-02 → 分组行 基本资料 / 训练内容 / 身体数据 → archiveExport.group.<key> → 圆圈：是（整组选择）；其余：否（展开 / 折叠）→ FCListGroupRow（ArchiveSelectionView.swift:54），不可用组 FCListRow.unavailable（:45）
M2-02 → 子行（姓名、性别、训练记录、趋势与个人最佳、学员课后总结、动作资料、各身体指标）→ archiveExport.item.<key> → 是（切换选择；不可用行无控件，显示「无数据」/「需同时选择训练记录」）→ FCListRow 可选（:87）/ 不可用（:80）
M2-02 → 排除说明「查看全部」/「收起」→ archiveExport.exclusion.viewAll → 否（只显示 / 隐藏文字清单）→ ArchiveExclusionNote VStack maxWidth .infinity（ArchiveExclusionNote.swift:21）
M2-02 → 「预览」→ archiveExport.preview → 是（流程状态 selecting → previewing；无有效选择时禁用）→ FCButton 经 archiveBottomButton（ArchiveSelectionView.swift:30）
M2-03 → 自定义返回 → archiveExport.back → 是（flow.back() 回 selecting）→ 工具栏前导项 44×44（ArchiveExportFlowView.swift:50）
M2-03 → 各区段行 → 无 → 否 → FCLabelValueRow（ArchivePreviewView.swift）
M2-03 → 自由文本条目（自定义 / 仅本次动作名、学员总结、自定义指标名）→ 无 → 否（不可点）→ FCListRow showsDisclosure: false（ArchivePreviewView.swift:122、:137）
M2-03 → 自由文本提示 → archiveExport.preview.freeTextNotice → 否 → FCStatusLabel maxWidth .infinity（ArchivePreviewView.swift:25）
M2-03 → 占位说明 → archiveExport.preview.placeholderNote → 否 → Text maxWidth .infinity（ArchivePreviewView.swift:71）
M2-03 → 「继续」→ archiveExport.continue → 是（previewing → confirmingFacts）→ FCButton 经 archiveBottomButton（ArchivePreviewView.swift:28）
M2-04 → 自定义返回 → archiveExport.back → 是（回 previewing）→ 工具栏前导项
M2-04 → 6 条事实行 → 无 → 否 → ArchiveFactRow maxWidth .infinity（ArchiveDeliveryWarningView.swift:18）
M2-04 → 「我已了解，设置密码」→ archiveExport.confirmFacts → 是（confirmingFacts → settingPassword）→ FCButton 经 archiveBottomButton（ArchiveDeliveryWarningView.swift:24）
M2-05 → 自定义返回 → archiveExport.back → 是（回 confirmingFacts，丢弃密码）→ 工具栏前导项
M2-05 → 设置密码 / 再次输入 → archiveExport.password / archiveExport.passwordConfirm → 否（仅内存）→ ArchivePasswordField 包 FCTextField（ArchivePasswordView.swift:17、:19）
M2-05 → 密码不符结果 → archiveExport.passwordError → 否 → FCInlineResult（ArchivePasswordView.swift:28）
M2-05 → 「生成档案」→ archiveExport.generate → 是（settingPassword → generating → generated / failed；写临时文件，首次写身份 setting）→ FCButton 经 archiveBottomButton（ArchivePasswordView.swift:39）
M2-06a～d → 系统返回 → 无 → 离开流程（leave() 删除临时文件）→ 系统导航栏
M2-06a～d → 结果 → archiveExport.deliveryResult → 否 → FCInlineResult（ArchiveDeliveryView.swift:48、:55、:62、:69）
M2-06a/c/d → 「交给系统…」→ archiveExport.deliver → 是（deliver()；取消 / 失败后先 retry() 再 deliver()）→ FCButton（ArchiveDeliveryView.swift:22）
M2-06b → 「完成」→ archiveExport.done → 是（leave() 并返回学员详情）→ FCButton safeAreaInset 底部（ArchiveDeliveryView.swift:35）
加载错误 / 意外错误 → archiveExport.loadError / archiveExport.actionError → 否 → FCInlineResult（ArchiveExportFlowView.swift:79、:32）
```

### 7.4 US-2 首次启动、导入与查看（tasks T039–T052，2026-10-11）

自动门：`xcodebuild build`、`FineCoachTests`、`FineCoachIntegrationTests` 全绿（数字见提交说明）。界面测试只改了首次启动步骤（先点「Coach 使用」），编译通过，未运行。**未经人工目视**；M2-11 的 L3 走查（T053）待产品负责人进行。

**入口与布局清单**（页面 → 控件 → 标识 → 是否写数据 → 撑满宽度的组件）：

| 页面 | 控件 | 标识 | 写数据 | 宽度 |
|---|---|---|---|---|
| M2-07 | 「Coach 使用」行 | `firstLaunch.coach` | 否（只切换分支） | `FCHubRow`（`FirstLaunchChoiceView.swift:38`） |
| M2-07 | 「导入个人训练档案」行 | `firstLaunch.import` | 否（push 导入页） | `FCHubRow`（`:46`） |
| Onboarding | 页头 `‹`（仅未选择时） | `onboarding.back` | 否（回 M2-07） | `FCPageHeader`（`OnboardingView.swift:38`） |
| M2-08 | 页头 `‹` | `archiveImport.back` | 否（删 Inbox 副本） | `FCPageHeader`（`ArchiveImportView.swift:19`） |
| M2-08 | 档案文件行 | `archiveImport.file` | 否（系统文件选择器） | `FCLabelValueRow`（`:29`） |
| M2-08 | 密码框 | `archiveImport.password` | 否（仅内存） | `FCTextField`（`:33`） |
| M2-08 | 「导入」 | `archiveImport.submit` | **是**（安装档案；失败不写） | `FCButton`（`:37`） |
| M2-08b | 失败结果 / 「重试」 | `archiveImport.failure` / `.retry` | 重试 = 再次导入 | `FCInlineResult`（`:90`） |
| M2-09 | `‹` / 「知道了」 | `archiveBlocked.back` / `.acknowledge` | 否（删 Inbox 副本） | `FCPageHeader` / `FCButton`（`ArchiveImportBlockedView.swift:19,44`） |
| M2-10 | `‹` / 「开始查看」 | `archiveSummary.back` / `.start` | 否（只重新解析安装状态） | `FCPageHeader` / `FCButton`（`ArchiveImportSummaryView.swift:15,48`） |
| 替换占位 | `‹` | `archiveImport.back` | 否 | `FCPageHeader`（`ArchiveImportView.swift:110`），T055 接入 |
| M2-11 | 设置齿轮 | `archiveHome.settings` | 否 | `FCTitleIconButton`（`ArchiveHomeView.swift:28`） |
| M2-11 | 训练记录 / 身体数据 / 趋势与个人最佳 | `archiveHome.records` / `.body` / `.trends` | 否 | `FCHubRow`（`:70,80,89`） |
| M2-11 | 动作资料 / 关于本档案 | `archiveHome.exercises` / `.about` | 否（暂不可点，T062 接入） | `FCHubRow`（`:98,107`） |
| M2-12 | `‹`、搜索、日期范围 / 训练重点胶囊、清除筛选、记录行 | `archiveRecords.back` / `.search` / `.filter.date` / `.filter.focus` / `.filter.clear` / `.row.N` | 否（内存筛选；行 push 详情） | `FCPageHeader` / `FCSearchField` / `FCFilterChip` / `FCListRow`（`ArchiveRecordsView.swift:41–109`） |
| M2-13 | 系统返回（M1 35 口径） | — | 否 | `ShareReportCardView(.page)` |
| M2-14 | `‹`、指标行、历史页 `‹` | `archiveBody.back` / `.metric.<key>` / `archiveMetric.back` | 否 | `FCPageHeader` / `BodyMetricValueRow`（`ArchiveBodyDataView.swift:25,64,85`） |
| M2-15 | `‹`、动作行、重量/次数/容量 | `archiveTrends.back` / `.exercise` / `.metric` | 否 | `FCPageHeader` / `FCLabelValueRow` / `FCSegmentedSwitch`（`ArchiveTrendsView.swift:49,58,116`） |
| M2-18 | `‹`、重量 / 围度与身高 / 列表密度 | `archiveSettings.back` / `.weight` / `.length` / `.density` | **是**（只写本机显示设置，不写档案） | `FCLabelValueRow` + `FCSegmentedSwitch`（`ArchiveSettingsView.swift:25,34,46`） |
| M2-18 | 导入较新档案 / 删除本机档案 | `archiveSettings.importNewer` / `.delete` | 否（禁用占位，T055 / T058 接入） | `FCActionRow`（`:68,74`） |

**无写入口清单（SC-005）**：查看模式各页可点控件只有上表所列的返回、push、内存筛选与本机显示设置；没有编辑、添加训练、分享报告、导出、备份、预约、课包入口。`ArchiveViewerScreenTests` 在 `Features/ArchiveViewer` 中禁止 `contextMenu`、`.sheet(`、`.fullScreenCover(`、`swipeActions` 及 Coach / 分享 / 备份 / 导出类型。

**待产品负责人确认（实现时的自定文案与判断）**：「正在导入…」；替换占位「导入较新档案的功能尚未提供。」；「无法读取档案」/「档案文件无法读取，没有任何内容被改动。」；「设置没有保存」/「请稍后再试。」；「近 N 天」以档案快照日为基准而非今天；无训练重点的记录标题沿用 M1 的「训练报告」；列表密度「紧凑」新增 `FCListRow` 的 `fcCompactRows` 环境值（最小高度 44，默认不变，尚未写入 `components.md`）；M2-09 步骤行没有悬挂缩进、序号不是灰色，与 PNG 有出入。

**T053 L3 走查（产品负责人 2026-10-11，iPhone 17 Pro Max 模拟器，虚构档案）**：M2-11 及其下各页逐项点过，无大问题。上面「待确认」中的自定文案全部同意；「近 N 天」以档案快照日为基准，同意。无训练重点的记录标题「训练报告」暂沿用 M1 35 口径（只出现在 M2-13 详情页标题，本次档案中的记录都有训练重点，因此走查时看不到）。**T053 结论：PASS。**

## 8. 待产品负责人确认的问题

1. ~~M2-09 的进入路径~~：**已定（R4）**，支持系统打开档案文件，spec D-010 已修订。
2. ~~「动作资料」是否依赖训练记录或趋势~~：**已定（R2）**，并入「训练内容」组；组内依赖写为 spec D-015。
3. ~~未含「动作资料」时隐藏训练部位示意图（M2-13）~~：**已定（2026-10-09 产品负责人同意）**。示意图着色来自动作的主 / 次肌群，属于「动作资料」内容；未含动作资料时不显示示意图，训练重点部位文字仍显示。

当前没有待确认的问题。
