# C′ 动作库扩充：产品负责人决定

2026-10-15 产品负责人决定把动作库扩充作为功能需求，与阶段 B 并行，不再按评分卡「不列为优化项」处理。

## 第 2b 步执行记录（2026-10-19）

1. **分类和依据**：B 类；批准来源 `design/cprime-2b-boards` `8172c8c`、Penpot 快照 `cprime-2b approved 2026-10-19`、设计交接「第二轮」「验收通过」。从干净本地 main `5730401` 创建 `.worktrees/cprime-2b` / `feat/cprime-2b`，bootstrap 与 worktree gate PASS，合并设计提交 `03a6926`；主 checkout 不改动。
2. **范围**：`DS-EQUIPMENT-ICON` 扩展 18 → 21；`DS-SECTION` / `DS-LIST-ROW` 复用。动作库页面与训练中添加动作面板新增「最近练过」，模板编辑器保持；动作库搜索和添加面板共用 CoreData 拼音搜索。既有动作行抽取为 `FCExerciseLibraryRowLabel`，登记 CG-10，普通 `FCListRow` 不变。无需新 Swift 文件或改 `project.pbxproj`；目录 JSON、Core Data 模型和用户数据不变。
3. **设计决定**：复用批准的 3 个新图标、5 个替换图标、最近 5 个不同目录动作与两种历史范围；CX-D13 仅允许壶铃 `#2A2822` 铃身填充。添加面板原实现只有 quick-create 表单和最多 8 个搜索建议，本轮按批准画板补齐部位 chips、筛选按钮与器械 bottom sheet、完整分组列表；原有创建控件保留在筛选结果下方，仍由同一动作名字段与既有保存用例驱动，无新增修改数据路径。共享行最小高度约束放在 padding 外侧，保留原行内边距而不额外撑高。内置拼音随 facet 首次加载预热，动态名称/alias 按内容缓存，避免改名后旧缓存继续命中；仅用 Foundation。Penpot board 17 回填由 Claude 负责，本任务不操作 Penpot。
4. **实施与检查**：`IconConsistencyTests` 覆盖 21 个顶层 SVG 的双向枚举、逐字节一致、viewBox、stroke、唯一 fill 例外、template 与 13 类器械映射；`ComponentCatalogTests` / `TouchTargetComponentTests.testExerciseLibraryRowDeclaresApprovedAnatomyAndFullWidthContract` 覆盖组件登记与行合同，组件含 icon/favorite 与 custom/no-icon Preview。`ExerciseIdentityTests.testRecentExercises*` 覆盖去重、倒序、不可选跳过并补足最多 5 个、当前学员/全体、临时动作与空历史；`ExercisePersistenceTests.testRecentSelectionUsesPersistedCompletedHistoryForStudentAndCoach` 覆盖已完成历史的 repository 集成。`ExerciseProvenanceTests.testPinyinSearch*` 与 `ExercisePersistenceTests.testSearchSupportsPinyinForBuiltInAliasAndCustomExercise` 覆盖全拼、空格、首字母、子串、大小写、不相关、alias/custom 与 alias 更新；中文命中及顺序、器械/部位匹配由同一 integration 测试明确断言。页面组合由 `DesignValueScanTests` 与下列入口清单记录。L3：待负责人在集中走查看两处「最近练过」、新图标与添加面板筛选/创建控件衔接，**没有人工视觉验证**。
5. **结果**：自动实施 gates **PASS**：全仓 strict lint、device SDK App build、`build-for-testing` PASS；L0/L1 42 tests（0 failures、1 skip），`FineCoachTests` 全量 504 tests（0 failures、1 skip），`FineCoachIntegrationTests` 全量 187 tests（0 failures）。skip 为既有 `ContrastHarnessTests.testTextDisabledOnSurfacePageIsWCAGExempt`。运行环境仅指定 iPhone 17 `EFE2D5A0-4877-4682-BE79-7460C0C1E8C8`，每次运行前 shutdown / boot / bootstatus；未运行 `FineCoachUITests`、未使用 reset-store、未用真机。证据位于 `DerivedData/C2b/evidence/`，下表保留失败与最终结果。代码提交：图标 `30d744e`、最近练过 `9a6de8a`、拼音 `90c6109`；无 push、无合入 main。审查、Claude Penpot board 17 回填与 L3 集中走查 **PENDING**，自动 PASS 不代表人工视觉验收。

