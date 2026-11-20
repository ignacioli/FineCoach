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
