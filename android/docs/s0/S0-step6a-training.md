# S0 step6a：训练页最终执行记录

状态：**设计比对 PASS：52项，48通过、4项不可观测（矢量内部）、UI偏差0、缺失0。第7轮定向自测254/0，s0Conformance/G3/G4分别1/0、38/0、12/0；宿主原861/6仍是最近一次完整门禁记录，修后未重跑完整门禁。** 负责人视觉走查和截图基线批准仍PENDING。本轮不提交、不切分支、不推送。

## 本轮优先记录与边界

工作树为 `FineCoach/.claude/worktrees/android-s0-core-training`，branch `feat/android-s0-core-training`，产品基线 `ab44d0d`。第7轮启动时21个tracked modifications（含宿主交付的PNG）和2个untracked files，均为既有未完工作，全部保留。没有staged content；单写者，无subagent。此前同worktree/branch已通过ig-worktree-gate，未改变分支或runtime links。

宿主在沙箱外执行的 `.handoff/logs/2026-11-10-host-s0-step6a-r2.log`：861 tests / 6 failures；s0G1/G2/G3/G4/G6/Room和s0Conformance均通过。6个失败是S1CatalogStateTests的5个旧行高断言，以及ActiveSessionEntryLayoutTests在重排用例teardown中的Compose RecomposeScope空指针。此处保留宿主FAIL证据，不用定向测试代替整体复验。

第7轮允许的改动限于测试合同、`components.md` §8的一处Android说明及执行文档。产品页面、比较器、容差、PNG和资产来源记录不再修改。两个疑似偶发测试类已分别隔离运行3次；ActiveSession有一次复现，已修测试清理并再隔离3次，结果见下表。52层最终三联图本轮仅查看一次，结论已落盘；查看后未改代码。

## S1-D34～D39落实

| 决策 | 最终落实与证据 |
|---|---|
| S1-D34 | 组行「已完成」保留callout15/400/text.secondary；宿主已修Penpot与导出，path13为47×18。无designOverride，不排除该项，最终正常PASS |
| S1-D35 | 删除统计；训练页saved不组合组件、不占位；saving/failed保持页头下方显示，失败说明和重试可见，失败不能结束训练。DS-SAVE-STATUS和catalog三态不改。SessionRecoveryEntryLayoutTests覆盖真实保存挂起、可访问名称、失败、重试和saved无节点 |
| S1-D36 | Android自适应图标决定不属于本训练页任务；未改图标资产、主题或分发配置 |
| S1-D37 | 文字仅比较x、w、垂直中心、原文、token，Δh只报告；容差仍±2dp含边界，原S1-D30 top/bottom/viewport规则不变。仅7/1、33/1、45/1、46/1允许矢量内部不可观测，须父图标几何通过、同名来源SVG/drawable及hash有效；前提不符仍失败。ConformanceComparisonTests保留原10例并新增4例，不引入插入补偿、origin参数或宽松容差 |
| S1-D38 | FcSetRow可见步距38dp；真实44dp点击区不参与布局高度、以图形为中心扩展，允许相邻行上下各3dp重叠。撤销与同行文字居中。S1ComponentTests用真实touch逐个命中相邻两行确认、编辑、撤销，证明每次仅触发本行callback；disabled不能写入。Android映射补记在components.md §8，iOS anatomy不改 |
| S1-D39 | 删除动作头可见选中✓及完成提示，保留selected语义；ActiveSessionEntryLayoutTests验证selected与子节点不增加、完成标记不存在；ComponentCatalogTests核实已退役消费者不再使用图标，仍校验资产hash/来源，固定6例不变 |

负责人已批准以components.md为准回填页头。最新layers.json逐字节来自宿主 `.handoff/design/P0-a2-training.layers.json`，SHA-256 `db837de48a94fb7d12df081e181a4bfc3ca4477aeb95d6c1d016985714355a99`，52层：path1标题x32、新增path47返回字形x16。map中path47为真实Text节点`active-session-back-glyph`，不是44dp的`active-session-back` overlay。两个字形用实际TextLayoutResult检验基线一致。当前PNG由宿主提供且本轮未改，尚待负责人再导出包含返回字形/标题新位置的版本；页头raw像素差是已知PNG更新待办，不掩盖机器几何偏差。