**Penpot 回填（2026-10-19，Claude）**：「M1-B G5 Design」Foundations 页「17 器材 icon 库」按 `design/m1-b-hifi/icons/` 更新：barbell、dumbbell、pec-deck、kettlebell（实心铃身，CX-D13）、cable-crossover 替换为新版；新增 plate-loaded（悍马机）、suspension-trainer（悬挂带）、pull-up-bar（单杠）一行，画板高 600 → 680，共 21 个；沿用原有 36×36、描边 3（24 网格的 1.5 倍）、圆角端点。快照 `before-C2b-board17 2026-10-19` → `C2b icons backfilled to board 17 2026-10-19: 21 icons`。`design/m1-b-hifi/screens/17-icons.png`（2x）待产品负责人在 Penpot 里重新导出。

### 本轮差异（包含移除项）

| 位置 | 当前状态 | 目标 | 理由 | 改变或保留 |
|---|---|---|---|---|
| 图标库 / Assets / README §7.1 | 18 个；5 个旧图；全部无填充；4 类器械无映射 | 21 个，替换 5 个，新增 4 类映射，壶铃唯一实心例外 | CX-D13 与批准画板 | 删除旧图字节和旧数量/无填充绝对断言，保留其余几何与 template 合同；extras 不导入 |
| 动作库页面 | 搜索/筛选后直接完整列表 | 默认有已完成历史时最近分组 → 16pt → 完整列表 | 批准最近练过画板 | 新增分组；无历史/有查询/有部位或器械筛选时不占位；完整列表不去除 recent 重复项 |
| 添加面板「动作库」 | quick-create 表单、最多 8 个建议；无完整浏览筛选 | 搜索/筛选 → recent → 16pt → 完整分组列表 | 实现批准画板的已有浏览结构 | 删除 8 条建议截断与旧简化建议行；保留原创建字段/按钮/用例、从模板分段与模板编辑器 |
| 动作行 | feature 内手工 label | 共享 DS-LIST-ROW 既有动作行变体 | 两处 recent 与完整列表保持同一 anatomy | 删除重复拼装；保留图标/名字/副文字/收藏/箭头及 token，显式满宽 |
| Core 搜索 | 中文/现有文字、器械/部位匹配 | 增加名称与 alias 的全拼/首字母子串匹配 | 批准维度 5 | 原匹配与结果排序、signpost 保留；无手写多音字映射、数据修改或依赖 |

### 入口与布局清单

路径均相对于 `ios/FineCoachApp/`；动态 identifier 由 `App/FCAccessibilityID.swift` 定义。

| 页面 → 可见控件 | 无障碍标识 | 是否改数据 | 宽度 owner / 真实代码 |
|---|---|---|---|
| 动作库 →「最近练过」动作行 → 原选项面板 | 分组 `exerciseLibraryRecent`，行 `exerciseLibraryRecentRow(id)`，与完整列表 `exerciseLibraryRow(id)` 不同 | 打开选项本身不改数据；后续沿用原用例 | `Features/ExerciseLibrary/ExerciseLibraryView.swift:172` → `FCExerciseLibraryRowLabel`（`DesignSystem/Components/FCListRow.swift:212` 满宽） |
| 添加动作「动作库」→「最近练过」动作行 | 分组 `addExerciseRecent`，行 `addExerciseRecentRow(id)` | 是，调用既有 `addCatalogMatch` 添加到当前训练 | `Features/ActiveSession/QuickCreateExerciseFlow.swift:11` → 满宽 `FCExerciseLibraryRowLabel` |
| 添加动作「动作库」→ 搜索动作 | `activeSessionExerciseName`（沿用） | 否，只改变查询 | `QuickCreateExerciseFlow.swift:122` 的 HStack → `FCSearchField` 弹性宽度 |
| 添加动作「动作库」→ 全部 / 部位 chip | `activeSessionCatalogMuscleAll` / `activeSessionCatalogMuscle(group)` | 否，只改变筛选 | `QuickCreateExerciseFlow.swift:148` 的横向 ScrollView / HStack → `FCFilterChip` |
| 添加动作「动作库」→ 筛选图标 | `activeSessionCatalogFilter` | 否，只打开筛选面板 | `QuickCreateExerciseFlow.swift:129` 的 `FCTitleIconButton`，搜索行 HStack 分配宽度 |
| 添加动作筛选面板 → 全部 / 器械 chip | `activeSessionCatalogEquipmentAll` / `activeSessionCatalogEquipment(group)` | 否，只改变筛选 | `Features/ActiveSession/ActiveSessionView.swift:622` 的 `FCBottomSheet` 内容 VStack / `FCFlowLayout` |
| 添加动作筛选面板 → 完成 | `activeSessionCatalogFilterDone` | 否，只关闭筛选面板 | `ActiveSessionView.swift:647` 的 `FCLinkButton.frame(maxWidth: .infinity)` |
| 添加动作「动作库」→ 完整列表动作行 | `activeSessionCatalogRow(id)`（沿用），section `activeSessionCatalogSection(id)` | 是，调用相同 `addCatalogMatch` | `QuickCreateExerciseFlow.swift:32` → 满宽 `FCExerciseLibraryRowLabel` |

