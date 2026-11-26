# S3 implementation map

每个新的用户可见交互一行（`design/design-system/components.md` §1.4）。所有列都必须指向真实代码；会改数据的入口不能只靠长按。

| screen | visible control | testTag | mutation | width owner | test |
|---|---|---|---|---|---|
| 训练中 | 确认新组 | set-save | Room 新建并确认 TrainingSet；重算 holder | set-editor-actions Row + FcButton.weight(1f) | S3SessionGainsEntryLayoutTests.confirmEditDeleteRestoreAndUndoRecomputeWithoutExtraFeedbackOrHistoryReads |
| 训练中 | 待完成组确认圆圈 | session-set-$id-confirm | Room 确认 TrainingSet | FcSetRow.fillMaxWidth；圆圈 44 touch | S3SessionGainsEntryLayoutTests.pendingConfirmationUsesOneHapticAndFailureUsesNone |
| 训练中 | 铅笔 → 保存 | session-set-$id-edit / set-save | Room 编辑 TrainingSet；重算，不发确认事件 | FcSetRow.fillMaxWidth；编辑 actions Row | S3SessionGainsEntryLayoutTests.confirmEditDeleteRestoreAndUndoRecomputeWithoutExtraFeedbackOrHistoryReads |
| 训练中 | swipe 后可见删除按钮 | session-set-delete | Room 删除 TrainingSet；重算 | SessionSwipeRow + FcSetRow.fillMaxWidth | S3SessionGainsEntryLayoutTests.confirmEditDeleteRestoreAndUndoRecomputeWithoutExtraFeedbackOrHistoryReads |
| 训练中 | 删除后的撤销按钮 | session-deleted-action | Room 恢复 TrainingSet；重算 | FcUndoRow.fillMaxWidth | S3SessionGainsEntryLayoutTests.confirmEditDeleteRestoreAndUndoRecomputeWithoutExtraFeedbackOrHistoryReads |
| 训练中 | 刚确认组撤销按钮 | session-set-$id-undo | Room 删除刚确认组；重算 | FcSetRow.fillMaxWidth | S3SessionGainsEntryLayoutTests.confirmEditDeleteRestoreAndUndoRecomputeWithoutExtraFeedbackOrHistoryReads |
| 总结页 | 只读本节收获 | summary-gains | 无 | summary-content → SessionGainsSection.fillMaxWidth | S3SessionGainsEntryLayoutTests.summaryHistoryAndReopenAgreeAndDoNotRewriteNotes |
| 历史详情 | 只读本节收获 | history-gains | 无 | history-record-card → SessionGainsSection.fillMaxWidth | S3SessionGainsEntryLayoutTests.summaryHistoryAndReopenAgreeAndDoNotRewriteNotes |
| 学员详情 | 训练趋势 | studentDetail.trends | 无，进入趋势页 | FcActionRow.fillMaxWidth | StudentRecordEntryLayoutTests.trendsEntryOpensTheTrendPageAtFullWidth；S3NavigationEntryLayoutTests.realStudentDetailOpensLoadedTrendsDestination |
| 学员详情 | 身体数据 | studentDetail.body | 无，进入身体数据 | FcActionRow.fillMaxWidth | StudentRecordEntryLayoutTests.bodyEntryOpensTheBodyPageAtFullWidth；S3NavigationEntryLayoutTests.realStudentDetailOpensBodyAndMetricUnits |
| 训练趋势 | 动作 | trends-exercise | 无，只改本页所选动作 | trends-exercise 与 platform-content 同宽 | TrendsEntryLayoutTests.exercisePickerAndMetricAreVisibleAndDoNotWriteHistory |
| 训练趋势 | 指标分段 | trends-metric-$index | 无，只改本页指标 | FcSegmentedSwitch.fillMaxWidth | TrendsEntryLayoutTests.exercisePickerAndMetricAreVisibleAndDoNotWriteHistory |
| 训练历史 | 选择 / 完成 | history-list-trailing | 无，进入或退出选择模式 | FcPageHeader.fillMaxWidth | HistoryCompareEntryLayoutTests.visibleSelectionComparesMatchingFocusAndExplainsAMismatch；S3NavigationEntryLayoutTests.realStudentHistoryOpensComparisonFromVisibleSelection |
| 训练历史 | 选择这节课 | history-compare-pick-$sessionID | 无，比较不写 Room | 选择按钮 FcButton.fillMaxWidth；比较面板与 history-results 同宽 | HistoryCompareEntryLayoutTests.visibleSelectionComparesMatchingFocusAndExplainsAMismatch；S3NavigationEntryLayoutTests.realStudentHistoryOpensComparisonFromVisibleSelection |
| 身体数据 | 打开指标 | body-open-$metricId | 无，进入该指标 | feature BodyMetricValueRow.fillMaxWidth | BodyDataEntryLayoutTests.openMetricAndSaveCustomMetricFromVisibleControls |
| 身体数据 | 新建自定义指标 | body-custom | 无，打开自定义指标面板 | FcLinkButton；body-footer 与 platform-content 同宽 | BodyDataEntryLayoutTests.openMetricAndSaveCustomMetricFromVisibleControls |
| 身体数据 | 保存自定义指标 | body-custom-save | Room 新建自定义指标 | body-custom-sheet 内 FcButton.fillMaxWidth | BodyDataEntryLayoutTests.openMetricAndSaveCustomMetricFromVisibleControls |
| 身体数据 | 保存 | body-save | Room：同一学员、同一指标、同一本地自然日 upsert；内置单位先换成 kg/cm | body-save 与 platform-content 同宽 | BodyDataEntryLayoutTests.sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage；displayedUnitIsConvertedBeforeItIsStored |
| 身体数据 | 删除 | body-delete-$id，确认 body-delete-accept / 取消 body-delete-cancel | 确认后 Room 删除并重算趋势；取消不删 | 删除按钮在记录行内 | BodyDataEntryLayoutTests.sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage |
| 身体数据 | 单位 | body-unit-kg / body-unit-lb（或 cm / in） | 原子保存教练全局显示偏好，不改测量值或单位 | FcFilterChip | BodyDataEntryLayoutTests.sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage；BodyDataUnitPreferenceTests.choicesSurviveLoadOpenMetricStudentAndStoreReconstruction |
| 训练趋势 / 身体趋势 | 图表曲线：按住 / 水平拖动查看 | conformance:Trend chart (M1 TrendsView)；trend-bubble | 否，仅临时选点，松手/取消清理 | FcTrendChart.fillMaxSize；气泡在图表宽度内夹紧 | TrendChartInteractionTests（hold / horizontalDrag / verticalGesture） |
| 今日 | 提示行 | insights.row.$snoozeKey | 无，进入课包、预填安排或该动作趋势 | 行 Column.fillMaxWidth，与 insight-parent 同宽 | InsightEntryLayoutTests.rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds；threeDestinationsAndStudentDetailOmitsTheName |
| 今日 | 全部 · N | today.insights.all | 无，进入完整列表 | FcGroupEntryRow.fillMaxWidth | InsightEntryLayoutTests.allEntryRendersFullListAndRowOpensPrefilledAppointment；S3NavigationEntryLayoutTests.todayFullListOpensPackageAndPrefilledAppointmentWithoutCreatingOne |
| 今日 | 左滑暂不提醒 | insights.snooze.$snoozeKey；TalkBack 自定义操作「暂不提醒」 | 是，InsightLocalStateStore 写入不透明 key 和截止日 | 行 Column.fillMaxWidth | InsightEntryLayoutTests.rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds |
| 今日 | 撤销 | insights.undo.$snoozeKey-action | 是，删掉这条暂不提醒 | FcUndoRow.fillMaxWidth | InsightEntryLayoutTests.rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds |
| 今日 | 首次轻推 | insights.nudge.$snoozeKey（装饰胶囊对无障碍隐藏） | 是，每台设备把 firstNudgePlayed 写成 true；关闭动画时不写 | 行 Column.fillMaxWidth | InsightEntryLayoutTests.nudgePlaysOnceAndIsSkippedWhenMotionIsOff |
| 完整列表 | 分组提示行 | insights.row.$snoozeKey | 无，与今日同一条跳转 | insights-list-content Column.fillMaxWidth | InsightEntryLayoutTests.allEntryRendersFullListAndRowOpensPrefilledAppointment；S3NavigationEntryLayoutTests.todayFullListOpensPackageAndPrefilledAppointmentWithoutCreatingOne |
| 学员详情 | 提示行 | insights.row.$snoozeKey | 无，进入该动作趋势；主文字不带学员名 | studentDetail.insights Column.fillMaxWidth | InsightEntryLayoutTests.threeDestinationsAndStudentDetailOmitsTheName；S3NavigationEntryLayoutTests.todayStagnantInsightOpensTheExerciseTrendsDestination |
| 学员详情 | 下一节课 | studentDetail.nextClass | 无；有课时打开与今日相同的课程操作，没有课时去预填安排 | StudentOverviewRow 与 platform-content 同宽 | InsightEntryLayoutTests.nextClassRowFillsWidthAndOpensTheScheduledClass |