## 根因 → 修法 → 修后数字

分类D（implementation drift repair），目标设计不由代码反向修改；初始51项为通过1、偏差40、missing10。最终新增获批页头字形后52项为48通过、4矢量内部不可观测、偏差/缺失/裁剪均0。

| 根因/图层 | 修法与文件 | 最终数字 |
|---|---|---|
| 页头1–3、47：标题x偏44、学员弹性框w偏167.5、时钟颜色/位置 | SessionChrome.kt：16dp前导slot、标题x32；返回真实glyph与44dp点击overlay分开、基线对齐；学员Text与Spacer分开；计时action.primary；FcSymbol可选visualTag保留真实TextLayoutResult且仍对无障碍隐藏装饰字形 | 4项PASS。path1 Δx0/Δw−2/中心+1.5；path47 Δx0/Δw−1.5/中心+2，Δh6仅报告 |
| 动作头/参考4、8、34、35：额外标记挤压、弹性标题框 | SessionChrome.kt：移除S1-D39标记，仅保留selected；自然宽标题/参考、真实器材Icon；点击区不推高内容流 | 4项PASS；两个器材父group7/33也PASS |
| 统计与保存状态使默认内容整体下移 | ActiveSessionScreen.kt、SaveStatusView.kt按S1-D35移除统计并在saved时不组合；失败和saving原路径保留 | 默认无这两个节点，不留间距；无registeredInserts |
| 组行9–18、45/46：52/60步距与44触控框混用，撤销偏下 | FcSetRow.kt：38dp可见节奏，独立44dp点击区、真实22圆圈/20铅笔；撤销/状态与数值同行；SessionSwipeRow在闭合时保留越出可见行的触控区 | 所有可观测组行层PASS；相邻行六次真实点击均只触发本行 |
| 组行数值无必要缩小 | 默认autosize的13.6起点/0.25步进不覆盖17sp上限；先尝试批准的17sp，确实放不下再沿用0.8下限的原fallback | 120kg×8自然宽从81.5dp回到86dp，x/w/中心PASS；窄列缩放及完整字形另有断言 |
| 122.5真实裁切 | FcControls.kt：输入框自然宽127px，内部水平滚动段落360px，原Center使字形x117～244超出视口；改为段落Start，外层slot继续居中，字形回到x0～127完整可见。没有固定行高 | TrainingInputLayoutTests及真实TrainingConformanceTests检查所有字形bounding boxes位于可见区域；重量、次数、左右重量、距离、速度、阻力、时长均覆盖 |
| 文字行盒Δh2.5～6 | 撤销FcTextMetrics.kt及全部fcSingleLine调用，恢复main的token排版；S1-D37按文字中心比较，不强压行盒 | FcTextMetrics.kt不保留；全局fontSize/lineHeight/token不改；文字层全PASS |
| stepper/提示/确认19–31：整列bounds误当文字、±语义和间距 | FcRows.kt保留label列，真实标签自然宽；FcStepperField输入/触控区分开；±真实Canvas绘制原20dp Material viewport，使用画稿14×26 advance frame，不拉伸资产；label/hint/录入区用既有token定位 | 13项PASS；图形节点有真实墨迹且不在边界裁切，44dp按钮保留 |
| 矢量内部path：7/1、33/1、45/1、46/1 | S1-D37封闭条件验证，map标记真实矢量内部，来源hash不改 | 正好4项不可观测，不计PASS或偏差；父group均PASS |
| 分割线/第二卡/添加入口32–38 | 真实divider tag；动作块、分隔与按钮间距按画稿，不删添加动作/新建分区 | 所有可观测项PASS |
| 底部5/6、39–44：结束按钮底距0对32、休息条52对96 | FcButton/页面labelModifier与RestTimerView定位；底部space.8、休息条后space.3、链接间距space.4；数据操作不变 | 8项PASS，结束按钮底距32、休息条底距96；背景path0 PASS |

四个内部path的特殊处理仅来自S1-D37，不是PASS；path1和path47正常参与比对，已无待豁免几何项。比较器相对ab44d0d的逻辑变化仅为上述文字与矢量内部两项；没有删层、改fixture内容、放宽容差或新增坐标补偿。

## Entry / layout map