### 拼音系统误读

542/542 条已逐项使用 Foundation 转写，完整证据 `DerivedData/C2b/evidence/pinyin-audit.txt`。53 条含「弹力带」的名字系统读作 `dàn lì dài`（语境应为 `tán lì dài`）；10 条「地雷/地板/贴地」系统将「地」读作 `de`：地雷管推举、地雷杆甩、地雷杆划船、地雷杆硬拉、哑铃地板卧推、杠铃地板卧推、地板飞鸟、地板飞鸟(负重)、跪姿地板飞鸟、贴地俯卧撑转体拉伸。依任务保留系统结果，不改目录或手写纠正表。任务示例 `gldl → 杠铃弯举` 与系统 `glwj` 不一致，实现遵循系统转写。

### 验证证据与修复次数

| 检查 | 真实结果 | evidence 下的文件 |
|---|---|---|
| 全仓 strict lint（最终） | PASS，0 diagnostics | `lint-acceptance.log` |
| App device SDK build（最终布局） | PASS，`CODE_SIGNING_ALLOWED=NO` | `app-build-final.log` |
| 测试 targets 编译（最终） | PASS；仅编译，不执行 UI tests | `build-for-testing-acceptance.log` / `.xcresult` |
| L0/L1（最终） | PASS，42 tests / 1 skip / 0 failures | `l0-l1-acceptance.log` / `.xcresult` |
| Unit 全量（最终） | PASS，504 tests / 1 skip / 0 failures | `unit-acceptance.log` / `.xcresult` |
| Integration 首轮 | FAIL，187 tests / 3 failures（1 unexpected），两条新增测试失败 | `integration.log` / `.xcresult` |
| 两条失败测试先单独重跑 | FAIL，2 tests / 3 failures，复现首轮原因 | `failures-isolated.log` / `.xcresult` |
| 两条测试各修正一次后单独重跑 | PASS，2 tests / 0 failures | `corrected-isolated.log` / `.xcresult` |
| Integration 修正后复验 | PASS，187 tests / 0 failures；随后发现并修正共享行最小高度约束的位置 | `integration-final.log` / `.xcresult` |
| Integration 全量（最终布局） | PASS，187 tests / 0 failures | `integration-acceptance.log` / `.xcresult` |
| 模拟器重启 | 每次运行单独记录；最终三次由 fail-fast 脚本串行运行 | `*-reboot.log`，脚本 `../run-acceptance.sh` |
| SVG / 转写 | 21 SVG byte/template PASS；542/542 条系统转写 | `icon-artifacts.log`、`pinyin-audit.txt` |

两条测试各仅修正 1 次：recent fixture 原本给 `.reps` 引体向上传了重量/公斤，违反现有 `TrainingSet` 合同，改为次数单位、不带重量；拼音测试原先错误要求拼音集合等于中文「卧推」集合，忽略 `卧腿 → wotui` 同音与 `抬腿 → wt` 首字母。修正后仍断言原中文命中完整保留且顺序不变，并增加明确同音、首字母额外命中与器械/部位匹配断言；没有更改产品匹配规则、删测试或缩小全量 gates。最后的行修正只把最小高度约束移至 padding 外侧，避免额外增加行高；收紧组件源码测试的扫描范围到该组件，并重新执行全部自动 gates。

