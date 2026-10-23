# 阶段 D 收获感：设计改动与实施映射

> 状态：**Phase 1–6 自动门通过；实现完成，待审查与集中走查；D-BLOCK-01 已关闭。画稿已批准（2026-10-20）。**本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
> 行为权威：`specs/004-stage-d-progress-milestones/spec.md`（`1.3-approved` + Revision 1.4；2026-10-21 任务说明确认；**Revision 1.5（2026-10-23）重新定义新纪录与比上次进步，见 README §10 C16，代码尚未按 1.5 修改**）。视觉权威：`design/design-system/README.md`、`components.md`。
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
- **状态**：只在 `completed` 且持有本节该项纪录的组上出现（spec D-FR-013）。草稿组、待完成组都不出现。Revision 1.5（C16）：每个动作最多标一组，取主指标超过历史的组里最好的一组（重量模式最重，同重量次数最多）；同重量多做几次不算新纪录，但标记会移到那一组，不出现第二个标记。
- **触感**：确认时如果判为新纪录，`.impact(weight: .heavy)` 替代 `.success`，只响一次；重算（编辑、删除、撤销）不响（D-FR-010、D-FR-012）。Revision 1.5：只有确认的这一组主指标严格高于历史和本节此前所有组时才用新纪录触感；同重量多做几次接过标记时用普通 `.success`（D-FR-013）。
- **不变量**：
  - 整行仍然是一个无障碍元素，读作「标题，数值，新纪录，状态」（可自动）。
  - 标记不只靠颜色，必须有文字（可自动）。
  - 小屏和大字体下，标记不挤掉数值：先缩数值（现有最小缩放 0.8），仍放不下时标记换到标题下方另起一行（人工，画稿给出 375 宽和最大字体两种状态）。
- **受影响的现有使用方**：只有 ActiveSession。比较选择模式（32）只复用 `FCSetStateCircle`，不受影响。

### D-b 课程总结「本节收获」区块

- **位置**：总结页统计（时长、完成组数、训练重点）之后，「私人备注」之前。
- **结构**：`FCSectionLabel`「本节收获」→ 行，行间 `FCListRowDivider`：
  1. ~~**新纪录行**：复用 `PersonalBestRowView`（名称 / 纪录类型 / 数值 / 「重量 × 次数」），日期栏不显示。~~ Revision 1.5（C16）取消：新纪录不再单列一行。
  2. **动作行（比上次进步 / 新纪录）**：`FCListRow` 标题为动作名，副标题为「上次 80 kg × 5 → 本次 80 kg × 7」（`caption` `text.secondary`）。新纪录动作在标题「动作名」后加 D-a 的「新纪录」胶囊，同一行，即使与上次相比不算进步也列出（spec D-FR-021、D-FR-022；Penpot D-b）。右侧不再显示单独数值。
  3. **里程碑行**：`FCListRow` 标题「第 25 节课」，副标题「累计完成的课程」。
- **排序**：动作行（含新纪录动作）→ 里程碑；动作行按动作在本节出现的顺序。
- **空状态**：三类都没有时，整个区块（含标签）不出现（D-FR-020）。
- **不变量**：只读，没有可点控件；不改 `studentFacingSummary`（D-FR-024）；宽度由页面 `VStack` 的 `space4` 边距撑满（与其他区块一致）。

### D-c 分享设置与分享卡片（spec 1.2，PD-D5′）

- **命名**：开关、卡片区块与总结页区块统一叫「本节收获」（负责人 2026-10-20）。历史页「个人最佳」不改名。
- **设置页开关行**：复用现有 `toggleRow`，保持单行。标题「本节收获」；右侧提示按「N 项新纪录」→「第 M 节课」→「N 项进步」取前两个非空项，用「 · 」连接，强调色（`emphasizedNote`）。三类都空时整行不出现，不显示不可用的开关（spec 1.2；取消 D7a 原有的「本次无新纪录」灰色状态）。
- **卡片**：现有个人最佳区块改名「本节收获」，行与总结页 D-b 一致：Revision 1.5（C16）起为动作行（名称 + 新纪录胶囊（如有）/ 「上次 → 本次」，右侧不再单列数值）→ 里程碑（「第 M 节课」/「累计完成的课程」）。开关关闭时整个区块不出现。开关提示里的「N 项新纪录」「N 项进步」按动作计数，不重复（spec D-FR-031）。
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