| 页面 → 控件/节点 | testTag | 改数据 | 宽度/触控所有者与证据 |
|---|---|---|---|
| 训练中 → 返回 | active-session-back；可见字形active-session-back-glyph | 否 | 44dp overlay不参与布局；glyph在16dp slot，标题x32；ActiveSessionEntryLayoutTests验证真实字形、独立点击区及绝对基线相等 |
| 训练中 → 动作头 | session-exercise-{id} | 否，仅打开录入 | 满宽动作头；selected语义保留、两个可见标记删除 |
| 训练中 → 确认/编辑/撤销 | session-set-{id}-confirm / -edit / -undo | 确认/撤销写入；编辑只打开 | FcSetRow.fillMaxWidth，38dp节奏；44dp点击区外扩。S1ComponentTests.neighboringCompactRowsKeepIndependentRealTouchTargets逐次真实touch，六个callback各自唯一命中 |
| 训练中 → 数字/± | set-weight-input / -input-touch / -minus / -plus；set-reps及左右同构 | 仅输入草稿 | FcLabelValueRow值列、满宽input-touch≥44；TextField自然宽、空值可见。TrainingInputLayoutTests检查字形边界；真实fixture先点plus再验证122.5布局 |
| 训练中 → 确认/保存/取消 | set-save / set-cancel | 确认/保存写入；取消不写 | set-editor-actions满宽，FcButton.weight(1f)，取消可见 |
| 训练中 → 添加动作/新建分区 | session-add-exercise / session-add-section | 选取/保存才写 | 满宽Row中的两个FcLinkButton，触控≥44 |
| 训练中 → −15/+15/跳过/关闭 | rest-minus / rest-plus / rest-skip / rest-close | 仅内存休息 | 满宽休息条内可见链接按钮；底距96，退出/键盘规则不改 |
| 训练中 → 结束训练 | session-finish | 打开结束流程 | 满宽FcButton，底部space.8；保存失败仍禁用 |
| 训练中 → 保存中/失败/重试 | save-status-saving / save-status-failed / save-retry | 重试执行原命令 | 非saved才组合，错误/重试满宽；saved无节点、无高度或额外间距 |
| 训练中 → 动作/组删除、移入分区 | session-exercise-delete / session-set-delete / session-exercise-move | 是 | 原可见左滑入口，未改为仅长按 |

## 已知两端差异与影响页面

- iOS常驻显示已保存和统计；Android按S1-D35不显示统计，saved不组合，仅saving/failed可见。DS-SAVE-STATUS/catalog三态和G2计数不改。
- iOS组行行高≥44；Android按S1-D38可见步距38，44dp点击区独立外扩，允许上下各3dp重叠。§4 iOS anatomy与token未改。
- 原生Material Symbols按AD-01保留；器材SVG与glyph字体来源不变。4个内部path不具备独立Compose layout，已按来源证据单列。
- 当前Android生产源码中，FcSetRow的唯一调用者是ActiveSessionScreen；历史详情/总结使用自身snapshot呈现，无FcSetRow调用（静态检索结果）。若以后复用该组件，会统一采用38dp合同，不另留52/44行高。HistoryEntryLayoutTests仍按要求回归。
- FcLabelValueRow/默认FcSymbol涉及学员、动作、课包、历史等页面。visualTag只有训练页返回字形使用，默认装饰语义/渲染不变；labelModifier默认不改其他页面。列入对应EntryLayoutTests及组件合同验证，不声称额外页面经人工视觉验收。

## 第7轮处置与验证台账

1. **5个catalog合同失败已修。** `S1CatalogStateTests`中draft/pending/completed/disabled/undo统一精确断言38dp；同处确认区≥44×44断言原样保留，5态均通过。检索S1ComponentTests、S1ComponentReviewTests、HistoryEntryLayoutTests、ComponentContractTests及其余test源码，未发现其他组行52/44布局高度旧假设；剩余52dp属于按钮，44dp属于点击区/其他组件，未改。components.md仅§8 DS-SET-ROW行补Android说明；G2固定27/66/6/5不变。
2. **ActiveSession NPE复现并修测试清理。** 修前第2次在`recentConfirmUndoUsesRowStatus`的`@After close()`清空`setContent { }`复现，而非重排用例；不能归为“三次全绿的已知偶发”。此清理把已有ComposeView更新为空内容，会在teardown调度一次新重组。改为`runOnIdle`等待已有工作完成、再对真实`AbstractComposeView.disposeComposition()`，reopen共用同一路径，随后仍等待SQLite事务完成再关库。没有捕获/忽略异常、删除用例或修改产品。修后隔离3次全绿，最终集合再通过；现有证据定位到清理时序，未发现SessionSwipeRow持续重组或产品重排缺陷，也不据此宣称框架内部成因已完全证实。
3. **ExerciseTemplate未复现。** 三次各33/0、无skip，按指令登记为已知偶发idle超时，本轮不改该类或产品。其用例同时在最终集合再通过。