### 拼音字级修正（2026-10-19）

1. **决定与范围**：产品负责人在 `.handoff/prompt/2026-10-19-pinyin-polyphone-fix-prompt.md` 批准将「弹」固定为 `tan`、「地」固定为 `di`，替代本轮上方「保留系统结果」对这两个字的处理；其余字仍用 Foundation，不扩成通用多音字表。由干净本地 main `0c683bf` 创建 `.worktrees/pinyin-polyphone` / `fix/pinyin-polyphone`，bootstrap 与 worktree gate PASS，初始无 tracked modification、untracked file 或 staged content。
2. **改动**：`ExercisePinyinSearch.makeTokens` 在 Foundation 转写前应用仅两项的常量覆盖，注释注明决定日期；覆盖读音两侧保留空格，确保连续「弹地」等仍有独立音节。`sourceValue` 保持原名称，full pinyin 与 initials 共用修正结果；内置预计算缓存和 custom / alias 按需缓存继续走同一路径。代码提交 `5cab194`，未改目录 JSON、动作名、Core Data 模型或界面。
3. **审计**：在 macOS Foundation 上用修改前与最终实际源码分别生成全部 542 条 tokens，并逐条核对前轮 `DerivedData/C2b/evidence/pinyin-audit.txt` 的系统转写。**64 条变化，478 条完全不变，非「弹／地」条目变化 0，目标误读剩余 0**。变化包含 53 条「弹力带」、1 条「弹跳引体」及 10 条「地」；「弹跳引体」原为 `dantiaoyinti` / `dtyt`，字级决定使其成为 `tantiaoyinti` / `ttyt`。证据为本 worktree 的 `DerivedData/Pinyin/evidence/pinyin-audit.txt`、`pinyin-before.json`、`pinyin-after.json`、`pinyin-comparison.txt`；同目录保留生成脚本、对比脚本、源码快照和环境信息。此审计不替代 iOS runtime 测试。
4. **回归与入口**：保留全部原有拼音测试，新增 3 个 unit tests，覆盖全拼、空格、首字母、旧读音拒绝、自定义名称／别名及连续覆盖字的音节边界；新增 1 个 integration test，通过实际 repository 覆盖内置「弹力带／地雷」、custom 与 alias 搜索。页面组合、入口、identifier、数据 mutation 与 width owner 均沿用上方第 2b 步入口清单，本轮无新增交互或布局，未进行人工视觉验证。
5. **结果**：最终 **5/5 gates PASS**：全仓 strict lint、App device SDK Debug build、`build-for-testing`、`FineCoachTests` 全量 **507 tests / 0 failures / 1 skip**、`FineCoachIntegrationTests` 全量 **188 tests / 0 failures**。skip 为既有 `ContrastHarnessTests.testTextDisabledOnSurfacePageIsWCAGExempt`。每次测试前 shutdown / boot / bootstatus，仅使用 iPhone 17 `EFE2D5A0-4877-4682-BE79-7460C0C1E8C8`；全量运行有 1200 秒硬时限和日志 300 秒无增长终止监控。未运行 `FineCoachUITests`、未用 reset-store 或真机。无 BLOCKED 项，审查 **PENDING**；未 push、未合入 main，主 checkout 保持原状。

| 位置 | 原状态 | 最终状态 | 理由与差异 |
|---|---|---|---|
| `ExercisePinyinSearch` 的「弹」 | 系统输出 `dan` | 字级覆盖 `tan`，对应 initials 改为 `t` | 删除该字对系统误读的依赖；执行 2026-10-19 决定 |
| `ExercisePinyinSearch` 的「地」 | 系统输出 `de` | 字级覆盖 `di`，initials 仍为 `d` | 删除该字对系统误读的依赖；执行同一决定 |
| 其余字、查询归一化、缓存、目录及界面 | 第 2b 步实现 | 保持 | 修复仅限两个字，不新增控件或数据 mutation |

