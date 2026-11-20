# S2 implementation map

每个新的用户可见交互一行（`design/design-system/components.md` §1.4）。所有列都必须指向真实代码；会改数据的入口不能只靠长按。

| screen | visible control | testTag | mutation | width owner | test |
|---|---|---|---|---|---|

## Phase 4 round 1 anatomy（实现前）

- 分类 C/D，目标设计不变；复用 DS-PAGE-PRIMARY/SECONDARY、DS-PAGE-HEADER、DS-TITLE-ACTION、DS-SEGMENTED、DS-HERO-CARD、DS-SECTION、DS-LABEL-VALUE-ROW、DS-BUTTON、DS-CHIP、DS-TOGGLE、AD-02。来源为 T002 的三张批准 PNG；日期选择器使用 FcAppointmentDatePicker。
- DS-LIST-ROW 的 Appointment 组合（Today/calendar 共用 `FcAppointmentRow`）：时间 callout 600、名称与部位 body、caption 状态、仅下一节课 scheduled 行显示 disclosure；逾期/其余行按画板不显示；整行最小 row，左右间隔 space.3，上下 space.3；下一节课变体纵排 title 时间、body 姓名、caption 时长/重点。沿用 iOS 行为，视觉仅按 design/ anatomy。无新视觉决策。
- DS-PAGE-FLOW：header→content、hero→section、section→section 为 space.4；sectionLabel→divider/list 为 space.2；相邻行内 divider 属 DS-LIST-ROW；页面水平 space.4，底部 space.6。画板偏差列 proposed-board，不补坐标。
- DS-CALENDAR-DAY：7 个等宽列，Sunday-first，单元最小 touch；28 的选中圆、compact 日期、下方 4 的预约点与非颜色状态说明；只显示当月真实日期。
- editor：header→divider space.4；label/value 行与 divider 连排；重点与重复区上下 space.3、内部 space.2；chip 使用既有共享组件；save 固定在底部，正文可滚动。编辑系列仅展示规则，scope 属 T040，不能伪装已完成。

| 今日 | ＋ 新建安排 | today-add | 否，进入编辑页 | FcPagePrimary title row / FcTitleAddButton | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 今日 | 日历 | today-calendar | 否 | FcPagePrimary title row / FcTitleIconButton | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 今日 | 学员分段 | root-1 | 否 | FcSegmentedSwitch | TodayNavigationEntryLayoutTests.todayToStudentsArrivesWithinSixFramesWithoutOutgoingPage |
| 今日 | 继续训练 | hero-<sessionID> | 否，打开已有训练 | FcHeroCard fillMaxWidth | TodayNavigationEntryLayoutTests.singleAndMultipleHeroesOpenExactExistingSessionAndBackNeverStartsAnother |
| 今日 | 下一节课／逾期／其余安排整行 | today-appointment-<UUID> | 否，先打开课程面板，再从面板内编辑进入安排编辑 | FcAppointmentRow fillMaxWidth | TodayS2EntryLayoutTests.visibleEntriesAndCollapsedResolvedRowsUseRealAppointmentData / overdueAndOtherTodayRowsAreVisibleClickableAndUseSharedStatus；真实 next-up 先开面板再点 course-edit：S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 今日 | 已处理 · N | today-resolved | 否，只切换展开 | FcGroupEntryRow fillMaxWidth | TodayS2EntryLayoutTests.visibleEntriesAndCollapsedResolvedRowsUseRealAppointmentData |
| 今日 | 重试 | today-retry | 否，只重读 | FcButton fillMaxWidth | TodayS2EntryLayoutTests.retryReadsTodayRangeAfterVisibleFailure |
| 今日 | 设置齿轮 | today-settings | 否，打开提醒页 | FcTitleIconButton | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today（真实点击） |

