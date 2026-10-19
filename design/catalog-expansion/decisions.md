# C′ 动作库扩充：产品负责人决定

2026-10-15 产品负责人决定把动作库扩充作为功能需求，与阶段 B 并行，不再按评分卡「不列为优化项」处理。

## 决定

| 编号 | 决定 |
|---|---|
| CX-D1 | 数据模型严格遵守 001 spec（`specs/FineCoach/001-m1-a-core-session/data-model.md` §2.2 `ExerciseCatalogItem`、`contracts/`），分类方式照 `catalog-review-100.md`：器械、主部位、动作名。器械枚举 `杠铃` `哑铃` `固定器械` `史密斯机` `绳索` `哈克机` `壶铃` `徒手` `悍马机` `弹力带` `悬挂带` `单杠` `其他`（2026-10-16 修订：原「龙门架」改名「绳索」，新增 5 项；现有条目除龙门架→绳索外不重新归类，动作名不改）；部位枚举 `胸` `肩` `背` `大腿` `小腿` `臂` `臀` `核心`。除此之外不新增枚举值 |
| CX-D2 | 只新增健身房里教练最常用的动作。不设硬数，也不设总数上限；确认来源的外部候选全部收入，置信度低的逐条决定（2026-10-17 修订：删除原「总数上限 300」） |
| CX-D3 | 动作名不写单侧或双侧（不出现「单腿」「单臂」「单手」「双侧」等），训练时由教练切换。名字仍要区分器械和变式（`catalog-review-100.md`「命名与器械」） |
| CX-D4 | 现有 3 条带单侧字样的条目：「单腿腿屈伸」从动作库隐藏并入「腿屈伸」（不删除，旧记录和「上次」匹配不受影响）；「单臂哑铃划船」改名「哑铃支撑划船」；「哑铃单手提走」改名「哑铃提箱走」。隐藏需要在目录 JSON 里加一个「已停用」标记，是数据模型改动，要同步改 001 spec |
| CX-D5 | 来源两条腿走路：wger 和其他有开源许可的健身动作库优先；没有合适开源条目的常用动作可以由 FineCoach 自建。每条都必须写明来源和许可（`provenance.json` 的 `records`），自建条目标明作者为 FineCoach。2026-10-17 补充：开源库里没有、但产品负责人采纳的动作按 FineCoach 自建条目处理，作者 `FineCoach`，许可取本仓库的 `MIT`（见根目录 `LICENSE`） |
| CX-D6 | 新动作的默认单侧沿用 P0 那 14 条的标准：本身一次只练一侧的动作默认单侧，其余默认双侧。审核表里单列一栏 |
| CX-D7 | 2026-10-17 新增：杠铃片、六角杆、地雷杆是杠铃的配件，器械一律归「杠铃」 |
| CX-D8 | 2026-10-17 新增：拉伸和热身动作收入动作库 |

术语提醒：「腿屈伸」是伸膝（leg extension），「腿弯举」是屈膝（leg curl）。俯卧做的是「俯卧腿弯举」，现有目录已有。

## 2026-10-17 修订

产品负责人 2026-10-17 对第 1 步（候选清单）的范围做出以下修订。逐条差异：

| 位置 | 当前状态 | 目标 | 理由 | 是否改变 |
|---|---|---|---|---|
| CX-D2 | 「总数上限 300（现有 146 条在内）」 | 取消总数上限；置信度 high 和 medium 的外部候选全部收入，low 的逐条决定 | 外部候选已逐行审计，按动作实际价值收录，不用条数倒推删减 | 改变 |
| CX-D5 | 自建条目标明作者为 FineCoach | 补充：自建条目作者 `FineCoach`，许可用本仓库 `MIT` | 原条目没写自建许可，第 2 步写 `provenance.json` 需要明确许可标识 | 改变 |
| CX-D7 | 无 | 杠铃片、六角杆、地雷杆归「杠铃」 | 三者是杠铃配件，不新增器械枚举 | 新增 |
| CX-D8 | 无 | 拉伸、热身动作收入动作库 | 教练课上的热身和拉伸需要记录 | 新增 |
| CX-D1 的字段与枚举、CX-D3 命名、CX-D4 现有 3 条改名/合并、CX-D6 单侧默认 | 不变 | 不变 | 第 1 步不改现有条目，不新增枚举和字段 | 保持不变 |

已知不一致：`design/11d-experience-scorecard.md` 的「动作库扩充（总数上限 300）」一句仍写旧上限；2026-10-17 修订后以本文件的 CX-D2 为准，第 2 步同步设计文档时一并更新。

## 流程

1. **调研和候选清单**（交给其他 agent）：调研开源动作库，起草候选清单 `design/catalog-expansion/catalog-review-300.md`，格式照 `catalog-review-100.md`，产品负责人逐条审。
2. **写入**（审核通过后）：写入 `provenance.json`，实现「已停用」标记、合并和改名，补测试，同步 001 spec（C-009 的条数范围、data-model、catalog-review）。