隔离结果（日志均在产品`.handoff/logs/`，以下为完整文件名）：

| 类/阶段 | 第1次 | 第2次 | 第3次 |
|---|---|---|---|
| ActiveSession修前 | 20/0；agent-test-android-s0-core-training-20261110-173745.log | 20/1；agent-test-android-s0-core-training-20261110-173800.log；teardown同一NPE | 20/0；agent-test-android-s0-core-training-20261110-173810.log |
| ExerciseTemplate | 33/0；agent-test-android-s0-core-training-20261110-173819.log | 33/0；agent-test-android-s0-core-training-20261110-173833.log | 33/0；agent-test-android-s0-core-training-20261110-173845.log |
| ActiveSession修后 | 20/0；agent-test-android-s0-core-training-20261110-174114.log | 20/0；agent-test-android-s0-core-training-20261110-174127.log | 20/0；agent-test-android-s0-core-training-20261110-174138.log |

最终类集合日志：`agent-test-android-s0-core-training-20261110-174219.log`。每项失败/error/skip均0，共254例；指定13类235例，原提示词补充的3类19例。

| 自测类 | 用例数 | 失败数 |
|---|---:|---:|
| S1CatalogStateTests | 35 | 0 |
| S1ComponentTests | 12 | 0 |
| S1ComponentReviewTests | 4 | 0 |
| ComponentContractTests | 27 | 0 |
| ComponentCatalogStateTests | 66 | 0 |
| ComponentCatalogTests | 6 | 0 |
| HistoryEntryLayoutTests | 9 | 0 |
| ActiveSessionEntryLayoutTests | 20 | 0 |
| ExerciseTemplateEntryLayoutTests | 33 | 0 |
| SessionRecoveryEntryLayoutTests | 7 | 0 |
| FinishSessionEntryLayoutTests | 9 | 0 |
| TrainingInputLayoutTests | 1 | 0 |
| TokenParityTests | 6 | 0 |
| RestNotificationEntryLayoutTests | 1 | 0 |
| ConformanceComparisonTests | 14 | 0 |
| ConformanceVisibilityTests | 4 | 0 |

| 任务 | 用例/失败 | 退出码 | 日志（.handoff/logs/） |
|---|---:|---:|---|
| s0Conformance / TrainingConformanceTests | 1/0 | 0 | agent-test-android-s0-core-training-20261110-174242.log |
| s0G3 / DesignValueScanTests | 38/0 | 0 | agent-test-android-s0-core-training-20261110-174250.log |
| s0G4 / EntryLayoutHarnessTests | 12/0 | 0 | agent-test-android-s0-core-training-20261110-174303.log |

任务均无error/skip。conformance JSON：total52/passed48/unobservableVectorInternal4/uiDeviations0/missing0/invisible0，容差2dp；Android render SHA-256 `72f074c77644636571b2fcecee58c4584bf78065f03a3dc9df83df5105a71265`，两次确定性render一致。报告在`android/app/build/outputs/conformance/P0-a2-training.report.md`与同名JSON。

### 一次性三联图清单（本轮最终产物，仅一次）

查看`android/app/build/outputs/conformance/P0-a2-training.triptych.png`，即上述174242任务产物。此为模型一次性清单审阅，不代替负责人视觉验收，不将raw pixel diff当机器几何PASS。原PNG含iOS顶部52pt空白，Android内容自顶开始，所有top锚点依既有S1-D30统一对齐；因此未对齐的raw差分有整段错位，不能称像素一致（differentPixelRatio=0.24257959654879085）。未据此修改产品、map或比较器。