## R2 执行记录（2026-11-21）

1. 分类：D；修复已批准 E-a1/E-a2/E-b/E-d 行语义与 4 秒撤销行为，复用 DS-SECTION、DS-UNDO-ROW；不增 token 或组件。
2. 范围：InsightBoard/Copy/Rows、InsightUseCases、入口测试及两张核心屏 mapping；比较器按 S3-D17 传递画板高度。
3. 保留 / 移除：保留原行结构、token、左滑与路由；移除 load 清空 pending、主线程文件读取、TalkBack 内部 phase、断言整包 JSON；新增剩余撤销时间及安全失败报告。
4. 检查：入口测试 `allEntryRendersFullListAndRowOpensPrefilledAppointment` 真实渲染完整列表并点击行到预填新建安排；行宽与各自容器相等，Room 安排数不变。其余场景见 T040。
5. 结果：学员详情严格全绿；今日「全部」行剩画板项，Phase 5 未完成；未在设备上验证，也未进行负责人视觉验收。完整门禁见 T045。

## Phase 5 R3 执行记录（2026-11-21，S3-D19）

1. 分类：D；保持批准画板和组件结构，修复比较视口诊断与证据文档，不新增设计。
2. 范围：ConformanceComparison 的 visibility 读取 board.h；入口测试 StateDescription 检查真实提示行；P7 左滑说明、README 和 T040–T045。
3. 保留 / 移除：保留已锁屏结果与例外；移除 visibility 残留 844 硬编码、README 对其他 phase 的覆盖和 P7 证明存储的过度表述。
4. 检查：完整单测 1262/0/0/0；入口 9/0，比较器 31/0，隐私规则 1/0；今日 S3 PASS 46/53 层（AD-01 7），学员详情 PASS 61/61 层，FAIL/MISSING/outside 0；详见 T045 R3。
5. 结果：S3-D19 宿主最终门禁与 dsh 独立复核 PASS，已合入本地 main；核心屏负责人视觉批准仍留给 T052。

