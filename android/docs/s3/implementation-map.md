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
| 学员详情 | 训练趋势 | studentDetail.trends | 无，进入趋势页 | FcActionRow.fillMaxWidth | StudentRecordEntryLayoutTests.trendsEntryOpensTheTrendPageAtFullWidth |
| 学员详情 | 身体数据 | studentDetail.body | 无，进入身体数据 | FcActionRow.fillMaxWidth | StudentRecordEntryLayoutTests.bodyEntryOpensTheBodyPageAtFullWidth |
| 训练趋势 | 动作 | trends-exercise | 无，只改本页所选动作 | trends-exercise 与 platform-content 同宽 | TrendsEntryLayoutTests.exercisePickerAndMetricAreVisibleAndDoNotWriteHistory |
| 训练趋势 | 指标分段 | trends-metric-$index | 无，只改本页指标 | FcSegmentedSwitch.fillMaxWidth | TrendsEntryLayoutTests.exercisePickerAndMetricAreVisibleAndDoNotWriteHistory |
| 训练历史 | 选择 / 完成 | history-list-trailing | 无，进入或退出选择模式 | FcPageHeader.fillMaxWidth | HistoryCompareEntryLayoutTests.visibleSelectionComparesMatchingFocusAndExplainsAMismatch |
| 训练历史 | 选择这节课 | history-compare-pick-$sessionID | 无，比较不写 Room | 选择按钮 FcButton.fillMaxWidth；比较面板与 history-results 同宽 | HistoryCompareEntryLayoutTests.visibleSelectionComparesMatchingFocusAndExplainsAMismatch |
| 身体数据 | 打开指标 | body-open-$metricId | 无，进入该指标 | FcListRow.fillMaxWidth | BodyDataEntryLayoutTests.openMetricAndSaveCustomMetricFromVisibleControls |
| 身体数据 | 新建自定义指标 | body-custom | 无，打开自定义指标面板 | FcButton.fillMaxWidth | BodyDataEntryLayoutTests.openMetricAndSaveCustomMetricFromVisibleControls |
| 身体数据 | 保存自定义指标 | body-custom-save | Room 新建自定义指标 | body-custom-sheet 内 FcButton.fillMaxWidth | BodyDataEntryLayoutTests.openMetricAndSaveCustomMetricFromVisibleControls |
| 身体数据 | 保存 | body-save | Room：同一学员、同一指标、同一本地自然日 upsert；内置单位先换成 kg/cm | body-save 与 platform-content 同宽 | BodyDataEntryLayoutTests.sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage；displayedUnitIsConvertedBeforeItIsStored |
| 身体数据 | 删除 | body-delete-$id，确认 body-delete-accept / 取消 body-delete-cancel | 确认后 Room 删除并重算趋势；取消不删 | 删除按钮在记录行内 | BodyDataEntryLayoutTests.sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage |
| 身体数据 | 单位 | body-unit-kg / body-unit-lb（或 cm / in） | 无，只改显示 | FcFilterChip | BodyDataEntryLayoutTests.sameDayEditDeleteConfirmationAndDisplayUnitDoNotRewriteStorage |
| 今日 | 提示行 | insights.row.$snoozeKey | 无，进入课包、预填安排或该动作趋势 | 行 Column.fillMaxWidth，与 insight-parent 同宽 | InsightEntryLayoutTests.rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds；threeDestinationsAndStudentDetailOmitsTheName |
| 今日 | 全部 · N | today.insights.all | 无，进入完整列表 | FcGroupEntryRow.fillMaxWidth | InsightEntryLayoutTests.allEntryRendersFullListAndRowOpensPrefilledAppointment |
| 今日 | 左滑暂不提醒 | insights.snooze.$snoozeKey；TalkBack 自定义操作「暂不提醒」 | 是，InsightLocalStateStore 写入不透明 key 和截止日 | 行 Column.fillMaxWidth | InsightEntryLayoutTests.rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds |
| 今日 | 撤销 | insights.undo.$snoozeKey-action | 是，删掉这条暂不提醒 | FcUndoRow.fillMaxWidth | InsightEntryLayoutTests.rowFillsWidthSnoozeUndoAndFullSwipeAndDisappearsAfterFourSeconds |
| 今日 | 首次轻推 | insights.nudge.$snoozeKey（装饰胶囊对无障碍隐藏） | 是，每台设备把 firstNudgePlayed 写成 true；关闭动画时不写 | 行 Column.fillMaxWidth | InsightEntryLayoutTests.nudgePlaysOnceAndIsSkippedWhenMotionIsOff |
| 完整列表 | 分组提示行 | insights.row.$snoozeKey | 无，与今日同一条跳转 | insights-list-content Column.fillMaxWidth | InsightEntryLayoutTests.allEntryRendersFullListAndRowOpensPrefilledAppointment |
| 学员详情 | 提示行 | insights.row.$snoozeKey | 无，进入该动作趋势；主文字不带学员名 | studentDetail.insights Column.fillMaxWidth | InsightEntryLayoutTests.threeDestinationsAndStudentDetailOmitsTheName |
| 学员详情 | 下一节课 | studentDetail.nextClass | 无；有课时打开与今日相同的课程操作，没有课时去预填安排 | StudentOverviewRow 与 platform-content 同宽 | InsightEntryLayoutTests.nextClassRowFillsWidthAndOpensTheScheduledClass |

## R2 执行记录（2026-11-21）

1. 分类：D；修复已批准 E-a1/E-a2/E-b/E-d 行语义与 4 秒撤销行为，复用 DS-SECTION、DS-UNDO-ROW；不增 token 或组件。
2. 范围：InsightBoard/Copy/Rows、InsightUseCases、入口测试及两张核心屏 mapping；比较器按 S3-D17 传递画板高度。
3. 保留 / 移除：保留原行结构、token、左滑与路由；移除 load 清空 pending、主线程文件读取、TalkBack 内部 phase、断言整包 JSON；新增剩余撤销时间及安全失败报告。
4. 检查：入口测试 `allEntryRendersFullListAndRowOpensPrefilledAppointment` 真实渲染完整列表并点击行到预填新建安排；行宽与各自容器相等，Room 安排数不变。其余场景见 T040。
5. 结果：学员详情严格全绿；今日「全部」行剩画板项，Phase 5 未完成；未在设备上验证，也未进行负责人视觉验收。完整门禁见 T045。