## 2026-10-18 产品负责人批准：第 2a 步

依据：产品负责人 2026-10-18 批准的 `.handoff/2026-10-18-cprime-step1-owner-decisions.md`，以及 `.handoff/prompt/2026-10-18-cprime-step2a-catalog-write-prompt.md`。以下为已批准决定；实现状态另见执行记录。

| 决定 | 位置与当前状态 | 目标 | 理由 | 差异 |
|---|---|---|---|---|
| CX-D9 | 现有 21 条 `equipmentClass` 为「龙门架」 | 改为「绳索」，筛选显示绳索，沿用原图标；动作名、id、旧记录和「上次」保持 | 与 CX-D1 的 13 值一致 | 删除器械值龙门架，替换为绳索；不删除动作 |
| Q1 | 候选有悬垂带、悬吊带 | 统一为悬挂带，记录方式 reps | 修正器械名称 | 改变 |
| Q2 | 弹力带候选使用 weightReps | 弹力带、悬挂带次数动作使用 reps；A1 时长例外保留 | 阻力无统一公斤刻度 | 删除这些候选的重量记录方式 |
| Q3 | 热身命名待决 | 统一「动作 + 热身」 | 统一命名 | 改变 |
| Q4 | 单侧规范化后仍新增近似条目 | 与现有条目合并；单腿臀桥、单腿罗马尼亚硬拉也并入，不再以近似名新增 | CX-D3 单侧由开关表达 | 删除重复新增候选，保留现有条目 |
| Q5 | 绳索训练器独立候选 | 并入绳索弯举 | 同一动作 | 删除重复新增候选 |
| Q6 | 两行哈克机深蹲器械不同 | 都按现有哈克深蹲处理 | 负责人明确判定 | 删除两行新增候选 |
| Q7 | 附录 E 27 组及机械核对报告 18 行待判定 | 器械不同就新增；器械相同、动作相同算已在库。保加利亚蹲(负重)→哑铃保加利亚分腿蹲；负重俄罗斯转体→俄罗斯转体；挂片罗马尼亚硬拉、分腿硬拉→罗马尼亚硬拉；清单附录逐组记结果 | 避免共用来源导致误合并，也避免同器械同动作重复 | 改变判重规则；不改现有 id |
| Q8 | 固定熊爬、平板肘撑转换、仰卧交叉腿、泡沫轴臀部放松的记录方式待审 | 依次 duration、reps、duration、duration | 采纳原清单判断 | 保持 |
| Q9 | low 21 行建议待审 | 采纳建议的 6 条，FineCoach 自建，作者 FineCoach，许可 MIT；其余 15 条不采纳 | 产品负责人批准 | 明确采纳与删除范围 |
| Q10 | 胸表 4 个史密斯机动作归固定器械 | 改归史密斯机 | 修正器械 | 改变 |
| A1 | 弹力带螃蟹行走为 weightReps | duration | 行走按时长，优先于 Q2 通则 | 改变 |
| A2 | 核对报告所列 11 行移除单侧字样后默认否 | 保持否 | 交替不等于单侧，其余由开关表达 | 保持 |
| A3 | `design/11d-experience-scorecard.md` 仍写总数上限 300 | 后续同步为 CX-D2 修订：不设硬数和总数上限 | 删除过时限制 | 待实施 |

本轮范围：数据和必要领域层、旧用户升级验证、spec 同步；拼音搜索、最近使用排序、新器械图标留到第 2b 步。本轮不改 Penpot、README 或 components.md。CX-D4 两条改名和停用继续有效；停用 JSON 字段确定为 `retired: true`，不得改已完成训练的 `displayNameSnapshot`。

## 第 2a 步执行记录

### 最新状态：BLOCKED（2026-10-19 resume3：提交后保护审计失败边界待裁决）