## Phase 6 执行记录（2026-11-21）

1. 分类：D；按 S3-D20 对齐单位记忆行为，`06-body-data.png` 与 DS-CHIP / DS-LIST-ROW 的 anatomy、tokens 不变。
2. 范围：复用 BodyDataScreen 控件，BodyDataState 与本地单位偏好存储；无新增入口，沿用上表「单位」行。
3. 保留 / 移除：保留 kg/cm canonical 存储与百分比/自定义行为；移除每次 load/open 重置显示单位，改为教练全局、weight/length 分开、跨重启记忆。
4. 检查：BodyDataUnitPreferenceTests 验证单位、同日保存、只改显示、跨指标/学员/存储重建与失败回传；现有 BodyDataEntryLayoutTests 验证可见入口和宽度；结果见 T053。
5. 结果：定向 27/0/0/0；完整单测和所有要求门禁结果见 T053；无新设计或基线审批，T051/T052 PENDING。

## Phase 6 R4 执行记录（2026-11-25，S3-D21）

1. 分类：D；恢复已批准 S3 入口的实际路由行为；批准画板、anatomy、组件、tokens 均不变。
2. 范围：S1Navigator 补 STUDENT_TRENDS/BODY、INSIGHTS 与两条参数直达；S1Routes 提供 typed helper，InsightRoutes 委托复用；debug seed v6 改为五位页面专人。
3. 保留 / 移除：保留 UUID/日期校验、冻结路由常量与全部原 S1/S2 业务数据；移除导航静默无动作和对原同名学员的 S3 overlay；不改界面样式或基线。
4. 检查：S3NavigationEntryLayoutTests 用真实 S1App + Room 测可见入口、目的地实际内容及预填不创建安排；旧页面宽度断言仍保留；DebugSeedTests 按专人验证领域结果及原记录不变；结果与日志见 T053 R4。
5. 结果：修复前 4 项中 3 项导航缺失，修复后真实导航 5/0、ScopeBoundaryTests 20/0；seed 库存两轮同错后停止，完整单测 1278/9/0/0（全部为 seed 阻塞）；G3/G4、三屏 conformance、P7 通过，见 T053 R4；宿主重新安装与负责人复查 PENDING。