| 课程日历 | 返回 | calendar-back | 否 | FcPageHeader / header Row fillMaxWidth | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 课程日历 | 上月／下月 | calendar-previous / calendar-next | 否 | FcCalendarMonthButton / header Row | CalendarEntryLayoutTests.monthSwitchSelectionAndCreatePassSelectedDateWithoutMutation |
| 课程日历 | 日期格 | calendar-day-<day> | 否，选中日期 | 7 个等宽 Box / FcCalendarDayCell | CalendarEntryLayoutTests.calendarDays / monthSwitchSelectionAndCreatePassSelectedDateWithoutMutation |
| 课程日历 | 安排整行 | calendar-appointment-<UUID> | 否，先打开课程面板，再从面板内编辑进入安排编辑 | FcAppointmentRow fillMaxWidth | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today（真实 calendar row → 课程面板 → course-edit） |
| 课程日历 | 添加课程安排 | calendar-add | 否，进入编辑页并携带 selectedDate | FcButton fillMaxWidth / FcPinnedAction | CalendarEntryLayoutTests.monthSwitchSelectionAndCreatePassSelectedDateWithoutMutation |
| 课程日历 | 重试 | calendar-retry | 否，只重读 | FcButton fillMaxWidth | CalendarEntryLayoutTests.retryReloadsDisplayedMonthAfterVisibleFailure |

| 新建/编辑安排 | 返回 | appointment-editor-back | 否 | FcPageHeader fillMaxWidth | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 新建/编辑安排 | 学员 | appointment-student | 否，展开学员列表 | FcLabelValueRow fillMaxWidth | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 学员选项 | appointment-student-<UUID> | 是，写入草稿 | FcListRow fillMaxWidth | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 日期 | appointment-date | 否，展开 AD-02 日期 | FcLabelValueRow fillMaxWidth | AppointmentEditorEntryLayoutTests.timePickerSupportsClockAndInputAndCancelPreservesDraft |
| 新建/编辑安排 | 开始时间 | appointment-time | 否，打开 AD-02 时间 | FcLabelValueRow fillMaxWidth | AppointmentEditorEntryLayoutTests.timePickerSupportsClockAndInputAndCancelPreservesDraft |
| 新建/编辑安排 | 时间确定／取消／模式 | appointment-time-accept / appointment-time-cancel / appointment-time-mode | 确定写入草稿时间 | FcLinkButton | AppointmentEditorEntryLayoutTests.timePickerSupportsClockAndInputAndCancelPreservesDraft（均点击） |
| 新建/编辑安排 | 预计时长 | appointment-duration | 否，展开时长 | FcLabelValueRow fillMaxWidth | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 时长芯片 | appointment-duration-<分钟> | 是，写入草稿 | FcFilterChip | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 训练重点 | appointment-focus-<index> | 是，切换草稿部位 | FcBodyPartChip / FcBodyPartPicker fillMaxWidth | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 重复 | appointment-repeat-<index> | 是，写入草稿 | FcFilterChip | AppointmentEditorEntryLayoutTests.invalidRecurrenceErrorsAppearInPreviewAndNeverPersist |
| 新建/编辑安排 | 结束方式 | appointment-end-date-mode / appointment-end-count-mode | 是，切换草稿终止 | FcFilterChip | AppointmentEditorEntryLayoutTests.invalidRecurrenceErrorsAppearInPreviewAndNeverPersist |
| 新建/编辑安排 | 结束日期 | appointment-end-date | 否，展开 AD-02 日期 | FcLabelValueRow fillMaxWidth | AppointmentEditorEntryLayoutTests.endDatePickerDisablesDayBeforeStart（已点击展开；前一天唯一且禁用、开始日唯一且启用均通过，完整类 9/0，日志 171844） |
| 新建/编辑安排 | 重复次数 | appointment-count | 是，写入草稿 | FcTextField | AppointmentEditorEntryLayoutTests.invalidRecurrenceErrorsAppearInPreviewAndNeverPersist（可见字段输入） |
| 新建/编辑安排 | 提醒档位 | appointment-reminder-lead | 否，展开档位 | 行内可见按钮，最小 touch | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 档位芯片 | appointment-lead-<分钟> | 是，写入草稿 | FcFilterChip | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 提醒开关 | appointment-reminder | 是，写入草稿 | FcToggle | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 保存 | appointment-save | 是，持久化 | FcButton / FcPinnedAction fillMaxWidth | AppointmentEditorEntryLayoutTests.visibleFieldsPersistSelectedStudentFocusDurationAndReminderTier |
| 新建/编辑安排 | 覆盖并保存 | appointment-conflict-accept | 是，覆盖后持久化 | FcConfirmationDialog | AppointmentEditorEntryLayoutTests.conflictRequiresVisibleConfirmationAndOverrideKeepsExistingAppointments |
| 新建/编辑安排 | 仅本次／本次及以后 | appointment-scope-single / appointment-scope-future | 是，按范围持久化 | FcActionRow / FcBottomSheet | AppointmentEditorEntryLayoutTests.thisOnlyScopeButtonChangesJustTheSelectedOccurrence / seriesEditingRequiresScopeAndFutureKeepsPriorInstance（真实按钮点击；T040 视觉验收待后续） |
| 新建/编辑安排 | 重试 | appointment-retry | 否，只重读 | FcButton fillMaxWidth | AppointmentEditorEntryLayoutTests.retryLoadsStudentChoicesAfterVisibleFailure |