Penpot 版本：`before-stage-D 2026-10-20` → `stage-D boards D-a D-a2 D-b D-b2 D-c D-c2 (pending approval) 2026-10-20` → `before-stage-D share 本节收获 2026-10-20` → `stage-D share 本节收获 D-c D-c2 (pending approval) 2026-10-20`（D-c、D-c2 按 spec 1.1 重画）→ `before-stage-D D-c2 compact states 2026-10-20` → `stage-D D-c2 note wording 2026-10-20`（D-c2 状态区收成两行加说明）→ `before-stage-D D-c2 hide empty row 2026-10-20` → `stage-D D-c2 hide empty row (pending approval) 2026-10-20`（去掉不可用状态）→ `before-stage-D card sticker 2026-10-20` → `stage-D card sticker placeholder + badge (pending approval) 2026-10-20` → `stage-D card padding 2026-10-20` → `before-stage-D sticker import 2026-10-20` → `stage-D card mascot sticker (pending approval) 2026-10-20`；`validate()` 0 错误。D-a、D-a2、D-b、D-b2、D-c、D-c2 均用 MCP `export_shape`（1×）导出看过渲染，未见文字变形。2× 定稿导出等批准后进行。Revision 1.5（2026-10-23，C16）：`before-gains-redefine 2026-10-23` → `gains-redefine D-a2 D-b D-c2 2026-10-23` → `gains-redefine D-a2 D-b D-c2 2026-10-23 (fix)`；D-b、D-c2 的深蹲行改为「上次 120 kg × 8 → 本次 125 kg × 5」+ 新纪录胶囊，D-a2 加「⑤ 判定口径」；三块均 1× 导出看过，无溢出、无重叠。D-a 不改（122.5 kg × 6 对上次最高 120 kg 按新口径仍是新纪录）。

## 4. 执行记录（五行，实施时填写）

```text
分类和依据：D-a/D-b/D-c 均为 B；目标设计有变化；依据 spec 004 与本文 §1。
范围：DS-SET-ROW 扩展；总结页、分享页组合；受影响使用方见 §2。
设计决定：D-a～D-c2 已于 2026-10-20 批准；Revision 1.4 与 plan §3.8 已于 2026-10-21 确认（任务说明）。本轮执行已批准的 B 类扩展，不改 Penpot。
实现和检查：Phase 1–6 自动门通过（下文），含 L0 token、L1 component contract、L2 DesignValueScanTests；页面组合为 ActiveSession → FCSetRow / FCNewRecordBadge，总结与详情 → SessionGainsSectionView / DS-SECTION / DS-LIST-ROW / PersonalBestRowView，分享 → toggleRow / FCNewRecordBadge / MascotHeartSticker；入口与宽度归属见 §5 共 5 行。旧期望契约调整累计 3 条（下文）。未经人工视觉检查。
结果：Phase 1–6 PASS（下文，保留 Phase 3 初次 BLOCKED 的原始证据与裁定）；T001–T029 已完成，待审查。L3 集中走查待负责人执行，不表示真机或视觉验收通过。
```

### Phase 1

- 初始审计：产品仓与 specs 仓均干净（tracked/staged/untracked 均无）；specs 在 main，仅按任务授权修改 tasks.md，不提交。
- 实现和检查：T001–T003 已实现；本阶段无新交互。新纪录文字键随组件加入，保证组件可独立使用。
- 结果：PASS。strict lint、iphoneos Debug App build、Simulator build-for-testing 通过；FineCoachTests 508 项 / 507 passed / 1 既有 WCAG exemption skipped / 0 failed；FineCoachIntegrationTests 188 / 188 passed / 0 failed。日志：`DerivedData/StageD/evidence/phase1/{lint,app-build,build-for-testing,unit,integration}.log`。未经人工视觉检查。

### Phase 2