1. **分类和依据**：目录数据与领域层修订；`DS-CHIP` / `DS-EQUIPMENT-ICON` 复用，目标 anatomy、视觉样式不变，按 CX-D1–D12 / D14 更新数据及绳索映射；已读批准画稿 33、README §7.1 / §8、components 对应 anatomy；没有新的组件设计，不改 Penpot、README、components.md。
2. **范围**：初始状态与 resume3 严格一致，13 tracked draft、2 指定 untracked 项，无 staged；bootstrap / gate PASS。本轮新增 startup fallback、Session-only 动态隐藏与释放后 reconcile、新增路径 selectable 校验、固定 146 baseline fixture 及测试。既有半成品保留；specs 独立 topic 仅 spec/data-model 两个草稿，未提交；不写共享 main。唯一模型变动仍是 V6 的 optional isRetired，未改 V1–V5 / pbxproj。
3. **设计决定**：CX-D14 已先独立提交 `6e9b9af`；普通新建/编辑重名仍报错，不能抢占现有 built-in claim。正常 release/reap 与内置 claim reconcile 在同一事务；恢复 generation 验证并 reload 后立即同步。独立 privacy gate 发现下述两条实际代码路径；第一条是未完成的 CX-D14 持久化缺口，第二条涉及已批准“失败已整体回滚”前提之外的存储失败策略，按 prompt 停止，不擅自更改持久化语义。
4. **实施与检查**：离线 verify/build/write 各双跑逐字节一致（r3-determinism.json）；fixture 与 96b385f 原文件完全一致。全仓 strict swift-format lint PASS（r3-swift-format-lint.log）；App Debug iphoneos 无签名 build PASS（r3-app-build.log）；Unit 首次 498 tests / 1 skipped / 2 assertion failures，修正旧版本值及“允许13项≠实际全部使用”的合同后全量重跑 PASS：498 tests / 1 skipped / 0 failures（r3-unit-tests-retry1.log / xcresult）。每次 test 前重启指定 iPhone17，alarm1200、300秒日志 watchdog、parallel-testing-enabled NO。Integration 未运行、0 tests，因停止规则未启动；新 Integration tests 只完成 parse/lint，尚无编译/runtime 证明。两个仓库 diff --check PASS。未跑 UITests、未用 ResetStore、未操作真机；未做人工视觉验证。
5. **结果**：BLOCKED，未完成第2a步；实际 JSON 新增396 / 总542，1 retired，无用户冲突和隐藏时可见541；26个旧条目变化为21绳索+2单杠+2改名+1停用，146旧id保持。代码和测试全部未提交；specs 两个草稿未提交。证据在 `DerivedData/CX2a/evidence/r3-*`，交接 `.handoff/subagent/2026-10-19-cprime-step2a-resume3-blocked.md`。不得把 Unit PASS 当作 Integration 或最终验收完成。

入口与布局清单：动作库筛选 sheet → `FCFilterChip` → `FCAccessibilityID.exerciseLibraryEquipment(equipment)`（`Features/ExerciseLibrary/ExerciseLibraryView.swift:251`）→ 只改筛选状态、器械8项改13项 → `filterSheet` 的 `FCBottomSheet` 内容区 → `VStack` → `FCFlowLayout` 负责内容宽度。其余没有新入口。L3 待人工看：13项小屏换行/滚动、两个改名动作、停用项确实不可见；**未做人工视觉验证**。

#### 未完成项与待裁决边界（静态证据，未做失败注入复现）

- `ActiveSessionUseCases.swift:367–377,437–445`：finish/abandon 先保存结束状态，随后 best-effort 释放 Session-only claim，异常被吞掉。正常路径立即恢复，但释放失败时当前进程内置仍隐藏，直到下次 launch reap。CX-D14 的立即恢复在此失败路径尚不满足；可在续作中研究把结束状态和释放/reconcile 放同一现有 writer transaction，不能靠把异常换成 UI 失败来假装 Session 未结束。未新增 retry queue 或改数据模型。
- `PersistenceWriter.swift:35–48`：save 成功后另做 secureStoreArtifacts，后者可能抛 `postCommitProtectionAuditFailed`；该错误发生在 rollback catch 之外，因此数据已经提交。`AppEnvironment.swift:185–193` 的 fallback 当前把所有同步异常同样处理，有旧条目就继续；这时不能保证“已整体回滚、继续旧目录”。需负责人明确：这类已提交但保护审计失败是否保留原 fail-closed 处理、作为 CX-D14 非阻断降级的例外；或者另行批准提交后恢复协议。没有把任何一个方案当成已批准，不修改全局 writer / 保护策略。

### 历史状态：BLOCKED（2026-10-18 resume2：新内置名与进行中 Session-only claim 冲突）

CX-D12 已记录并提交 `db33187`；清单 `e97d169`、JSON/schema `733d80d` 已提交。实际目录现为 **新增 396 / 总数 542**（含 1 条 retired，未考虑用户偏好时可见 541）；146 个旧 id 保留。旧 401 / 547 仅为历史草稿，不再适用。

**停止依据**：任务要求「遇到上面没写到、并且会影响入库数据或用户已有数据的分歧：停下来写进执行记录，不要自己选」。独立 privacy/security gate 发现新目录名称与进行中 Session-only 动作的 `currentSession` claim 冲突没有负责人裁决。当前草稿保持旧统一名称冲突语义，不删除该 claim，但同步整体回滚；启动错误页阻断训练入口，用户无法结束训练释放 claim。若改成隐藏内置项直到 Session 结束，需要把 CX-D11 的 Custom 例外扩展到 Session-only，属于未批准的数据/行为选择，故停止，不自行采用。