全部证据位于本 worktree 的 `DerivedData/Pinyin/evidence/`：

| 检查 | 最终结果 | 证据 |
|---|---|---|
| 全仓 strict lint | PASS，0 diagnostics | `lint-final.log` |
| App device SDK Debug build | PASS，`CODE_SIGNING_ALLOWED=NO` | `app-build-acceptance.log` |
| `build-for-testing` | PASS，仅编译 UI tests | `build-for-testing-acceptance.log` |
| Unit 全量 | PASS，507 tests / 1 skip / 0 failures | `unit-acceptance.log` / `.xcresult`、`unit-acceptance-reboot.log` |
| Integration 全量 | PASS，188 tests / 0 failures | `integration.log` / `.xcresult`、`integration-reboot.log` |

过程证据保留：`lint.log` 首轮有两处换行格式错误，格式化后全仓复验通过；首轮 `unit.log` 为 506 tests / 1 skip / 0 failures。随后独立转写检查发现连续「弹地／地弹／弹弹／地地」丢失 initials 音节边界，修复一次并增加回归断言后，重新生成审计并重跑最终全部 gates，以上仅以最终结果计完成；未删测试或放宽断言。

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

## 2026-10-19 产品负责人批准：CX-D13（图标填充例外）

依据：`.handoff/prompt/2026-10-19-cprime-step2b-implement-prompt.md` 与设计交接「第二轮」「验收通过」。`kettlebell` 铃身保留实心填充 `#2A2822`，并允许 `none`；其他 20 个图标只允许 `none`。这是唯一填充例外，导入时同步 README §7.1、组件规格和 `IconConsistencyTests`；`extras/` 的 5 个备选不进 App。

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

已知不一致（2026-10-30 核对已解决）：体验评分卡里「总数上限 300」的旧说法已改为 CX-D2（不设硬数和总数上限）。体验评分卡已移出本仓库。

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
| A3 | 体验评分卡仍写总数上限 300 | 后续同步为 CX-D2 修订：不设硬数和总数上限 | 删除过时限制 | 已实施（2026-10-30 核对） |

本轮范围：数据和必要领域层、旧用户升级验证、spec 同步；拼音搜索、最近使用排序、新器械图标留到第 2b 步。本轮不改 Penpot、README 或 components.md。CX-D4 两条改名和停用继续有效；停用 JSON 字段确定为 `retired: true`，不得改已完成训练的 `displayNameSnapshot`。

## 第 2a 步执行记录

### 最新状态：实现闸门 PASS，待审查（2026-10-19 r5 收尾）