- 范围：T005–T008，统一纯领域比较与 SessionGains，辅助动作查询工具；无新 UI。
- 实现和检查：现有 Comparison 的历史平手归最近课程规则保留；SessionGains 只在严格更好时更新各纪录项持有者。进行中课程使用进入训练页时读取的已完成历史；完成课程按 (completedAtUTC, id) 截断。
- 结果：PASS。strict lint、App build、build-for-testing PASS；FineCoachTests 515 项 / 514 passed / 1 既有 skip / 0 failed；FineCoachIntegrationTests 188 / 188 passed / 0 failed。日志：`DerivedData/StageD/evidence/phase2/{lint,app-build,build-for-testing,unit,integration}.log`。首次编译的辅助标记访问错误已按现有 preference.isAssisted 修正，未修改测试断言。

### Phase 3

- 范围：DS-SET-ROW 已批准 B 类扩展；ActiveSessionViewModel 使用单一 RecordState 同步发布 session 与持有者集合，每次 session 写入纯内存重算；load 的一次 listCompleted 同时用于上次、最近动作与新纪录。
- 实现和检查：新增标记与组行自动 contract 检查；新增 ActiveSessionNewRecordTests 的确认、转移、撤销与 reload 场景；入口见 §5。初次运行未改旧断言；续做按 D-BLOCK-01 裁定更新一处触感 contract。
- 结果：BLOCKED。strict lint、App build、build-for-testing PASS；FineCoachTests 516 项 / 514 passed / 1 既有 skip / 1 failed。失败为 SetEntryAssistTests.testMotionTableIsWiredAtTheApprovedMoments（单独复跑 1 项 / 0 passed / 1 failed）；FineCoachIntegrationTests 189 / 189 passed / 0 failed（含现有 PerformanceMeasurementTests.testRecoverySearchAndSetConfirmMeetP95Budgets 与新增 ActiveSessionNewRecordTests）。日志：`DerivedData/StageD/evidence/phase3/`。训练页标记、小屏 / 最大字体和触感未经人工视觉检查，并入集中走查。

### 待决项 D-BLOCK-01（Phase 3）

- 位置：`ios/FineCoachTests/ActiveSession/SetEntryAssistTests.swift:142`，`testMotionTableIsWiredAtTheApprovedMoments`。
- 当前：旧静态断言要求 `FCSetRow.swift` 源码含 `.sensoryFeedback(.success, trigger: state)`；全量与单独复跑均在此失败。
- 目标：plan §3.7 与 D-FR-010 / Q-D3 要求使用返回 `SensoryFeedback?` 的闭包，按同次发布的 `isNewRecord` 在 heavy / success 中选择一个；D-FR-012 禁止重算时触感。
- 冲突：任务说明只允许 T025 修改指定旧口径断言，其他旧断言一律不改；该文件不在 T025 范围。不能用源码注释、死代码或保留无效调用来满足旧字符串检查。
- 处置：保留旧断言，记录 FAIL，不提交 Phase 3；按 Phase 严格串行要求，T015 与 Phase 4–6 暂不完成。需要审查者裁定该旧触感 contract 断言的更新范围。所有 Phase 3 实现保留在 worktree，未撤销任何工作。

- 运行器收尾：Phase 3 unit 的 XCTest 已报告上述结果后，xcodebuild 在 simctl diagnose 阶段日志连续 300 秒未增长，watchdog 按任务规则终止；watchdog 后续 KILL 记录 EPERM（见 unit-watch.log），已核实 xcodebuild 退出，并单独终止残留诊断子进程。原始失败日志和单独复跑日志均保留，未把被中断的全量运行记为 PASS。

- 已裁定（审查者 2026-10-21，依据 Q-D3）：更新 SetEntryAssistTests 第 142 行为新触感形式，强度不变。纳入 T025 改过的旧断言清单，Phase 6 汇总。

### Phase 3 续做（T015）

- 审计：8 个 tracked 修改、1 个 untracked 新测试，无 staged 内容，均为保留的 Phase 3 成果；specs 仅 tasks.md 已改，按授权继续勾选且不提交。
- 结果：PASS。strict lint、App build、build-for-testing PASS；FineCoachTests 516 项 / 515 passed / 1 既有 skip / 0 failed；FineCoachIntegrationTests 189 / 189 passed / 0 failed，包含 measureSetConfirm 的既有性能测试。日志：`DerivedData/StageD/evidence/phase3-resume/{lint,app-build,build-for-testing,unit,integration}.log`。本次运行正常结束，无诊断残留。未经人工视觉检查，并入集中走查。