证据：`CoreDataExerciseRepository.swift:506–510` 保留非 builtIn/activeCatalog claim 并抛 conflict；`AppEnvironment.swift:177–187` 设 `catalogUnavailableMessage`；`RootNavigation.swift:80–85` 用错误内容替换业务导航。该场景来自静态路径检查，**尚无 runtime 复现**。独立检查同时指出新增训练路径 `ActiveSessionUseCases.swift:121–129` 直接用不过滤的 `catalogItem(id:)`，旧搜索结果可绕过 retired / custom-shadow；后续需加新增可选性校验并保留历史按 id 查询，不宣称已经修复。未发现本轮新增网络、遥测、凭据或敏感日志路径；不把该结论当物理设备隐私验收。

待负责人裁决：进行中 Session-only 与新内置同名时，是否保留 Session-only claim、临时隐藏内置，并在 Session 结束释放占用后立即恢复；或者指定其他不会阻断已有训练的规则。此处只是选项，未实施、未批准。

五行执行记录：

1. **分类和依据**：批准目录数据修订；对组件属于既有目标的 D 类映射对齐 / 复用，`DS-CHIP` anatomy、样式不变，`DS-EQUIPMENT-ICON` 仅按 CX-D9 把绳索映射到既有 cableCrossover。已读 33 筛选 PNG、README 对应章节及 components 对应项；本轮明确不改 Penpot、README、components.md。13 项数据与组件复用已获任务授权，不增加视觉决定。
2. **范围**：两个 topic worktree 初始状态已审计并 bootstrap / GATE PASS。catalog_data 完成清单与 JSON；ios-swiftui-dev 完成 App 实现草稿和唯一 V6 model 写入；mobile-reliability-tester 完成测试草稿；mobile-privacy-security-reviewer 独立只读检查触发上述 BLOCKED。所有初始 draft 保留继续；原 untracked digest 保留、不提交。新模型以现有 model wrapper 资源编译，无新增源文件注册，故 pbxproj 最终未修改。
3. **设计决定**：CX-D1–D12、Q1–Q10、A1–A3 已应用数据生成。代码草稿采用每次启动按稳定 id 原位同步，保留 preference、createdAt、Custom、训练 snapshot 和模板引用；已核实 archiveCustom 删除 claim，改名和归档均在同一事务立即 reconcile。恢复选择为**恢复完成时立即同步**：generation 完整性验证且重新打开后运行 `prepareExerciseCatalog()`，以免恢复旧目录后仍需等重启；若同步失败，恢复结果只表示 generation 已持久化，目录失败通过 catalogUnavailableMessage 表达，下次启动重试。实现未通过运行测试，不能声称同步和 V6 已完成验收。
4. **实施与检查**：offline verify_sources / build_candidates 双跑逐字节一致；writer 双跑一致；内置中文重名负向校验 PASS，JSON 542 个唯一 id / 542 署名记录，旧 146 id 保留，批准旧条目变化 26。证据 `DerivedData/CX2a/evidence/{candidate-determinism.json,catalog-contract.json}`。全仓 swift-format lint PASS（`swift-format-lint.log`）；App Debug iphoneos build PASS（`app-build-retry1.log`，CODE_SIGNING_ALLOWED=NO）。首次 build 因 Exercise.swift 参数顺序失败（`app-build.log`），一次明确修复后通过。两个仓库 diff --check PASS。**Unit / Integration 未运行，测试数量 0**；未运行 FineCoachUITests、未用 ResetStore、未操作真机，未重启模拟器。测试草稿仅有 parse/lint 静态证据，不能当 runtime 通过。
5. **结果**：BLOCKED。数据三次提交已完成，App 和 tests 草稿保留未提交，specs 的 spec.md / data-model.md 保留未提交；不 push、不 merge main。全量 Unit / Integration gates 待裁决后继续，不能把 build/lint 当 checkpoint 完成。本次停止记录单独提交；交接见 `.handoff/subagent/2026-10-18-cprime-step2a-resume2-blocked.md`。

入口与布局清单：动作库筛选 sheet → 搜索框右侧可见筛选图标 → `FCAccessibilityID.exerciseLibraryEquipment(equipment)` 的 `FCFilterChip` → 8 值变 13 值，仅改变筛选状态 → `ExerciseLibraryView.swift:234–270` 的 `FCBottomSheet` 内容区 / `VStack` / `FCFlowLayout` 撑满容器；其余无新入口。恢复路径沿用可见恢复确认控件和原 identifier，只增加其持久化后的同步。L3 待负责人看：小屏 13 项换行/滚动、两个改名动作和停用条目不可见；**未做人工视觉验证**。

### 历史状态：BLOCKED（2026-10-18 续作：8 行入库裁决，已由 CX-D12 解除）

CX-D10 / CX-D11 已由产品负责人批准并独立提交 `961a157`，上一轮升级方案的审批阻塞已解除。重生成候选时又发现以下会改变入库数据的分歧，依据原任务「遇到上面没写到、而且会影响入库数据或用户已有数据的分歧，停下来写进执行记录，不要自己选」再次停止。不能把本轮草稿的 401 新增 / 547 总数当作最终批准结果；当前实际 JSON 仍为 146 条、新增写入 0 条。

