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

### 最新状态：BLOCKED（2026-10-18）

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
- `ios/FineCoachApp/Core/Persistence/ExerciseManagedObject+Mapping.swift:9` 写入已有 `metadataVersion`；`:209` 的 upsert 按 id 查找再 apply，没有版本比较、retired 同步或升级编排。`:235` 的统一名称 claim 已被其他 owner 占用时抛 `DomainError.conflict`；需覆盖新内置名与用户自定义名冲突，而不能自行更名、覆盖或吞错。
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