| 项目 | 观察结论 |
|---|---|
| 页头 | Android可见返回‹、标题、学员与计时；新52层几何通过。当前PNG仍无‹且标题x16，负责人已批准x32/新增‹，等待再导出。顶部52pt平台起点差按S1-D30登记 |
| 动作卡 | 深蹲名称、器材及上次参考清楚；没有选中✓/全部完成额外图标。与第二卡阅读顺序一致 |
| 已完成组行 | 两行完整，圆圈/✓/标题/重量次数/状态可见，38dp节奏；原生器材/铅笔与设计轮廓仍有AD-01平台差异，4个内部path已单列 |
| 撤销 | 与第2组数值同行居中，未再明显下坠；字重/字形有平台字体外观差异，机器中心/token通过 |
| 录入区 | 重量122.5全数可见、没有小数尾部裁切；次数8完整，两端±及胶囊清楚。其他数值模式由真实TextLayoutResult测试覆盖，不声称截图展示了全部模式 |
| 提示 | 步进与可直接输入提示完整，在录入区下方，颜色为次要文字色 |
| 确认按钮 | 满宽、文字居中可见，底部分割线清楚 |
| 第二个动作卡 | 卧推名称、器材和上次参考完整，分割线清楚；不添加画稿外状态 |
| 添加动作/新建分区 | 两个可见入口均保留，无仅长按替代；与第二卡之间留白存在 |
| 休息条 | 组间休息、1:45、−15秒/+15秒/跳过均可读；底部固定区与结束按钮分离，底距96dp由报告确认 |
| 结束训练 | 满宽按钮完整、底部留白保留；底距32dp由报告确认 |
| 背景 | 页面背景一致、主体留白存在；未发现新遮挡。无统计/已保存占位；raw差分中的红色大面积重影来自顶部起点/旧页头及字形差，不掩盖报告数值 |

查看后没有外观修码。遗留：负责人页头PNG重新导出与最终视觉/基线批准、宿主修后完整门禁复验；本轮指定范围无剩余失败，不声称旧宿主861/6已变为861/0。

## 改动文件清单（相对ab44d0d，累计step6a）

- 产品designsystem：FcControls.kt、FcRows.kt、FcSetRow.kt；FcTextMetrics.kt已撤回，不保留。
- 产品features/session：ActiveSessionScreen.kt、SessionChrome.kt、SessionSwipeRow.kt、SaveStatusView.kt、SetEditor.kt、RestTimerView.kt。本轮不再动这些文件。
- 验证：ActiveSessionEntryLayoutTests.kt、SessionRecoveryEntryLayoutTests.kt、S1ComponentTests.kt、ComponentCatalogTests.kt、ConformanceComparison.kt、ConformanceComparisonTests.kt、TrainingConformanceTests.kt、新增TrainingInputLayoutTests.kt；本轮另对齐S1CatalogStateTests.kt。
- 映射/记录：android/design-assets/conformance/P0-a2-training.layers.json、.map.json、README.md；本文件；android/docs/s1/implementation-map.md；design/design-system/components.md仅§8一句Android合同说明。
- 用户/宿主所有的design/experience-p0/screens/P0-a2-training.png保留，不由agent改写。iOS、冻结domain/schema/repository/port、S1Routes.kt、资产来源文件、截图baseline、G2固定计数均未改。

## 已保留的失败历史

初始环境因沙箱外Robolectric lock不可写而失败，之后仅用JVM临时home复用依赖缓存；Gradle仍可能输出Kotlin daemon目录权限诊断，不隐去。初始有效conformance51/1/40偏差/10missing；中间阶段的偏差和重量裁切已在后续实际修复，旧失败清单已由最终根因表替代。曾临时使用的designOverride/registeredInserts已完全撤掉。第5轮末为51/46通过/4不可观测/1标题待回填；第6轮宿主新52层后为52/48/4/0。

本轮沿用agent-test.sh，不直接运行Gradle；没有skip、减少G2计数或放宽比较容差。git diff --check通过。第7轮新增改动仅为S1CatalogStateTests.kt、ActiveSessionEntryLayoutTests.kt的清理、components.md §8一句说明及三份记录（本文件、S1 implementation-map、conformance README）；产品页面、比较器、导出JSON/map和PNG均未再改。