## Phase 4 round 2 执行记录（S2-D17）

分类与依据：D；目标为 c339427 中负责人批准的三份 PNG/layers，6 文件按 blob readback 核对。
范围：共享 DS-TITLE-ACTION 的 add visualModifier overload；Today 挂真实 Icon tag；三份 map 沿用自动映射，Today 手写例外降为 0；editor fixture 改批准 endDate。
设计决策：复用 S2-D17 七项裁决；未引入新视觉决定。gear 与 gearshape 的现有命名冲突和指定自然文字宽度项保留为负责人处理。
实现与检查：Today 28/7/1，Calendar 60/4/0，Editor 65/1/0（PASS/FAIL/MISSING，FAIL 含 MISSING）；S1 1/0，G3 42/0，G4 12/0，Entry 8/0。Today add 的 visual tag 与点击区有独立尺寸断言。
结果：PENDING，三个 strict gate 均 FAIL；不修改 board、comparator、baseline/manifest。L3 仍待负责人批准，comparison 见 T033。

## Phase 4 round 3 anatomy 与导航范围（实现前契约补齐）

分类 D；复用 S2-D17 固定画板与既有 S2 组件，不引入新页面设计。根 Today 改为 TodayS2Screen；设置齿轮继续禁用，Phase 5 才接入。
本 phase 的安排行按本表既有「进入安排详情/编辑」落点直接进入真实编辑 route；D1 课程操作面板、开始/取消/缺席/删除仍归 T041，不借本轮宣称完成。
S2Routes 独立定义 Calendar / create(date) / edit(UUID)；S1Routes 的冻结成员和原校验不变。scope guard 只新增这三个已授权目的地及两个 builder；保留未知 S2 路由负例。
| 来源 | 可见控件 | tag | mutation | width owner | integration test |
|---|---|---|---|---|---|
| 根 Today S2 | 新建安排 | today-add | 否，route 携带 today | FcTitleAddButton / FcPagePrimary | S2NavigationEntryLayoutTests |
| 根 Today S2 | 课程日历 | today-calendar | 否 | FcTitleIconButton / FcPagePrimary | S2NavigationEntryLayoutTests |
| Today / Calendar | 安排行 | today-appointment-UUID / calendar-appointment-UUID | 否，编辑 route 携带 UUID | FcAppointmentRow fillMaxWidth | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today（Today/Calendar row 均真实点击） |
| 编辑页 | 返回 / 保存后返回 | appointment-editor-back / appointment-save | 返回不写；保存沿用持久化用例 | FcPageHeader / FcPinnedAction | S2NavigationEntryLayoutTests + AppointmentEditorEntryLayoutTests |
| 日历 | 返回 | calendar-back | 否 | FcPageHeader | S2NavigationEntryLayoutTests |

## Phase 4 round 3 执行结果

分类：D，复用 S2-D17；gear 仅按 92d864a 重命名，比较规则按 S2-D18。
范围：共享测试 comparator、真实 S2Routes/NavHost 与其入口测试；设置保持 Phase 5 禁用。
设计决策：无新增；图层与容差均有负责人裁决，不改渲染坐标、PNG 或 baseline。
实现与检查：三屏 33/0/0、64/0/0、66/0/0；S1 七屏及 baseline 均绿；G3 42/0、G4 12/0、P7 15/0、comparator+scope 100/0、Entry/Nav 23/0，含真实 row 的导航补充单跑 1/0。
结果：agent 自测 PASS；T034 仍 PENDING 宿主完整门禁与 owner L3，候选 hash 仅在 T033。