| 行 | 本轮候选名称 / 器械 | 现有名称 / 器械 | 待裁决项 |
|---|---|---|---|
| 胸:47 | 史密斯机V把 / 史密斯机（Q10 修正后） | 史密斯窄距卧推 / 史密斯机 | Q7 决定单将核对 18 行除四例外的其余保留新增；Q7 通则则同器械同动作并入。原表备注明确映射窄距卧推、英文同名，但不足以决定 V 把是否独立变式。需明确并入还是保留新增 |
| 背:65 | 引体向上 / 单杠 | 引体向上 / 徒手 | Q7 器械不同新增，但中文名相同会违反全局 claim；待批准新增名「单杠引体向上」或明确并入 |
| 背:68 | 反手引体向上 / 单杠 | 反手引体向上 / 徒手 | 同上，待批准新增名「单杠反手引体向上」或明确并入 |
| 背:69 | 山羊挺身 / 徒手 | 山羊挺身 / 固定器械 | 原输入无器械映射徒手，FEDB 缓存 equipment 为 other，尚不能证明器械差异；需明确并入或新增器械及名称 |
| 腹:9 | 俄罗斯转体 / 徒手 | 俄罗斯转体 / 哑铃 | 待批准新增名「徒手俄罗斯转体」或明确并入；不把 Q7 对腹:10 的明确例外扩展到本行 |
| 腹:22 | 健腹轮 / 徒手（原名腹肌轮收） | 健腹轮 / 其他 | 缓存 equipment 为 other，器械差异未证实；需明确并入或新增器械及名称 |
| 腿:23 | 罗马尼亚硬拉 / 哑铃 | 罗马尼亚硬拉 / 杠铃 | 待批准新增名「哑铃罗马尼亚硬拉」或明确并入 |
| 腿:84 | 北欧腿弯举 / 其他 | 北欧腿弯举 / 徒手 | 缓存 UUID 与旧条目相同，未提供具体不同器械；需明确并入或新增器械及名称 |

上述新增名仅为审查选项，**未应用、未批准**。不自动改旧条目、不用 CX-D11 把内置之间的重名当成自定义冲突处理。证据：冻结 `design/catalog-expansion/source/2026-10-17/match-audit.csv`、source cache、固定 `96b385f` baseline 及生成草稿附录 E/F。

五行执行记录：

1. **分类和依据**：目录数据修订；`DS-CHIP` / `DS-EQUIPMENT-ICON` 复用既有 anatomy，仅计划按批准枚举更新数据和映射，未引入新组件或视觉设计。批准源为 CX-D1–D11、Q1–Q10、A1–A3；已阅读 33 筛选画稿、README 和 components 对应条目。本轮不修改 Penpot、README、components.md。
2. **范围**：初始状态严格符合 resume 要求，只有指定 untracked digest，保留不提交。bootstrap / gate PASS，main 已为 HEAD 祖先。数据 agent 修改候选生成器、清单草稿、评分卡；ios agent 有四个 Swift 文件半成品；测试 agent 未编辑测试。specs 已审计 clean，在独立 topic worktree 中只有 data-model 草稿，原共享 main 未修改。
3. **设计决定**：`961a157` 仅记录已批准升级机制。静态核实 `archiveCustom` 删除名称 claim，故改名或归档可作为找回入口；同步机制、V6、恢复后同步时机尚未完成，不宣称已实现。上述 8 行留给产品负责人裁决。
4. **实施与检查**：`git diff --check`（产品和独立 specs worktree）PASS；未运行全仓 lint、App build、Unit、Integration，测试数量 0，无运行闸门日志。未运行 UITests、未重启/使用模拟器、未用 ResetStore；没有人工视觉验证。Swift 同步辅助实现未完成，当前工作区不可视为可构建，需续作，不可安装分发。
5. **结果**：BLOCKED。JSON / schema 保持原样，现有 146 个 id 未改；未改 Core Data 模型 / pbxproj；全部 draft 保留未提交，只有已批准决定及本执行记录独立提交。提交号、准确剩余文件和恢复入口见 `.handoff/subagent/2026-10-18-cprime-step2a-resume-blocked.md`。

入口与布局清单：动作库筛选 sheet → `FCFilterChip` → `FCAccessibilityID.exerciseLibraryEquipment(equipment)` → 只改变筛选状态 → `ExerciseLibraryView.swift` 的 `filterSheet` / `FCBottomSheet` → `VStack` → `FCFlowLayout` 撑满内容宽度；目标由 8 值变 13 值，领域枚举 draft 已改，完整实现和闸门未完成。其余没有新入口。L3 待人工看：13 项在小屏上的换行或滚动、两个改名动作、停用条目不可见；**未做人工视觉验证**。