## Phase 6 R6 身体数据执行记录（S3-D22）

1. 分类：D；目标 `06-body-data.png`、DS-LIST-ROW anatomy 不变，修复实现偏离。
2. Anatomy：feature-owned 三列行，名称 callout/secondary、值 numeralLarge、单位 caption/secondary；first baseline 对齐，最小 row 高，space3 垂直内边距，尾部分隔线；基本/围度/自定义分组，姓名在页头下；固定底栏占满 content 宽度。
3. 保留 / 移除：保留整行打开、Room canonical 值、全局单位偏好；移除 subtitle 双行和末尾整宽自定义按钮；统一列表/详情/图标注显示精度，无共享组件或 token 新增。
4. 入口布局：`body-open-*` → 指标详情；`body-custom` → sheet → Room 自定义定义；`body-unit-*` → durable 全局偏好 → `body-unit-summary`；`body-footer` 宽度归 platform-content；由 BodyDataEntryLayoutTests 证明。
5. 检查与结果：完整 1283/0/0/0、G3 42/0、G4 12/0、P7 28/0、三屏 conformance 各 1/0，diff-check PASS，日志见 T032 / T053 R6；R7 已裁决底栏左侧按 iOS 只读，入口测试验证无 OnClick。

## Phase 6 R7 执行记录（S3-D22 / S3-D23）

1. 分类与依据：B，负责人已批准的密集态/按住查看及青绿；原 D 类移植条目扩展，Penpot 三板及 PNG 见 components.md anatomy、T002 哈希。
2. 范围：复用 FcTrendChart，训练/身体均接入精确日期/decimal 样本；tokens 仅新增 chart.line，尺寸全部复用既有 token，无近似替代。
3. 决策 / 保留移除：≤8 点布局与日期例外保留；>8 点移除逐点圆；查看态临时显示参考线/圈/气泡并隐藏最大值标签，松手清理，不写数据；R6 单位摘要已裁决只读并补无 OnClick 断言。
4. 实现与检查：TrendChartInteractionTests 5/0；TokenParity/Contrast/身体入口 27/0；完整 1289/1/0/0（唯一为趋势门禁），今日/详情各 1/0，P7 28/0，G3 42/0，G4 12/0；入口/布局 map 已加查看行。
5. 结果：BLOCKED，当前趋势透明层无法从旧未标 fill 的 base-background 得到背景，完整与定向连续同错后停止；此前末尾面积层还遮挡六点的颜色观测。metadata 顺序/背景/8-bit alpha 提案未应用，待调度者裁决；不改比较器/容差/基线。独立复核与 T052 PENDING，详情见 T053 R7。

- R8（2026-11-26，S3-D24）：仅按 Penpot 实际结构同步核心 PNG 与 layers/map（白底、面积 11/2、折线 11/3、七圆 11/4–11/10、有效 alpha 20/255）；trends 47 层 / PASS 45 / OWNER_EXCEPTION 2 / UNOBSERVABLE/FAIL/MISSING 0，完整 1289/0/0/0，全部指定专项门禁 PASS；代码、比较器、容差、基线与日期例外未改，diff-check PASS；日志及未验证项见 T053 R8。

## Phase 6 R10 执行记录（S3-D25）

1. 分类与依据：C / 已批准外观无设计增量；负责人「全部批准」，机械记录三核心屏与两张 P7 sheet 的验收，不自行判断批准。
2. 范围：png / manifest / APPROVALS / coreBaselineScreens；复用 S2-D24（1513d36）锁定流程；产品组件、tokens、entry/layout 交互不变，沿用既有测试映射。
3. 决策与保留：写入前当前渲染等于批准 actualSha256；替换 Today S2 / Student Detail S1 的核心清单项并增加趋势，旧十条 baseline/批准历史保留不动。T051 独立复核 PASS、T052 人工验收 PASS、T053 checkpoint PASS。
4. 检查：manifest 13 条 baseline-check PASS；新三屏 finalizer 双渲染锁全部 code 0 / changed 0；完整 1289/0/0/0，三屏各 1/0、P7 28/0、G3 42/0、G4 12/0、s0Conformance 1/0，diff-check PASS，详见 T053 R10。
5. 结果：S3-D21 入口回归及 R7/R9 阻塞闭合，集中走查/核心屏/两张 sheet 批准已登记，无新增待裁决项；未 commit 或改 specs 复选框，人工验收与自动证据各有来源。