## Phase 5 anatomy（实现前）

分类 C/D；复用批准的 24 scope、18-s2 action sheet、42/43-s2 settings 与 AD-02。删除误建是 T002 已批准 B delta；不新增设计决定。
范围：复用 DS-BOTTOM-SHEET（标题、副标题、grabber）、DS-ACTION-ROW（subtitle/destructive/disabled）、DS-LIST-ROW、DS-STATUS、DS-PAGE-FLOW、DS-BUTTON；scope 的取消占满 sheet-content；课程操作由 Today/Calendar 安排行打开，编辑作为面板内可见入口；settings 仅提醒。
组合：页面水平 space.4、块间 space.4、标签至内容 space.2、底部 space.6；sheet 内使用共享组件现有间距，不以坐标贴板。

| 编辑范围 | 取消 | appointment-scope-cancel | 否，保留草稿和 Room 原数据 | FcLinkButton fillMaxWidth / sheet-content | AppointmentEditorEntryLayoutTests.seriesEditingRequiresScopeAndFutureKeepsPriorInstance |
| Today / Calendar | 安排行 → 课程面板 → 编辑安排 | course-edit | 否，进入 editor | FcActionRow / course-actions fillMaxWidth | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 课程面板 | 开始训练 | course-start | 是，创建/关联训练后导航 | FcButton / course-actions fillMaxWidth | CourseActionEntryLayoutTests.startPersistsAndNavigatesOnlyAfterSuccess / failedStartShowsErrorAndKeepsRoomUnchanged |
| 课程面板 | 进入上次训练 | course-previous | 否，FR-007a 新安排不变 | FcButton fillMaxWidth | CourseActionEntryLayoutTests.startCreatesLinkedTrainingWithFocusAndVisiblePreviousTrainingEntryLeavesNewAppointmentUnchanged |
| 课程面板 | 标记缺席 / 返回 | course-absent / course-absent-back | 否，选择页 | FcActionRow / FcLinkButton fillMaxWidth | CourseActionEntryLayoutTests.absentBackThenExplicitDebitPersistsOneIdempotentAppointmentEvent |
| 缺席选择 | 不扣课 / 扣1课时 | course-absent-free / course-absent-debit | 是，前者仅缺席，后者一次 appointmentAbsent 扣课 | FcActionRow fillMaxWidth | CourseActionEntryLayoutTests.absentWithoutDebitNeverWritesLedger / absentBackThenExplicitDebitPersistsOneIdempotentAppointmentEvent |
| 课程面板 | 取消本次 / 确认与返回 | course-cancel / course-confirm-accept / course-confirm-cancel | 仅确认保留取消记录、不扣课 | FcActionRow / FcConfirmationDialog | CourseActionEntryLayoutTests.cancelConfirmationAndDismissKeepRecordWithoutDebit |
| 课程面板 | 删除误建 / 确认与返回 | course-delete / course-confirm-accept / course-confirm-cancel | 仅确认永久删除可删除安排 | FcActionRow fillMaxWidth / FcConfirmationDialog | CourseActionEntryLayoutTests.deleteRequiresConfirmationAndHasFullWidthVisibleControl |
| 课程面板 | 取消（关闭面板） | course-dismiss | 否 | FcLinkButton fillMaxWidth | CourseActionEntryLayoutTests.overdueNeverOffersPermanentDeleteAndEditDismissDoNotWrite |