### 历史状态：BLOCKED（2026-10-18 首轮，升级方案待审批）

任务第 3 步明确要求：「如果需要改 Core Data 模型（新的模型版本、新属性），或者需要你自己设计迁移：先停下，把方案写进执行记录交给产品负责人，不要自己做。」提前核查升级路径后发现没有可沿用的版本更新机制，需要设计已有存储的数据升级；因此在清单重生成、JSON 写入及代码实施前停止。不是已确认必须改 Core Data 模型；不能把具备 upsert helper 等同于已实现安全升级。

五行执行记录：

1. **分类和依据**：本轮为已批准目录数据修订及必要领域层变更；筛选沿用既有 chip、布局与图标，目标仅扩充枚举。尚未实施 UI，不主张视觉验收。依据 CX-D1–CX-D9、Q1–Q10、A1–A3 和任务第 3 步停止条件。
2. **范围**：初始审计只有 untracked `design/catalog-expansion/external-taxonomy-digest.md`，无 tracked 修改、无 staged 内容；保留且未提交。`feat/catalog-expansion` 已 merge 本地 main（`25949bd`），bootstrap 完成，worktree gate PASS；仅追加本文件的已批准决定与本执行记录。
3. **设计决定**：产品负责人批准内容已独立提交 `4976e7c`；下面的升级方案只是待审候选，不是新增批准决定。未修改 Core Data 模型、JSON、脚本、Swift、specs、Penpot、README 或 components.md。
4. **实施与检查**：静态追踪启动、seed、repository、mapping、bundle loader 和名称 claim；现有 JSON 实测 146 条、龙门架 21 条。本文件执行 `git diff --check` 并回读；完整 lint、App build、Unit、Integration 均未运行，测试数量 0；未运行 UITests、模拟器或真机。证据为下列源码位置和 `.handoff/subagent/2026-10-18-cprime-step2a-blocked.md`，未产生 `DerivedData/CX2a/evidence/` 运行日志。
5. **结果**：BLOCKED；新增写入 0 条，当前目录仍为 146 条，批准清单尚未重生成，最终目标总数尚未计算。合并和决定提交见上；本执行记录随独立文档提交保存，提交号见交接文件与最终回报。没有完成第 2a 步，不宣称测试或升级通过。

### 已安装用户升级机制：静态核查证据

- `ios/FineCoachApp/App/AppEnvironment.swift:176` 的 `prepareExerciseCatalog` 调用 `ExerciseLibraryUseCases.seedIfNeeded`（`Core/Application/ExerciseLibraryUseCases.swift:14`），后者只调用 `seedPlaceholderCatalogIfNeeded`。
- `ios/FineCoachApp/Core/Persistence/CoreDataExerciseRepository.swift:11`：先计数，100…150 条时直接返回，发生在加载 bundle JSON 之前；146 条的旧存储不会读取新增条目和改名，不比较 `metadataVersion` / `contentVersion`。该路径不是逐启动按 JSON 同步，也不只是绝对意义上的首次安装写入；条数不在区间时会重建。
- 同文件 `:251` 固定范围 100…150；`:272` 对新 JSON 仍做同一条数限制。只扩充 JSON 会使新安装拒绝初始化；只放宽范围又会令 146 条旧存储继续提前返回。
- 同文件 `:301` 的 `removeBuiltInCatalog` 删除内置条目及其名称 claim 和 preference（`:310–314`）。不能沿用此重建路径来满足单侧、辅助、收藏、隐藏、别名偏好保留要求。
- `ios/FineCoachApp/Core/Persistence/ExerciseManagedObject+Mapping.swift:9` 写入已有 `metadataVersion`；`:212` 的 upsert 按 id 查找再 apply，没有版本比较、retired 同步或升级编排。`:235` 的统一名称 claim 已被其他 owner 占用时抛 `DomainError.conflict`；需覆盖新内置名与用户自定义名冲突，而不能自行更名、覆盖或吞错。
- `ios/FineCoachApp/Core/Application/ExerciseProvenanceValidator.swift:228` 从 bundle 解码 JSON；`:275` 的 facet cache 只把 JSON 分类映射给已有行，不插入存储行、不更新存储显示名，不构成升级机制。
- `ios/FineCoachApp/Core/Persistence/SessionManagedObject+Mapping.swift:41` 独立持久化 `displayNameSnapshot`，`:123` 读取；后续升级方案必须完全不写 Session 及其 snapshot。

### 待审升级候选方案（未实施）

建议在现有 Core Data 模型上研究按稳定 id 原位同步目录：先完整校验候选 JSON、来源、id、名称和版本，再在单个现有 writer transaction 内新增缺失内置动作、更新已有内置动作的目录显示名及 metadata，保留原 createdAt 和所有 preference，不调用 `removeBuiltInCatalog`。不触碰自定义动作、Session、模板引用和训练名字快照。重复启动应幂等，任一失败应回滚并保留最后有效状态；成功后再报告目录可用。