1. **分类和依据**：沿用 D 类实现对齐，复用既有 `DS-CHIP` / `DS-EQUIPMENT-ICON` anatomy；依据已批准 CX-D4 / D9–D12 / D14 / D15，不新增设计或产品决定。本轮未改产品代码、目录数据、模型、工程设置、icons、Assets、Penpot、README 或 components.md；仅完成测试修复、运行闸门和提交既有草稿。未做人工视觉验证。
2. **影响范围**：初始 `feat/catalog-expansion@1a85142` 的 23 个 tracked 修改、3 个指定 untracked 项及 specs 两个草稿与交接完全一致，无 staged；两个 topic worktree 审计 PASS，全部草稿保留。`ios-swiftui-dev` 修测试编译，`mobile-reliability-tester` 执行测试闸门并修测试 fixture，主 agent 核对 specs、分组提交与整合；未另开审查 agent。`external-taxonomy-digest.md` 保持 untracked、不提交。
3. **设计决定**：批准规则保持不变：稳定 id 原位同步，Custom / Session-only 升级重名优先、内置动态隐藏，释放占用后恢复；已有目录提交前失败回滚并降级，保存后保护审计失败仍拦截；finish / abandon 与 claim 释放同事务、随后尽力同步；新增路径重新校验可选性。目录仍为新增 396 / 总数 542（1 retired，默认可见 541），13 器械都有动作，旧 146 id 保留。
4. **实施与检查**：测试编译 `build-for-testing` PASS（`DerivedData/CX2a/evidence/r5-build-for-testing{,-retry1,-retry2,-retry3}.log`）；备份测试改为不捕获 XCTest self 的静态 helper，并提供 `@MainActor` export helper。Unit 全量 PASS：498 tests、1 skipped、0 failures（`r5-unit-tests.log/.xcresult`）。Integration 首轮 185 tests / 1 failure：升级保留测试的 weightReps fixture 缺重量；失败单跑复现且结束阶段 wrapper 到 240 秒退出 142，保留 `r5-integration-failure-single.log` 和未完成的 `.xcresult` 目录（不是有效 result bundle）；第一次测试修复补 40 kg 后暴露全部目录 ID 期望遗漏该测试自建 Custom（`r5-integration-fixed-single.log/.xcresult`），第二次修复改为精确 543 条及完整 ID 集合，保留全部业务断言，单条 PASS（`r5-integration-fixed-single2.log/.xcresult`）。最终 Integration 全量 PASS：185 tests、0 skipped、0 failures（`r5-integration-tests-final.log/.xcresult`）；同条测试共修 2 次。每次测试前重启指定 EFE2D5A0 iPhone 17，单条 alarm240、全量 alarm1200；主 agent 人工查看日志，本轮未实施自动 300 秒停滞 watchdog，各次运行均在 300 秒内结束或被硬时限终止。命令和退出状态详见 `r5-runtime-status.md`。最终全仓 strict lint PASS（`r5-swift-format-lint-final.log`）；本轮未改产品代码，App Debug build 沿用 `r4-app-build-retry1.log` PASS。测试 agent 额外执行的 Release build / production test-hook exclusion 均 PASS（`r5-app-release-build.log`、`r5-production-test-hook-exclusion.log`），不替代指定四闸门。两个仓库 diff --check PASS；未跑 UITests、真机或 ResetStore。
5. **结果与提交**：四道实现闸门 PASS，交由 Claude 审查，L3 与 milestone 接受仍待进行；无新增 BLOCKED 或待决产品问题。产品分组提交：`81a0a72` 模型与映射、`e11d2e2` 目录数据与器械映射、`3f8531d` 同步与占用规则、`807629a` 新增路径校验、`76120d5` 测试与 fixture；specs 独立 topic 提交 `33805f9`（仅 `spec.md` / `data-model.md`，与实现核对一致）。本执行记录独立提交，提交号及最终状态见 `.handoff/subagent/2026-10-19-cprime-step2a-finish.md`。未 push、未合并 main。

入口与布局清单：动作库筛选 sheet → 可见 `FCFilterChip` → `FCAccessibilityID.exerciseLibraryEquipment(equipment)`（`Features/ExerciseLibrary/ExerciseLibraryView.swift:251`）→ 只改变筛选条件、器械 8 项变 13 项 → `filterSheet` 的 `FCBottomSheet` 内容区 → `VStack` → `FCFlowLayout` 负责内容宽度；未增加其他入口或控件。L3 待人工看：13 项小屏换行/滚动、两个改名动作、停用项不可见；**未做人工视觉验证**。

### 历史状态：BLOCKED（2026-10-19 resume4：Integration 编译连续失败，重试额度已用完）