| 课程面板 | 继续训练 | course-continue | 否，打开已关联训练 | FcButton fillMaxWidth | CourseActionEntryLayoutTests.linkedAppointmentHasVisibleContinueAndNeverDelete |
| 删除学员 | 受影响安排数 / 取消 | delete-student-appointments / StudentTestTags.DELETE_CANCEL | 否，取消不删除 | 既有 DeleteStudentScreen 列与按钮 | CourseActionEntryLayoutTests.studentDeleteConfirmationCountsAppointmentsAndCancelKeepsRoom |
| 今日 | 设置齿轮 | today-settings | 否，打开提醒页 | FcTitleIconButton / title row | S2NavigationEntryLayoutTests.realNavHostOpensEditorAndCalendarAndReturnsToS2Today |
| 设置 | 通知 / 前往设置 | settings-notifications | 否，系统 Intent | FcHubRow / settings-content fillMaxWidth | ReminderSettingsEntryLayoutTests.deniedRowUsesStatusAndVisibleSystemSettingsActionWithoutRoomMutation / enabledRowStillOpensSystemSettingsAndNeverRequestsRuntimePermission |
| 设置 | 返回 | settings-back | 否 | FcPageHeader | ReminderSettingsEntryLayoutTests.deniedRowUsesStatusAndVisibleSystemSettingsActionWithoutRoomMutation |
| 设置 | 重试 | settings-retry | 否，重读权限 | FcButton fillMaxWidth | ReminderSettingsEntryLayoutTests.failureRetryAndOpenFailureAreVisibleAndDoNotChangeRoom |
| 保存已启用提醒且权限已拒绝 | 前往设置 / 完成 | saved-reminder-denied-accept / saved-reminder-denied-cancel | 否，安排已落盘；前往设置只打开提醒页 | FcConfirmationDialog | S2NavigationEntryLayoutTests.deniedReminderSaveKeepsRowAndCompleteDismisses / deniedReminderSaveOpensSettingsFromVisibleAction |
| 结束关联训练 | 丢弃未完成组并结束 | finish-discard | 是，完成并按关联安排扣一次；不出现扣/不扣 | FcButton / finish-content fillMaxWidth | LinkedFinishEntryLayoutTests.linkedCompletionUsesVisibleDiscardAndDeductsOnceWithoutAdhocChoice |
| 结束关联训练 | 扣课失败后重试 | finish-retry | 是，重试后仍只一笔；无「不扣课」 | FcButton fillMaxWidth | LinkedFinishEntryLayoutTests.linkedDebitFailureHasExplicitRetryAndNoInvalidSkip |
| 结束关联训练 | 返回继续 | finish-return | 否 | FcSecondaryButton | LinkedFinishEntryLayoutTests.linkedReturnKeepsTrainingAndAppointmentWithoutDebit |

## Phase 6 P3 修复（D；复用现有组件）

分类：D；保存后的 Room 读取失败使用 ReminderSettingsState.refresh 的同一失败文案，复用 DS-CONFIRM-DIALOG（components §4.4 / CG-6），保守「完成」在左、「重试」在右。settings 43 批准画板与既有错误重试语义不变，无新 token、anatomy 或视觉决定。
范围：移除无兜底 read；保存成功仍保持 durable，失败只表示提醒状态未读到。原 denied dialog 保留。移除仅 revision 差值的无限等待，rotation 保留活动请求，process death 丢失请求则读取当前状态。
设计决策：无新设计；组件仅使用现有 title/body/actions slots。
实现与检查：最终writer完整单测1168/0/0/0，含授权状态3、读取错误UI 1、导航11、seed14、alarm evidence6；dispatcher host gate r5 BUILD 0 / UNIT 0 / total1168 / BAD0（含全部p4 conformance、P7、G3/G4/Room、s1SeedChecks等），见T054与交付report。
结果：T050宿主API31 r7/API36 r6五方法各OK (1 test)，T052两P2修复后限定复核PASS；历史失败与fix4～fix6保留在report。仅T053负责人走查/基线批准及合并后最终gate摘要PENDING，见T050/T054。

| screen | visible control | testTag | mutation | width owner | test |
|---|---|---|---|---|---|
| 保存后提醒状态读取失败 | 重试 | saved-reminder-error-accept | 否，重读提醒状态，不重复保存 | FcConfirmationDialog / DS-CONFIRM-DIALOG | SavedReminderReadErrorTests.failedReadShowsSettingsFailureAndVisibleRetryRecoversWithoutCrash / S2NavigationEntryLayoutTests.saveCallbackReadFailurePreservesAppointmentAndVisibleRetryRecovers |
| 保存后提醒状态读取失败 | 完成／遮罩关闭 | saved-reminder-error-cancel | 否，关闭错误提示 | FcConfirmationDialog / DS-CONFIRM-DIALOG | SavedReminderReadErrorTests |