`retired` 可研究仅作为 bundle 元数据来过滤列表与搜索，按 id 读取保留；是否足够覆盖备份/恢复和旧目录仍需后续证明，不据此新增模型属性。条数 gate 应由新目录合同替代旧 100…150 范围，不能只移除校验。以上属于待批准的数据升级设计，不是已完成迁移。

需要产品负责人审查并授权上述升级机制后继续；另需明确新内置名称或改名与已有自定义动作的 claim 冲突时采取何种产品行为。现有证据只能确定当前会抛 conflict，不能擅自选择覆盖、更名或跳过。升级 Integration 验证仍须用旧 JSON 预置存储覆盖新增、改名、停用、偏好、自定义动作、已完成训练 snapshot 保留及幂等结果。

### 入口与布局清单、L3

| 屏幕 | 可见控件 / identifier | 数据变化 | 宽度 owner | 状态 |
|---|---|---|---|---|
| 动作库筛选 sheet | `ExerciseLibraryView.swift:247`，`FCFilterChip` / `FCAccessibilityID.exerciseLibraryEquipment(equipment)` | 计划由 8 个器械值扩至 13 个，只修改筛选条件，不持久化训练数据 | `filterSheet` 的 `FCBottomSheet` 内容区 → `VStack` → `FCFlowLayout`（`:234–240`） | 未实施，仍为 8 项；无其他新入口 |

L3 待人工看：13 项筛选在小屏上的换行或滚动、两个改名后的动作、停用动作在列表与搜索中不可见。**未做人工视觉验证**。

## 2026-10-18 产品负责人批准：CX-D10 / CX-D11（续作）

依据：`.handoff/prompt/2026-10-18-cprime-step2a-resume-prompt.md`。以下覆盖上一轮待审方案和模型停止条件，历史 BLOCKED 记录保留。

| 决定 | 位置 / 当前状态 | 目标 | 理由 | 差异 |
|---|---|---|---|---|
| CX-D10 同步 | seed 按 100–150 条短路，异常时删除并重建 | 每次启动按稳定 id 在一个事务内更新、插入，失败整体回滚，重复执行幂等；移除数量上限，改结构校验 | 已安装用户也获得新目录并保留用户数据 | 删除重建路径及数量 gate；保留 preference、自定义动作、createdAt、Session 名字快照和模板引用 |
| CX-D10 停用 | 目录没有持久化停用字段，当前模型 V5 | 新建 V6，仅内置动作实体新增 optional Bool `isRetired`、默认 false，轻量迁移；JSON 消失的内置项也标为停用 | 旧引用可继续按 id 读取 | 新增停用过滤：列表、搜索、添加选择器过滤；id 查询保留 |
| CX-D10 恢复 | 备份恢复可能恢复旧目录 | 恢复完成立即同步或下次启动同步；实施记录明确采用的路径 | 恢复旧备份仍获得当前目录 | 增加恢复后对比；保留最后有效状态 |
| CX-D11 名称 | 新增或改名内置动作遇自定义 claim 会冲突 | 自定义优先；冲突内置项在本机隐藏，每次同步重新计算，不写 isRetired；不弹窗、不改自定义名、不向 UI 抛该冲突 | 保留教练名字与历史 | 增加动态隐藏，删除这类冲突的 UI 错误路径 |
| CX-D11 找回 | 尚未核实归档是否释放 claim | 自定义改名后立即重新同步；归档仅在实际释放 claim 时同样找回，并记录调查结论 | 不等下次启动 | 新增改名后的立即同步；归档行为按现有 claim 生命周期核实，不自行改变 |
| 其他边界 | CX-D1–D9、Q1–Q10、A1–A3 已批准 | 保持；仅数据与必要领域层，FCEquipmentIcon 龙门架→绳索映射 | 本轮不引入第 2b 步 | 不新增图标、拼音、最近使用排序，不改 Penpot、README、components.md |

本轮初始审计：HEAD `96b385f`，`feat/catalog-expansion`；仅 untracked `design/catalog-expansion/external-taxonomy-digest.md`，无 tracked / staged 修改。该文件视为用户所有，保留且不提交。main 已为 HEAD 的祖先，无需重复 merge；bootstrap 与 worktree gate PASS。

## 2026-10-18 产品负责人批准：CX-D12（8 行入库裁决）

依据：`.handoff/prompt/2026-10-18-cprime-step2a-resume2-prompt.md` 和决定单末尾的 CX-D12。以下裁决解除上一轮 8 行阻塞；不把草稿 401 / 547 当最终统计。