1. **分类和依据**：D，按已批准目录和 CX-D9 / D10 / D12 / D14 / D15 修正实现，目标 anatomy 与样式不变；已阅读 `33-exercise-filter-sheet.png`、README §7.1 / 筛选规则和 `components.md` 的 `DS-CHIP` / `DS-EQUIPMENT-ICON`。只复用既有组件与图标，不修改 Penpot、README、components.md、icons 或 Assets；CX-D15 映射是本轮明确批准例外。
2. **影响范围**：初始 `feat/catalog-expansion@adfc8c6` 的 16 tracked 修改、3 指定 untracked 项与交接一致，无 staged；bootstrap 与 gate PASS。保留并完成既有代码、V6、测试和 fixture 草稿，digest 不提交。specs 唯一写入目标为独立 `feat/finecoach-catalog-cx2a` 的 `FineCoach/001-m1-a-core-session/{spec,data-model}.md`，没有写共享 main。实现由 `ios-swiftui-dev` 负责，`mobile-reliability-tester` 负责运行门禁，主 agent 整合与验收；未另开 privacy/security 审查。
3. **设计决定**：CX-D15 已独立提交 `6c49fee`。`postCommitProtectionAuditFailed` 保持 `catalogUnavailableMessage` 拦截，其他已回滚同步失败按 CX-D14 使用旧目录，首次安装无目录仍不可用；未改 `PersistenceWriter`。finish / abandon 与临时 claim 释放同 writer transaction，terminal retry / replay 同样释放；之后内置 claim reconcile 尽力执行，失败不影响训练结束，下次启动 reap / seed 补上。删除动作或分组、Custom 改名或归档释放占用后立即 reconcile；普通临时新建遇已有内置名称仍 conflict。备份 generation 验证并 reload 后立即同步。两条哈克机只改器械，名字和 id 不变；其他图标映射保持（既有 CX-D9 绳索映射草稿一起完成）。
4. **实施与检查**：build_candidates / write_catalog 最终各离线双跑，输出逐字节一致，`r4-determinism.json`；JSON 相对本轮初始只修改两条哈克机器械字段。固定 146 fixture 与 `96b385f` 原文件逐字节一致；全部旧 id 保留；XML 对比确认 V6 只新增 optional Bool isRetired default false（另有模型版本标识变化）。最终 strict lint PASS；App build 首轮 FAIL（缺 return），保留 `r4-app-build.log`，一次定向修复后 PASS（`r4-app-build-retry1.log`）。Integration 首轮因测试引用不存在的 activeRecoveryURL 编译 FAIL，retry1 因迁移测试隐式捕获 non-Sendable XCTest self 编译 FAIL，均为 0 tests；保留 `r4-integration-tests{,-retry1}.log/.xcresult`，分别定向修复后 retry2 仍编译 FAIL：`BackupRoundTripTests.swift:31–32` 的 `@MainActor` 测试调用 nonisolated async 实例 helper `seedLegacyCatalog` / `exportInventory`，Swift 6 报 `sending self risks causing data races`（`r4-integration-tests-retry2.log/.xcresult`）。三次均 0 tests executed；编译失败的两次重试已用完，按任务说明停止，未修复这最后一组诊断。Unit 未启动，0 tests；不能沿用 r3 Unit PASS 作为本轮结果。最后两轮测试修正后的全仓 strict lint 由实施子 agent 复跑 PASS（未另写 final2/final3 日志）；已落盘 `r4-swift-format-lint-final.log` 对应之前的全仓 PASS。未运行 UITests、ResetStore 或真机；未做人工视觉验证。
5. **结果**：BLOCKED，未完成第 2a 步。四道闸门为 lint PASS、App build PASS、Integration FAIL（编译失败 / 0 tests）、Unit NOT RUN（0 tests）；CX-D14 / D15 与新增路径校验已实施为草稿，但没有本轮 Integration / Unit runtime 验证，不能声明完成。除批准决定和本 BLOCKED 文档外，不提交代码、测试、数据或 specs；所有草稿保留。目录新增 **396 / 总数 542**（1 retired，无用户冲突或隐藏时可见 541）；146 旧 id 保持。器械条数：杠铃75、哑铃88、固定器械76、史密斯机23、绳索59、哈克机2、壶铃4、徒手118、悍马机24、弹力带53、悬挂带7、单杠9、其他4。28 个旧条目变化为21绳索 + 2单杠 + 2哈克机 + 2改名 + 1停用。所有日志 / xcresult 置于 `DerivedData/CX2a/evidence/r4-*`；最终外部审查和 L3 仍待进行。

入口与布局清单：动作库筛选 sheet → 可见 `FCFilterChip` → `FCAccessibilityID.exerciseLibraryEquipment(equipment)`（`Features/ExerciseLibrary/ExerciseLibraryView.swift:251`）→ 只改变筛选条件、器械 8 项变 13 项 → `filterSheet` 的 `FCBottomSheet` 内容区 → `VStack` → `FCFlowLayout` 负责内容宽度；未增加其他入口或控件。L3 待人工看：13 项小屏换行/滚动、两个改名动作、停用项不可见；**未做人工视觉验证**。这是 2a 实现门禁记录，不代替人工审查、视觉或 milestone 接受。

### 历史状态：BLOCKED（2026-10-19 resume3：提交后保护审计失败边界待裁决）

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