### Phase 4（T016–T021）

- 范围：已批准的 B 类 D-b 页面组合；复用 DS-SECTION、DS-LIST-ROW、PersonalBestRowView。仅本节收获调用允许纪录数值换行，历史既有行保持单行。总结、详情均使用 SessionGains，档案查看页独立且不改。详情将 card 的 summary block 拆到收获之后以保留备注顺序。
- 设计差异：总结统计/重点后原先直接是备注 → 插入空则隐藏的只读收获；详情 card 备注前插入同一区块；保留全部原有操作和文字读写。D-a～D-c2 本地没有导出 PNG，按任务已确认的 Penpot 批准及 §2 anatomy 实现；读取了既有 29、35 画稿，不新增设计决定。未经人工视觉检查。

- 结果：PASS。strict lint 无输出、App build BUILD SUCCEEDED、build-for-testing TEST BUILD SUCCEEDED；FineCoachTests 516 项 / 515 passed / 1 既有 skip / 0 failed；FineCoachIntegrationTests 190 / 190 passed / 0 failed。日志：`DerivedData/StageD/evidence/phase4/{lint,app-build,build-for-testing,unit,integration}.log`。本轮确认全部代码修改早于证据运行，复用既有证据，无重跑。§5 总结页、详情页两行已对应真实代码。未经人工视觉检查。

### Phase 5（T022–T026）

- 审计：Phase 4 提交后产品仓干净；specs 仅既有 tasks.md 修改，继续仅勾选且不提交。
- 范围和差异：D-c 已批准 B 类修订；保留开关的 identifier、默认关闭和内存状态，标题从「个人最佳」改为「本节收获」；取消空内容的禁用行与 share.pb.none，改为整行隐藏；卡片原 personalBests block 保留分段标识但改名，追加进步与里程碑；共享 FCNewRecordBadge，复用已入库 MascotHeartSticker 资产。历史页个人最佳、档案查看与模型不变。总结/详情的 FCListRow 默认 disclosure 显式关闭，修复只读行箭头漂移（D-FR-020）。
- 实现和检查：DTO schema 3，allowlist 扩展仅 progress 与 milestoneSessionNumber，progress 值复用 ShareReportSetDTO；开关仅 opt-in 后传入同一 SessionGains。新增测试覆盖门控、与总结同源、提示六种组合和空隐藏、第一次/平手/后续课程不改旧纪录、辅助方向、三类卡片渲染与单独进步/里程碑 block。既有 BodyDataReportExclusionTests 与 DTO 禁用词测试正文未改。入口见 §5；未经人工视觉检查。
- 编译修正：首次 App build 中 SwiftUI 对 progress 行报类型推导错误；DTO 的数值展示改为使用既有 TrainingSetDisplayFormatting.summary(for:)（TrainingSet 的 displaySummary 不属于 DTO API）。原始日志保留 app-build-initial.log。测试编译中新增反射测试的 Set 拼接改用 union，原始日志保留 build-for-testing-initial.log；两项均为编译修正，未改测试期望。

- 结果：PASS。strict lint 无输出、App build 与 build-for-testing SUCCEEDED；FineCoachTests 519 项 / 518 passed / 1 既有 skip / 0 failed；FineCoachIntegrationTests 191 / 191 passed / 0 failed。日志：`DerivedData/StageD/evidence/phase5/{lint,app-build,build-for-testing,unit,integration}.log`。测试前分别重启指定 iPhone 17 模拟器；本次正常结束，无诊断挂起。未经人工视觉检查。

### 改过的旧断言清单（累计 3 条期望契约）

| 文件 / 测试名 | 旧期望 → 新期望 | 依据 |
|---|---|---|
| `ios/FineCoachTests/ActiveSession/SetEntryAssistTests.swift` / `testMotionTableIsWiredAtTheApprovedMoments` | 仅 `.sensoryFeedback(.success, trigger: state)` → 同时要求 `.sensoryFeedback(trigger: state)` 与 `isNewRecord ? .impact(weight: .heavy) : .success`；状态迁移断言保留 | D-BLOCK-01 裁定、Q-D3、D-FR-010；Phase 3 已改 |
| `ios/FineCoachTests/ShareReport/ShareReportPolicyTests.swift` / `testAllowlistMirrorMatchesFrozenDTOProperties` | schemaVersion 精确等于 2 → 精确等于 3 | D-FR-032、plan §3.6；resume1 唯一放宽条件，强度不变 |
| 同文件 / 同测试（`allowedShareReportDTOPropertyNames`） | 9 字段精确集合 → 11 字段精确集合（仅加 progress、milestoneSessionNumber）；原有反射、allowlist 等式和 count 断言全保留 | D-FR-032、plan §3.6；resume1 唯一放宽条件，强度不变 |