| 位置 | 当前状态 | 目标 | 理由 | 差异 |
|---|---|---|---|---|
| 胸:47、背:69、腹:22、腿:84 | 曾列新增候选 | 并入现有条目，不新增 | 负责人逐行裁决 | 删除四条新增候选，保留现有 id |
| 背:65、背:68 | 现有引体向上、反手引体向上为徒手 | 并入现有，器械原位改为单杠，名字和 id 不变 | CX-D10 同步；负责人明确器械 | 删除两条新增候选，修改两条现有器械；偏好和训练记录保持 |
| 腹:9 | 候选与现有俄罗斯转体同名 | 新增徒手俄罗斯转体，器械徒手 | 批准器械变式和唯一名 | 新增；现有俄罗斯转体保持哑铃 |
| 腿:23 | 候选与现有罗马尼亚硬拉同名 | 新增哑铃罗马尼亚硬拉，器械哑铃 | 批准器械变式和唯一名 | 新增；现有罗马尼亚硬拉保持杠铃 |
| 内置中文名 | 生成器未拒绝跨器械中文重名 | 内置之间不得中文重名，生成器重名即失败；以后遇到未裁决同名停止报告 | 不自动加前缀或静默隐藏 | 新增校验，只有上述两条批准名称生效 |

续作初始审计：`feat/catalog-expansion` / HEAD `d600cf9`，7 个未暂存 tracked 草稿与指定 untracked digest 完全匹配；无 staged 内容。已逐项识别为上一轮半成品，保留继续审阅。specs topic worktree 仅有 `FineCoach/001-m1-a-core-session/data-model.md` 未暂存草稿；共享 specs main 不写入。

## 2026-10-19 产品负责人批准：CX-D15（第四次续作）

依据：`.handoff/prompt/2026-10-19-cprime-step2a-resume4-prompt.md` 和决定单 CX-D15。以下为批准合同，实施结果另记。

| 位置 | 当前状态 | 目标 | 理由 | 差异 |
|---|---|---|---|---|
| AppEnvironment 同步失败 | 已有目录时所有错误均放行 | `postCommitProtectionAuditFailed` 保持目录不可用拦截；其余已回滚失败按 CX-D14 使用旧目录 | 保存后保护审计失败不符合整体回滚前提 | 增加 CX-D14 例外；不改 PersistenceWriter |
| finish / abandon | 结束状态先提交，名称占用随后尽力释放 | 结束状态和临时动作 claim 释放同一写事务；随后目录同步尽力执行，失败不影响结束，下次启动补上 | 保证结束与占用释放原子性 | 删除分离的释放事务；保留目录同步重试机制 |
| 哈克深蹲、哈克机提踵 | 器械为固定器械 | 经生成脚本改为哈克机，名字和 id 保持，按 CX-D10 原位同步 | CX-D1 不重新归类的明确例外 | 仅修改两条器械；增加哈克机 → `.hackSquat` 映射，其他映射不变 |
| 图标整合 | 另一个设计分支已有画板与图标 | 本轮不合并 | 独立任务范围 | 保留 icons、Assets、Penpot、README、components.md |

初始审计：`feat/catalog-expansion@adfc8c6`，16 个 tracked 未暂存修改、3 个指定 untracked 项，无 staged 内容，与 resume3 交接一致；specs `feat/finecoach-catalog-cx2a` 仅 `spec.md` / `data-model.md` 两个草稿。保留全部既有改动；digest 不提交。

## 2026-10-19 产品负责人批准：CX-D14（第三次续作）

依据：`.handoff/prompt/2026-10-19-cprime-step2a-resume3-prompt.md` 和决定单 CX-D14。

| 位置 | 当前状态 | 目标 | 理由 | 差异 |
|---|---|---|---|---|
| Session-only 名称占用 | 新增或改名内置与 currentSession claim 同名时抛 conflict，启动被阻断 | 临时动作优先；保留名称、记录和 claim，同名内置动态隐藏，不写 isRetired，不弹窗、不改名、不向界面抛该冲突 | 保留进行中训练可用性 | 删除该 conflict 分支；训练结束、放弃或删除等实际释放占用路径立即重新同步 |
| 已有目录同步失败 | catalogUnavailableMessage 拦整个 App | 事务整体回滚后继续旧目录，下次启动重试；失败仅保留本地状态，无敏感日志和遥测 | 旧目录仍可用 | 删除已有目录失败的启动拦截；首次安装无任何内置条目仍显示目录不可用 |
| 备份恢复后同步失败 | 恢复后立即同步，失败拦 App | 保持恢复后立即同步，失败不拦 App，继续恢复的有效旧目录 | 与启动降级一致 | 改变失败处理；保留恢复 generation 的持久化验证 |

本轮初始审计：`feat/catalog-expansion@a0d12cf`，13 个 tracked 未暂存草稿、2 个指定 untracked 项，无 staged 内容；specs topic 仅 `FineCoach/001-m1-a-core-session/{spec,data-model}.md` 两个未暂存草稿。所有既有半成品继续审阅，digest 保留不提交；不切换或重建 worktree。