第一次做、平手、全部历史口径在两个指定测试文件中没有需替换的旧断言；保留原断言，新增严格测试覆盖 Q-D1、D-FR-003、Revision 1.4，不凭空改旧用例。

### Phase 6（T027–T029）

- 审计：Phase 5 提交后产品仓干净；本阶段仅收尾文档与授权 tasks.md 勾选，不改 App 或测试代码。
- 实现和检查：五行执行记录与旧断言清单已补全，§5 共 5 行对应真实代码；blueprint 阶段 D 改为「实现完成，待集中走查」。Phase 3 初次失败、裁定、续做 PASS 原样留存，D-BLOCK-01 已关闭，无其他待决项。
- 未经人工视觉检查、并入集中走查：训练页新纪录标记、持有者转移、小屏/最大字体及 heavy/success 触感；总结页与教练详情页本节收获有内容/无内容（另含只有里程碑）及最大 Dynamic Type 关键数值不截断（AC-D13）；分享开关单行提示、空时隐藏、卡片新纪录胶囊/进步行/里程碑贴纸。没有截图比较、UITests 或真机验收；这些自动门不证明 Feature UI 已视觉验证。

- 结果：PASS。strict lint 无输出、App build BUILD SUCCEEDED、build-for-testing TEST BUILD SUCCEEDED；FineCoachTests 519 项 / 518 passed / 1 既有 WCAG exemption skipped / 0 failed；FineCoachIntegrationTests 191 / 191 passed / 0 failed。日志：`DerivedData/StageD/evidence/phase6/{lint,app-build,build-for-testing,unit,integration}.log`。每个 target 运行前重启指定 iPhone 17 模拟器 EFE2D5A0-4877-4682-BE79-7460C0C1E8C8；测试正常退出，无诊断挂起。全部 Phase 的自动证据已记录；无 BLOCKED 或待决项，保留人工集中走查与审查为后续步骤。

## 5. 入口与布局清单（`components.md` §1.4，实施时填写）

每条新交互一行：画面 → 控件 → accessibility identifier → 是否改数据 → 宽度由谁撑满。每行必须指向真实代码。

| 画面 | 控件 | identifier | 改数据 | 宽度 |
|---|---|---|---|---|
| 课程总结页 | 只读「本节收获」 | `FCAccessibilityID.sessionSummaryGains`；`SessionSummaryView.swift` → `SessionGainsSectionView` | 否 | 页面满宽 VStack，space4 边距 |
| 课程详情页（教练端） | 同一只读区块；在 card 的 summary 之前 | `FCAccessibilityID.sessionDetailGains`；`SessionDetailView.swift` → `SessionGainsSectionView` | 否 | 详情 VStack 与区块 maxWidth infinity，space4 边距 |
| 训练页 | 组行「新纪录」（只读） | `FCAccessibilityID.setNewRecord(set.id)`；`ActiveSessionView.swift` → `FCSetRow.recordBadge` | 否 | `FCSetRow` 的 HStack 与训练页列表容器；胶囊在标题后，空间不足换到标题下方 |
| 分享设置页 | 可见「本节收获」toggle（空收获整行隐藏） | `FCAccessibilityID.shareReportPersonalBestToggle`；`ShareReportFlowView.swift` → `contentSection` | 仅流程内存状态与 DTO，不持久化 | 页面满宽 VStack，space4 边距；toggleRow 的 Spacer 分配提示与开关 |
| 分享卡片 / 预览 | 只读「本节收获」block；渲染图无交互 | `FCAccessibilityID.shareReportGains`；`ShareReportCardView.swift` → `content(for:)` | 否 | CardFrame 固定 cardWidth，space6 边距；section 与行撑满 |
