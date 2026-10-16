# FineCoach 交互一致性审计（T2）

审计基线：`6c36e40702d49e86d6d561a34776e254d679288d`，分支 `docs/t2-interaction-audit`。仅静态只读审计产品源文件；唯一新增文件为本文。开始时 `git status --short`、`git diff --stat` 均为空；无既有 tracked、staged、untracked 改动。未运行 xcodebuild、模拟器或截图，未提供修复方案。

范围：`ios/FineCoachApp/Features/` 75 个 Swift 文件、`ios/FineCoachApp/DesignSystem/Components/` 24 个 Swift 文件；必要时跟踪 App 的 identifier 定义和 Core 调用。已先读 `AGENTS.md`、`design/design-system/components.md` §1.4，以及 `design/experience-p0/implementation-map.md` P0-D8～D14 / 入口与布局清单。

口径：一行一个操作类型，不按数据库实体实例计数。标「草稿」的是输入或内存流程状态，不能当成持久化成功；「无」指没有显式 identifier，容器 identifier 与内部按钮分开说明；「未确认」指静态证据不足。「可反向修改」不等同撤销原操作或恢复原流水。系统分享只能证明 handoff 路径，不能证明交付。确认栏中的「自定义确认」为 `FCConfirmationDialog`，与系统 `confirmationDialog` 区分；独立确认页面另行说明，不能强行归为 sheet。

## 1. 修改数据的入口清单

下列代码路径均相对本 worktree 根目录；`Features/` 前缀为 `ios/FineCoachApp/Features/`，`Components/` 前缀为 `ios/FineCoachApp/DesignSystem/Components/`。identifier 保留代码常量名或动态表达式，不包含实例数据。

### 业务数据、状态及本机偏好

| 页面 | 操作 | 触发控件（Button / swipeActions / Menu / contextMenu / toolbar / 手势） | accessibilityIdentifier（没有就写「无」） | 是否有确认（无 / alert / confirmationDialog / 撤销提示 / sheet） | 是否可以撤销 | 代码位置 file:line |
|---|---|---|---|---|---|---|
| 学员详情 → 训练页 | 无活动训练时创建 Session；有活动训练时打开；加载先 reconcileOnLaunch | FCButton → 页面 task | FCAccessibilityID.detailStartTraining | 无 | 未见撤销创建；可按结束流程放弃空训练 | Features/Students/StudentDetail/StudentDetailView.swift:411；Features/ActiveSession/ActiveSessionView.swift:174；Features/ActiveSession/ActiveSessionViewModel.swift:150；ios/FineCoachApp/Core/Application/ActiveSessionUseCases.swift:60 |
| 训练中 | 保存失败后重试持久化 | Button（FCButton） | activeSession.retry | 无 | 未确认 | Features/ActiveSession/SaveStatusView.swift:18；Features/ActiveSession/ActiveSessionViewModel.swift:251 |
| 训练中·添加动作 | 添加动作库匹配项 | sheet 内 Button | FCAccessibilityID.activeSessionCatalogRow(entry.id) | sheet | 无直接撤销；可删除动作 | Features/ActiveSession/QuickCreateExerciseFlow.swift:16 |
| 训练中·添加动作 | 新建仅本次动作 | sheet 内 FCButton | activeSession.saveExercise | sheet | 无直接撤销；可删除动作 | Features/ActiveSession/QuickCreateExerciseFlow.swift:81 |
| 训练中·添加动作 | 新建动作存入库并加入训练 | sheet 内 FCButton | activeSession.saveExerciseToLibrary | sheet | 无直接撤销；可删除训练动作、归档库动作 | Features/ActiveSession/QuickCreateExerciseFlow.swift:88 |
| 训练中 | 删除不含已完成组的动作 | swipeActions Button | activeSession.deleteExercise | 无 | 未见撤销 | Features/ActiveSession/ActiveSessionView.swift:406；Features/ActiveSession/ActiveSessionViewModel.swift:313 |
| 训练中 | 删除含已完成组的动作 | swipeActions → 全屏 FCButton | activeSession.deleteExercise → activeSession.deleteExerciseConfirm | sheet（全屏说明与确认） | 未见撤销 | Features/ActiveSession/ActiveSessionView.swift:406；Features/ActiveSession/DeleteExerciseFlow.swift:18 |
| 训练中 | 动作移到无分区 | swipeActions → confirmationDialog Button | 入口 activeSession.moveToSection；执行无 | confirmationDialog（选择目标） | 可再次移动；无 undo | Features/ActiveSession/ActiveSessionView.swift:203 |
| 训练中 | 动作移入已有分区 | swipeActions → confirmationDialog Button | 入口 activeSession.moveToSection；执行无 | confirmationDialog（选择目标） | 可再次移动；无 undo | Features/ActiveSession/ActiveSessionView.swift:207 |
| 训练中 | 创建分区 | sheet 内 FCButton | 无；打开面板 activeSession.createSection | sheet | 无直接撤销；可删分区 | Features/ActiveSession/ActiveSessionView.swift:557 |
| 训练中 | 删除分区、成员移到无分区 | 标题 Button → confirmationDialog Button | 执行无；标题容器 activeSessionSectionHeader(section.id) | confirmationDialog | 未见撤销 | Features/ActiveSession/ActiveSessionView.swift:188 |
| 训练中 | 删除分区及动作 | 标题 Button → confirmationDialog destructive Button | 执行无；标题容器 activeSessionSectionHeader(section.id) | confirmationDialog | 未见撤销 | Features/ActiveSession/ActiveSessionView.swift:191 |
| 训练中 | 确认新录入组 | FCButton | activeSession.confirmSet | 无；执行后撤销提示 | 新建路径短暂撤销；activeDraftSetID 分支不 offerUndo | Features/ActiveSession/SetEditor.swift:103；Features/ActiveSession/ActiveSessionViewModel.swift:379 |
| 训练中 | 确认已有 draft/pending 组 | 组圆圈 Button / accessibilityAction | 行 FCAccessibilityID.setAt(index)；圆圈无独立 id | 无 | 未发现此路径提供短暂撤销 | Features/ActiveSession/ActiveSessionView.swift:603；Features/ActiveSession/ActiveSessionViewModel.swift:406；Components/FCSetRow.swift:104 |
| 训练中 | 保存组数值修改 | FCButton | activeSession.saveSetEdit | 无 | 可再编辑；无 undo | Features/ActiveSession/SetEditor.swift:88；Features/ActiveSession/ActiveSessionViewModel.swift:452 |
| 训练中 | 删除组，含已完成组 | swipeActions destructive Button | FCAccessibilityID.setDeleteAt(setIndex) | 无 | 未见撤销；还会清除此组已有 undo | Features/ActiveSession/ActiveSessionView.swift:365；Features/ActiveSession/ActiveSessionViewModel.swift:470 |
| 训练中 | 撤销刚确认组（删除该组并回填输入） | FCLinkButton / accessibilityAction | 行 FCAccessibilityID.setAt(index)；内部撤销无独立 id | 撤销提示（4 秒） | 无直接重做；可重新确认 | Features/ActiveSession/ActiveSessionView.swift:607；Features/ActiveSession/ActiveSessionViewModel.swift:491；Components/FCSetRow.swift:71 |
| 训练中 | 正常结束训练并执行课时结算 | 底部 FCButton | activeSession.finish | canComplete 分支无；特殊分支下列说明 | 未见重新打开入口；课时撤销未确认 | Features/ActiveSession/ActiveSessionView.swift:129；Features/ActiveSession/ActiveSessionViewModel.swift:512、575、588 |
| 训练中·结束流程 | 放弃空训练并调用预约结算 | 全屏 FCButton | activeSession.abandonConfirm | sheet（全屏） | 未确认 | Features/ActiveSession/FinishSessionFlow.swift:18；Features/ActiveSession/ActiveSessionViewModel.swift:541 |
| 训练中·结束流程 | 丢弃 unresolved 组，条件满足则结束 | 全屏 FCButton | activeSession.discardDrafts | sheet（全屏） | 未见撤销 | Features/ActiveSession/FinishSessionFlow.swift:23；Features/ActiveSession/ActiveSessionViewModel.swift:555 |
| 训练中·时长复核 | 保存调整时长，条件满足继续结束 | 全屏 FCButton | activeSession.durationConfirm | sheet（全屏） | 未见撤销 | Features/ActiveSession/FinishSessionFlow.swift:89；Features/ActiveSession/ActiveSessionViewModel.swift:531 |
| 训练结束·临时课 | 扣 1 课时 | FCConfirmationDialog confirm Button | 无 | 自定义确认 | 未确认；未见原流水撤回入口 | Features/ActiveSession/ActiveSessionView.swift:311；Features/ActiveSession/ActiveSessionViewModel.swift:618 |
| 模板列表 | 创建空模板 | sheet 内 FCButton | 无；打开面板 templates.add | sheet | 无直接撤销；可删模板 | Features/Templates/TemplateListView.swift:125 |
| 模板编辑 | 名称变更并自动保存 | FCTextField.onChange | templateEditor.name | 无 | 可再编辑；无 undo | Features/Templates/TemplateEditorView.swift:177 |
| 模板编辑 | 训练重点变更并自动保存 | BodyPartMultiSelectView 内 Button | 无 | 无 | 可再选；无 undo | Features/Templates/TemplateEditorView.swift:182；Components/FCBodyPartChip.swift:18 |
| 模板编辑 | 添加模板动作 | FCButton | templateEditor.addExercise | 无 | 可移除；无 undo | Features/Templates/TemplateEditorView.swift:200 |
| 模板编辑 | 创建模板分区 | FCButton | templateEditor.createSection | 无 | 可删除；无 undo | Features/Templates/TemplateEditorView.swift:207 |
| 模板编辑 | 删除模板 | FCActionRow → FCConfirmationDialog Button | 入口 templates.delete；最终确认无 | 自定义确认 | 未见撤销 | Features/Templates/TemplateEditorView.swift:213、232 |
| 模板编辑 | 动作移到无分区 | Menu 内 Button | 无；行容器 templateExerciseRow(exercise.id) | 无（Menu 是选择） | 可再移动；无 undo | Features/Templates/TemplateEditorView.swift:269 |
| 模板编辑 | 动作移到已有分区 | Menu 内 Button | 无；行容器 templateExerciseRow(exercise.id) | 无 | 可再移动；无 undo | Features/Templates/TemplateEditorView.swift:274 |
| 模板编辑 | 移除模板动作（立即写入） | 行内 Button | 无；行容器 templateExerciseRow(exercise.id) | 无 | 未见撤销 | Features/Templates/TemplateEditorView.swift:280、98 |
| 模板编辑 | 删除空分区 | 分区标题 Button | 无；标题容器 templateSectionRow(section.id) | 无 | 未见撤销 | Features/Templates/TemplateEditorView.swift:299、135 |
| 模板编辑 | 删除非空分区，动作移到无分区 | 标题 Button → confirmationDialog Button | 无 | confirmationDialog | 未见撤销 | Features/Templates/TemplateEditorView.swift:255 |
| 模板编辑 | 删除非空分区及动作 | 标题 Button → confirmationDialog Button | 无 | confirmationDialog | 未见撤销 | Features/Templates/TemplateEditorView.swift:258 |
| 应用模板页 | 应用模板并持久化新分区 | 整行 Button | FCAccessibilityID.applyTemplateRow(template.id) | 无 | 未见撤销 | Features/Templates/ApplyTemplateView.swift:84、36 |
| 训练中·从模板面板 | 应用模板并持久化新分区 | sheet 内 FCLinkButton | FCAccessibilityID.applyTemplateRow(template.id) | sheet | 未见撤销 | Features/Templates/ApplyTemplateView.swift:152 |
| 动作库选项 | 收藏/取消收藏 | sheet 内 Toggle | 容器 exerciseLibraryFavorite(entry.id) | 无 | 可切回 | Features/ExerciseLibrary/ExerciseLibraryView.swift:281 |
| 动作库选项 | 隐藏/取消隐藏 | sheet 内 Toggle | 容器 exerciseLibraryHide(entry.id) | 无 | 可切回 | Features/ExerciseLibrary/ExerciseLibraryView.swift:290 |
| 动作库选项 | 修改辅助器械标记 | sheet 内 Toggle | 容器 exerciseLibraryAssisted(entry.id) | 无 | 可切回 | Features/ExerciseLibrary/ExerciseLibraryView.swift:299 |
| 动作库选项 | 修改单侧标记 | sheet 内 Toggle | 容器 exerciseLibraryUnilateral(entry.id) | 无 | 可切回 | Features/ExerciseLibrary/ExerciseLibraryView.swift:308 |
| 自定义动作编辑 | 创建动作 | FCButton | customExercise.save | 无 | 无直接撤销；可归档 | Features/ExerciseLibrary/CustomExerciseEditorView.swift:162、50 |
| 自定义动作编辑 | 保存名称/记录模式 | FCButton | customExercise.save | 无 | 可再编辑；无 undo | Features/ExerciseLibrary/CustomExerciseEditorView.swift:162、42 |
| 自定义动作编辑 | 归档动作 | 底部红字 Button | customExercise.archive | 无 | 有恢复 Button | Features/ExerciseLibrary/CustomExerciseEditorView.swift:175 |
| 自定义动作编辑 | 恢复动作 | FCButton | customExercise.restore | 无 | 可再次归档 | Features/ExerciseLibrary/CustomExerciseEditorView.swift:185 |
| 训练总结 | 保存重点、备注、总结并跳过分享 | FCButton | FCAccessibilityID.sessionSummarySkipShare | 无 | 可再编辑；无 undo | Features/History/SessionSummaryView.swift:154、67 |
| 训练总结 | 另存为模板 | sheet 内 FCButton | activeSession.saveAsTemplateConfirm | sheet | 无直接撤销；可删模板 | Features/History/SessionSummaryView.swift:179 |
| 历史训练详情 | 另存为模板 | sheet 内 FCButton | sessionDetail.saveAsTemplateConfirm | sheet | 无直接撤销；可删模板 | Features/History/SessionDetailView.swift:163 |
| 历史训练编辑 | 保存训练重点 | FCButton | sessionEdit.save | 无 | 可再编辑；无 undo | Features/History/SessionEditView.swift:58、26 |
| 欢迎页 | 跳过并完成 onboarding | FCLinkButton | onboarding.skip | 无 | 未见撤销 | Features/Students/Onboarding/OnboardingView.swift:157、15 |
| 首次新增学员 | 新建 Student 并完成 onboarding | 底部 FCButton | studentEditor.save | 无 | 未见撤销；有后续编辑/归档 | Features/Students/Onboarding/StudentEditorView.swift:218、71、73 |
| 新增学员 | 新建 Student | 底部 FCButton | studentEditor.save | 无 | 未见撤销；有后续编辑/归档 | Features/Students/Onboarding/StudentEditorView.swift:218、71 |
| 编辑学员 | 更新 Student | 底部 FCButton | studentEditor.save | 无 | 可再编辑；无 undo | Features/Students/Onboarding/StudentEditorView.swift:218、77 |
| 首次新增学员 | 跳过并完成 onboarding | FCLinkButton | studentEditor.skip | 无 | 未见撤销 | Features/Students/Onboarding/StudentEditorView.swift:202、94 |
| 归档确认页 | 归档 Student | FCButton | archive.confirm | sheet（全屏影响说明） | 归档列表/详情可恢复 | Features/Students/StudentDetail/DeleteStudentFlow.swift:32、35；Features/Students/Onboarding/StudentEditorView.swift:241 |
| 永久删除确认页 | 删除 Student 及关联数据 | 名称匹配后 FCButton | deleteStudent.confirm | sheet（全屏影响说明及输入匹配） | 未见撤销 | Features/Students/StudentDetail/DeleteStudentFlow.swift:158、183 |
| 已归档列表 | 恢复 Student | 行尾 FCLinkButton | 无（只有 label） | 无 | 可再归档；无即时 undo | Features/Students/StudentList/StudentListView.swift:445、63 |
| 已归档详情 | 恢复 Student | 底部 FCButton | studentDetail.restore | 无 | 可再归档；无即时 undo | Features/Students/StudentDetail/StudentDetailView.swift:406、76 |
| 课程操作面板（Today/Calendar/详情共用） | 开始训练、关联 Session、更新 Appointment | FCButton | 无 | sheet（明确选择，无额外确认） | 未确认 | Features/Appointments/CourseActionSheet.swift:157、17；ios/FineCoachApp/Core/Application/AppointmentUseCases.swift:447 |
| 课程操作面板 | 取消本次 Appointment | FCActionRow → 自定义确认 | 入口和最终确认无 | 自定义确认 | 未见撤销 | Features/Appointments/CourseActionSheet.swift:182、92、21 |
| 课程操作面板 | 缺席，不扣课时 | 二级面板 FCActionRow | 无 | sheet（二级明确选择） | 未见撤销 | Features/Appointments/CourseActionSheet.swift:200、25 |
| 课程操作面板 | 缺席，选择扣课时并尝试 applyAbsence | 二级面板 FCActionRow | 无 | sheet（二级明确选择） | 未见原流水撤回 | Features/Appointments/CourseActionSheet.swift:205、25、35 |
| 新建课程 | 新建单次 Appointment | 底部 FCButton | appointmentEditor.save | 无；冲突时 confirmationDialog | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:541、244 |
| 新建课程 | 新建周期 Appointment | 底部 FCButton | appointmentEditor.save | 无；冲突时 confirmationDialog | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:541、256 |
| 编辑课程 | 修改单次安排 | 底部 FCButton | appointmentEditor.save | 非周期直接；周期 scope sheet；冲突 confirmationDialog | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:541、272 |
| 编辑课程 | 只更新本次 trainingFocus | 底部 FCButton | appointmentEditor.save | 无 | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:541、299 |
| 编辑周期课程 | 提交仅本次修改 | scope sheet FCActionRow | 无 | sheet | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:751、204、272 |
| 编辑周期课程 | 提交本次及未来修改 | scope sheet FCActionRow | 无 | sheet（影响范围说明） | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:758、287 |
| 课程冲突确认 | 覆盖冲突，重执行保存 | 系统 confirmationDialog Button | 无 | confirmationDialog | 未见撤销 | Features/Appointments/AppointmentEditorView.swift:571、215 |
| 新建课包 | 创建并激活 CoursePackage | FCButton | coursePackageEditor.save | 有效旧包未过期且余额非零时 confirmationDialog；否则无 | 未见撤销 | Features/CoursePackages/CoursePackageEditorView.swift:209、89、68 |
| 新建课包确认 | 结束当前有效课包并保存新包 | confirmationDialog Button | 无 | confirmationDialog | 未见撤销 | Features/CoursePackages/CoursePackageEditorView.swift:235、80、89 |
| 课包详情 | 结束当前课包 | FCActionRow → 自定义确认 | 入口 coursePackages.end；最终确认无 | 自定义确认 | 未见撤销 | Features/CoursePackages/CoursePackageListView.swift:190、165、67 |
| 人工课时调整 | 新增调增 CreditAdjustment | FCButton | manualAdjustment.save | 无（方向、数量、理由表单） | 可追加反向调整；不撤回原流水 | Features/CoursePackages/ManualCreditAdjustmentView.swift:121、35 |
| 人工课时调整 | 新增调减 CreditAdjustment | FCButton | manualAdjustment.save | 无（方向、数量、理由表单） | 同上 | Features/CoursePackages/ManualCreditAdjustmentView.swift:121、35 |
| 身体数据 | 新建自定义指标 | sheet 内 FCButton | 无 | sheet | 无记录时可删；无即时 undo | Features/BodyData/BodyDataListView.swift:251、134 |
| 指标录入 | 新增当天 measurement | FCButton | bodyMeasurementEntry.save | 无 | 可删除；无即时 undo | Features/BodyData/BodyMeasurementEntryView.swift:288、141 |
| 指标录入 | 覆盖当天已有 measurement | FCButton | bodyMeasurementEntry.save | 无；有 overwriteHint | 未见旧值恢复入口 | Features/BodyData/BodyMeasurementEntryView.swift:288、240、141 |
| 指标录入 | 修改 weight 显示单位偏好 | FCSegmentedSwitch | 容器 bodyMeasurementEntry.unitToggle | 无 | 可切回 | Features/BodyData/BodyMeasurementEntryView.swift:251、65；Features/BodyData/BodyDataUnitPreferences.swift:30 |
| 指标录入 | 修改 length 显示单位偏好 | FCSegmentedSwitch | 容器 bodyMeasurementEntry.unitToggle | 无 | 可切回 | Features/BodyData/BodyMeasurementEntryView.swift:268、70；Features/BodyData/BodyDataUnitPreferences.swift:38 |
| 指标录入 | 删除单条 measurement | 行尾 trash Button → confirmationDialog | trash 无；行 bodyMeasurementRow(measurement.id)；确认 bodyMeasurementEntry.deleteConfirm | confirmationDialog | 未见撤销 | Features/BodyData/BodyMeasurementEntryView.swift:417、360、158 |
| 指标录入 | 清空指标全部 measurement | 红色 Button → confirmationDialog | bodyMeasurementEntry.deleteAll；确认 bodyMeasurementEntry.deleteAllConfirm | confirmationDialog | 未见撤销 | Features/BodyData/BodyMeasurementEntryView.swift:300、377、211 |
| 自定义指标录入 | 停用指标 | toolbar 可见 Menu → Button | 无 | 无 | 同 Menu 可恢复 | Features/BodyData/BodyMeasurementEntryView.swift:393、174 |
| 自定义指标录入 | 恢复指标 | toolbar 可见 Menu → Button | 无 | 无 | 可再停用 | Features/BodyData/BodyMeasurementEntryView.swift:393、176 |
| 自定义指标录入 | 删除未使用指标 | toolbar Menu → Button → confirmationDialog | 入口和最终确认无 | confirmationDialog | 未见撤销 | Features/BodyData/BodyMeasurementEntryView.swift:400、343、193 |
| 备份与恢复 | 导出备份文件并交给系统 exporter | FCButton | backup.export | sheet（系统 exporter） | 外部保存结果和撤回未确认 | Features/BackupRestore/BackupExportFlow.swift:192、81、88 |
| 备份与恢复 | 重试导出备份 | FCLinkButton | backup.retry | sheet（系统 exporter） | 未确认 | Features/BackupRestore/BackupExportFlow.swift:203 |
| 备份与恢复 | 备份替换当前资料 | FCButton | restore.confirm | 无弹窗；页面 warning、suggestBackup、明确 confirm | 本页无 undo；旧状态保留策略未展开 | Features/BackupRestore/BackupRestoreFlow.swift:124、67 |
| 备份与恢复 | 重试恢复 | FCInlineResult retry Button | restore.retry | 同上 | 同上 | Features/BackupRestore/BackupRestoreFlow.swift:185、191 |


### 输入草稿与临时训练状态

这些行不重复计为 durable command；筛选、展开、导航等纯展示状态不计为业务数据修改。每行确认类型均为「无」，可撤销栏表示提交前的状态性质，不证明存在系统 undo。

| 页面 | 操作 | 触发控件 | accessibilityIdentifier | 是否有确认 | 是否可以撤销 | 代码位置 file:line |
|---|---|---|---|---|---|---|
| 添加动作面板 | 修改名称草稿 | FCTextField | activeSession.exerciseName | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/QuickCreateExerciseFlow.swift:8 |
| 添加动作面板 | 修改记录模式草稿 | FCFilterChip | activeSession.mode.weightReps / reps / duration / cardio | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/QuickCreateExerciseFlow.swift:35、98 |
| 添加动作面板 | 修改单侧草稿 | Toggle | 容器 activeSession.newExercise.unilateral | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/QuickCreateExerciseFlow.swift:65 |
| 训练中 | 修改重量草稿 | FCStepperField 输入 / − / + | activeSession.weight / .decrement / .increment | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:20 |
| 训练中 | 修改次数草稿 | FCStepperField 输入 / − / + | activeSession.reps / .decrement / .increment | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:29 |
| 训练中 | 修改时长草稿 | FCTextField | activeSession.duration | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:56、69 |
| 训练中 | 修改距离草稿 | FCTextField | activeSession.distance | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:59 |
| 训练中 | 修改速度草稿 | FCTextField | activeSession.speed | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:62 |
| 训练中 | 修改阻力草稿 | FCTextField | activeSession.resistance | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:65 |
| 训练中 | 修改左侧数值草稿 | FCTextField / FCStepperField | activeSession.left / .decrement / .increment | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:78、120、154 |
| 训练中 | 修改右侧数值草稿 | FCTextField / FCStepperField | activeSession.right / .decrement / .increment | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:81、121、154 |
| 训练中 | 切换左右相同/不同草稿 | FCLinkButton | activeSession.splitSides | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:142 |
| 训练中 | 进入组编辑并加载草稿 | 铅笔 Button / 长按快捷入口 | 行 FCAccessibilityID.setAt(index)；铅笔无独立 id | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/ActiveSessionView.swift:606；Components/FCSetRow.swift:66、132 |
| 训练中 | 取消组编辑，重新带入数值 | FCLinkButton | activeSession.cancelSetEdit | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/SetEditor.swift:94 |
| 新建分区面板 | 修改分区名称草稿 | FCTextField | activeSession.sectionName | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/ActiveSessionView.swift:555 |
| 时长复核 | 修改待保存时长草稿 | FCTextField | activeSession.durationValue | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/FinishSessionFlow.swift:87 |
| 休息条 | 减 15 秒（临时计时并重排通知） | FCLinkButton | activeSession.rest.minus | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/ActiveSessionView.swift:724 |
| 休息条 | 加 15 秒（临时计时并重排通知） | FCLinkButton | activeSession.rest.plus | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/ActiveSessionView.swift:728 |
| 休息条 | 跳过休息（撤销待发通知） | FCLinkButton | activeSession.rest.skip | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/ActiveSessionView.swift:732 |
| 休息条 | 关闭结束提示 | FCLinkButton | activeSession.rest.close | 无 | 草稿可重改；临时计时无持久化 undo | Features/ActiveSession/ActiveSessionView.swift:750 |
| 新模板面板 | 修改模板名称草稿 | FCTextField | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Templates/TemplateListView.swift:124 |
| 模板编辑 | 修改待添加动作名称草稿 | FCTextField | 无；定义常量未赋到控件 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Templates/TemplateEditorView.swift:199 |
| 模板编辑 | 修改待创建分区名称草稿 | FCTextField | templateEditor.sectionName | 无 | 草稿可重改；临时计时无持久化 undo | Features/Templates/TemplateEditorView.swift:205 |
| 自定义动作编辑 | 修改名称草稿 | FCTextField | customExercise.name | 无 | 草稿可重改；临时计时无持久化 undo | Features/ExerciseLibrary/CustomExerciseEditorView.swift:128 |
| 自定义动作编辑 | 修改记录模式草稿 | Button | customExercise.mode.weightReps / reps / duration | 无 | 草稿可重改；临时计时无持久化 undo | Features/ExerciseLibrary/CustomExerciseEditorView.swift:132、204 |
| 训练总结 | 修改重点草稿 | BodyPartMultiSelectView Button | 容器 FCAccessibilityID.sessionSummaryFocus | 无 | 草稿可重改；临时计时无持久化 undo | Features/History/SessionSummaryView.swift:117 |
| 训练总结 | 修改 privateCoachNote 草稿 | TextField | FCAccessibilityID.sessionSummaryPrivateNote | 无 | 草稿可重改；临时计时无持久化 undo | Features/History/SessionSummaryView.swift:119、202 |
| 训练总结 | 修改 studentFacingSummary 草稿 | TextField | FCAccessibilityID.sessionSummaryStudentSummary | 无 | 草稿可重改；临时计时无持久化 undo | Features/History/SessionSummaryView.swift:124、202 |
| 训练总结另存模板 | 修改模板名称草稿 | FCTextField | activeSession.saveAsTemplateName | 无 | 草稿可重改；临时计时无持久化 undo | Features/History/SessionSummaryView.swift:177 |
| 历史详情另存模板 | 修改模板名称草稿 | FCTextField | sessionDetail.saveAsTemplateName | 无 | 草稿可重改；临时计时无持久化 undo | Features/History/SessionDetailView.swift:158 |
| 历史训练编辑 | 修改重点草稿 | BodyPartMultiSelectView Button | 容器 sessionEdit.focus | 无 | 草稿可重改；临时计时无持久化 undo | Features/History/SessionEditView.swift:55 |
| StudentEditor | 修改 displayName 草稿 | 输入框 | FCAccessibilityID.editorName | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:128 |
| StudentEditor | 修改 sex 草稿 | FCFilterChip | FCAccessibilityID.sexIdentifier(sex) | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:140 |
| StudentEditor | 修改 trainingGoal 草稿 | 输入框 | FCAccessibilityID.editorGoal | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:151 |
| StudentEditor | 修改 phone 草稿 | 输入框 | FCAccessibilityID.editorPhone | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:158 |
| StudentEditor | 修改 wechatID 草稿 | 输入框 | FCAccessibilityID.editorWechat | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:166 |
| StudentEditor | 修改 privateCoachNote 草稿 | 输入框 | FCAccessibilityID.editorPrivateNote | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:173 |
| StudentEditor | 修改 injuryNotes 草稿 | 输入框 | FCAccessibilityID.editorInjuryNotes | 无 | 草稿可重改；临时计时无持久化 undo | Features/Students/Onboarding/StudentEditorView.swift:181 |
| AppointmentEditor | 选择 selectedStudentID 草稿 | Menu / Picker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:590 |
| AppointmentEditor | 修改 date 草稿 | 行 Button → DatePicker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:459、465 |
| AppointmentEditor | 修改 startTime 草稿 | 行 Button → DatePicker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:472、478 |
| AppointmentEditor | 修改 durationMinutes 草稿 | 行 Button → Picker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:487、492 |
| AppointmentEditor | 修改 trainingFocus 草稿 | FCBodyPartPicker Button | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:614 |
| AppointmentEditor | 修改 repeatInterval 草稿 | FCFilterChip | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:702 |
| AppointmentEditor | 选择 endMode 为 date 草稿 | FCFilterChip | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:650 |
| AppointmentEditor | 选择 endMode 为 count 草稿 | FCFilterChip | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:654 |
| AppointmentEditor | 修改 endDate 草稿 | DatePicker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:673 |
| AppointmentEditor | 修改 repeatCount 草稿 | Picker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:688 |
| AppointmentEditor | 修改 reminderLeadMinutes 草稿 | Menu / Picker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:715 |
| AppointmentEditor | 修改 reminderEnabled 草稿 | Toggle | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/Appointments/AppointmentEditorView.swift:728 |
| CoursePackageEditor | 修改 name 草稿 | TextField | 容器 FCAccessibilityID.coursePackageEditorName | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/CoursePackageEditorView.swift:128 |
| CoursePackageEditor | 修改 totalCredits 草稿 | FCStepper | 容器 FCAccessibilityID.coursePackageEditorTotalCredits | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/CoursePackageEditorView.swift:136 |
| CoursePackageEditor | 修改 hasStartDate 草稿 | Toggle | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/CoursePackageEditorView.swift:146 |
| CoursePackageEditor | 修改 startDate 草稿 | 行 Button → DatePicker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/CoursePackageEditorView.swift:153、159 |
| CoursePackageEditor | 修改 hasEndDate 草稿 | Toggle | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/CoursePackageEditorView.swift:168 |
| CoursePackageEditor | 修改 endDate 草稿 | 行 Button → DatePicker | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/CoursePackageEditorView.swift:175、181 |
| 人工课时调整 | 修改 direction 草稿 | FCSegmentedSwitch | FCAccessibilityID.manualAdjustmentDirection | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/ManualCreditAdjustmentView.swift:87 |
| 人工课时调整 | 修改 amount 草稿 | FCStepper | FCAccessibilityID.manualAdjustmentAmount | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/ManualCreditAdjustmentView.swift:97 |
| 人工课时调整 | 修改 reason 草稿 | 输入框 | FCAccessibilityID.manualAdjustmentReason | 无 | 草稿可重改；临时计时无持久化 undo | Features/CoursePackages/ManualCreditAdjustmentView.swift:112 |
| 新建指标面板 | 修改指标名称草稿 | FCTextField | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/BodyData/BodyDataListView.swift:249 |
| 新建指标面板 | 修改指标单位草稿 | FCTextField | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/BodyData/BodyDataListView.swift:250 |
| 指标录入 | 修改测量值草稿 | 输入框 | FCAccessibilityID.bodyMeasurementEntryValueField | 无 | 草稿可重改；临时计时无持久化 undo | Features/BodyData/BodyMeasurementEntryView.swift:246 |
| 指标录入 | 修改 custom unitText 草稿 | 输入框 | 无 | 无 | 草稿可重改；临时计时无持久化 undo | Features/BodyData/BodyMeasurementEntryView.swift:285 |
| 备份导出 | 修改口令草稿 | FCTextField | FCAccessibilityID.backupPassword | 无 | 草稿可重改；临时计时无持久化 undo | Features/BackupRestore/BackupExportFlow.swift:160 |
| 备份导出 | 修改确认口令草稿 | FCTextField | FCAccessibilityID.backupPasswordConfirm | 无 | 草稿可重改；临时计时无持久化 undo | Features/BackupRestore/BackupExportFlow.swift:163 |
| 备份恢复 | 选择备份文件草稿 | Button / fileImporter | FCAccessibilityID.restorePickFile | 无 | 草稿可重改；临时计时无持久化 undo | Features/BackupRestore/BackupRestoreFlow.swift:104 |
| 备份恢复 | 修改口令草稿 | FCTextField | FCAccessibilityID.restorePassword | 无 | 草稿可重改；临时计时无持久化 undo | Features/BackupRestore/BackupRestoreFlow.swift:116 |

| 首次导入档案 | 选择文件草稿 | 行 Button / 文件选择器 | FCAccessibilityID.archiveImportFile | 无 | 提交前可改 | Features/ArchiveImport/ArchiveImportView.swift:24 |
| 首次导入档案 | 输入口令草稿 | 输入框 | FCAccessibilityID.archiveImportPassword | 无 | 提交前可改；离开清空 | Features/ArchiveImport/ArchiveImportView.swift:33 |

### 档案、分享及共享组件

| 页面 | 操作 | 触发控件（Button / swipeActions / Menu / contextMenu / toolbar / 手势） | accessibilityIdentifier（没有就写「无」） | 是否有确认（无 / alert / confirmationDialog / 撤销提示 / sheet） | 是否可以撤销 | 代码位置 file:line |
|---|---|---|---|---|---|---|
| 档案设置 | 修改重量显示单位（本机持久化偏好） | Button（FCSegmentedSwitch） | 容器 FCAccessibilityID.archiveSettingsWeight；子选项无独立 id | 无 | 可切回；无原操作 undo | Features/ArchiveViewer/ArchiveSettingsView.swift:26；Features/ArchiveViewer/ArchiveViewerModel.swift:42 |
| 档案设置 | 修改长度显示单位（本机持久化偏好） | Button（FCSegmentedSwitch） | 容器 FCAccessibilityID.archiveSettingsLength；子选项无独立 id | 无 | 可切回 | Features/ArchiveViewer/ArchiveSettingsView.swift:35；Features/ArchiveViewer/ArchiveViewerModel.swift:42 |
| 档案设置 | 修改密度（本机持久化偏好） | Button（FCSegmentedSwitch） | 容器 FCAccessibilityID.archiveSettingsDensity；子选项无独立 id | 无 | 可切回 | Features/ArchiveViewer/ArchiveSettingsView.swift:44；Features/ArchiveViewer/ArchiveViewerModel.swift:42 |
| 档案设置 | 删除本机档案 | Button（FCActionRow）→确认 Button | FCAccessibilityID.archiveSettingsDelete；最终确认无 | 自定义确认 | 未见撤销入口 | Features/ArchiveViewer/ArchiveSettingsView.swift:75、104、111；Features/ArchiveViewer/ArchiveViewerModel.swift:57 |
| 档案设置 | 重试删除本机档案 | Button（FCInlineResult retry） | FCAccessibilityID.archiveSettingsDeleteRetry | 无新确认；沿用先前确认 | 未见撤销入口 | Features/ArchiveViewer/ArchiveSettingsView.swift:87、119 |
| 首次导入档案 | 导入并安装档案 | Button（FCButton） | FCAccessibilityID.archiveImportSubmit | 无弹窗；文件和口令表单 | 未见 undo；另有删除档案路径 | Features/ArchiveImport/ArchiveImportView.swift:35；Features/ArchiveImport/ArchiveImportViewModel.swift:55 |
| 首次导入档案 | 重试导入 | Button（FCInlineResult retry） | FCAccessibilityID.archiveImportRetry | 无 | 同首次导入 | Features/ArchiveImport/ArchiveImportView.swift:78 |
| 较新档案导入 | 选文件及口令，准备候选（未替换） | Button / 文件选择器 / 输入框 | FCAccessibilityID.archiveReplaceFile、archiveReplacePassword、archiveReplaceSubmit | 后续独立确认页面 | 返回清除候选 | Features/ArchiveImport/ArchiveReplaceView.swift:64、72、74；Features/ArchiveImport/ArchiveReplaceViewModel.swift:64 |
| 替换档案确认页 | 替换已安装档案 | Button（FCButton） | FCAccessibilityID.archiveReplaceConfirm | 独立确认页（非 alert / sheet） | 未见 UI 恢复旧档案入口 | Features/ArchiveImport/ArchiveReplaceView.swift:149；Features/ArchiveImport/ArchiveReplaceViewModel.swift:85 |
| 较新档案导入 | 重试准备替换候选 | Button（FCInlineResult retry） | FCAccessibilityID.archiveReplaceRetry | 后续仍进入确认页 | 返回取消候选 | Features/ArchiveImport/ArchiveReplaceView.swift:113 |
| 档案导出 | 选择/取消模块组（内存） | Button（FCListGroupRow） | FCAccessibilityID.archiveExportGroup(key)（组合元素） | 无 | 再点切回 | Features/ArchiveExport/ArchiveSelectionView.swift:55；Features/ArchiveExport/ArchiveExportViewModel.swift:104 |
| 档案导出 | 选择/取消模块项（内存） | Button（FCListRow） | FCAccessibilityID.archiveExportItem(...) | 无 | 再点切回 | Features/ArchiveExport/ArchiveSelectionView.swift:78、88；Features/ArchiveExport/ArchiveExportViewModel.swift:108 |
| 档案导出 | 输入口令（草稿） | 输入框 | FCAccessibilityID.archiveExportPassword | 无 | 可改；返回清空 | Features/ArchiveExport/ArchivePasswordView.swift:18；Features/ArchiveExport/ArchiveExportViewModel.swift:131 |
| 档案导出 | 输入确认口令（草稿） | 输入框 | FCAccessibilityID.archiveExportPasswordConfirm | 无 | 可改；返回清空 | Features/ArchiveExport/ArchivePasswordView.swift:20 |
| 档案导出 | 生成临时加密文件 | Button（FCButton） | FCAccessibilityID.archiveExportGenerate | 前置预览 + 事实确认页；无弹窗 | 离开清理临时文件，不改原记录 | Features/ArchiveExport/ArchivePasswordView.swift:40；Features/ArchiveExport/ArchiveExportViewModel.swift:138、183 |
| 档案交付 | 交给系统；取消/失败后重试时重新生成 | Button（FCButton） | FCAccessibilityID.archiveExportDeliver | 系统分享 sheet | 无可验证的交付撤销 | Features/ArchiveExport/ArchiveDeliveryView.swift:23；Features/ArchiveExport/ArchiveExportViewModel.swift:160 |
| 档案交付 | 完成/离开，清理临时文件与内存口令 | Button / 页头返回 / 返回手势 / onDisappear | FCAccessibilityID.archiveExportDone；步骤返回 archiveExportBack；通用返回无 | 无 | 未见恢复临时文件入口 | Features/ArchiveExport/ArchiveDeliveryView.swift:36；Features/ArchiveExport/ArchiveExportFlowView.swift:46、97 |
| 档案导入/替换 | 离开时清理 Inbox 副本/口令/候选 | 页头 Button / 返回手势 / onDisappear | FCAccessibilityID.archiveImportBack、archiveReplaceBack、archiveReplaceConfirmBack | 无 | 原选择文件不删除；副本未见 undo | Features/ArchiveImport/ArchiveImportViewModel.swift:89；Features/ArchiveImport/ArchiveReplaceView.swift:42；Features/ArchiveImport/ArchiveReplaceViewModel.swift:103、112 |
| 训练详情 | 打开分享页，按需生成 ShareReport 元数据 | Button（FCButton）→ task | FCAccessibilityID.sessionDetailGenerateReport | 无 | 未见撤销元数据入口 | Features/History/SessionDetailView.swift:137；Features/ShareReport/ShareReportFlowView.swift:56、213；ios/FineCoachApp/Core/Application/HistoryUseCases.swift:123 |
| 训练总结 | 保存备注并打开分享页，按需生成 ShareReport 元数据 | Button（FCButton）→ task | FCAccessibilityID.sessionSummaryGenerateReport | 无 | 备注可再编辑；未见撤销元数据入口 | Features/History/SessionSummaryView.swift:146；Features/ShareReport/ShareReportFlowView.swift:56 |
| 分享配置 | 切换 includeRecord（内存 DTO） | Button（checkRow） | 无；父组 shareReportModules | 无 | 可切回 | Features/ShareReport/ShareReportFlowView.swift:290、321 |
| 分享配置 | 切换 includeExercises（内存 DTO） | Button（checkRow） | 无；父组 shareReportModules | 无 | 可切回 | Features/ShareReport/ShareReportFlowView.swift:292、321 |
| 分享配置 | 切换 includeSummary（内存 DTO） | Button（checkRow） | 无；父组 shareReportModules | 无 | 可切回 | Features/ShareReport/ShareReportFlowView.swift:294、321 |
| 分享配置 | 切换 includePersonalBests（内存 DTO） | Toggle | FCAccessibilityID.shareReportPersonalBestToggle（行） | 无 | 可切回 | Features/ShareReport/ShareReportFlowView.swift:296、363 |
| 分享配置 | 切换 includeVolume（内存 DTO） | Toggle | FCAccessibilityID.shareReportVolumeToggle（行） | 无 | 可切回 | Features/ShareReport/ShareReportFlowView.swift:307、363 |
| 分享预览 | 生成临时图片并记录系统 handoff 结果 | 页头 Button | FCAccessibilityID.shareReportShare | 系统分享 sheet | 无可验证的交付撤销 | Features/ShareReport/ShareReportFlowView.swift:414、100；ios/FineCoachApp/Core/Application/HistoryUseCases.swift:150 |
| 分享预览 | 重试分享 | Button（FCLinkButton） | FCAccessibilityID.shareReportRetry | 系统分享 sheet | 同上 | Features/ShareReport/ShareReportFlowView.swift:457 |
| 分享预览 | 离开清理临时图片 | 返回 / onDisappear | 通用 FCPageHeader 返回无 | 无 | 未见恢复临时图片入口 | Features/ShareReport/ShareReportFlowView.swift:413、435、122 |

共享组件自身不拥有业务持久化，绑定与 callback 的业务结果在消费者行中统计，不重复计数。扫描确认：FCButton / FCActionRow 转发 callback，FCTextField 修改 binding，FCBodyPartPicker 修改 selection，FCStepper 修改 binding；FCStepperField 的减号、输入框、加号分别接收 identifier；FCSetRow 的确认/编辑/撤销由调用方提供，长按只是编辑快捷方式；FCListGroupRow 的组合元素有 accessibilityAction；FCConfirmationDialog.Action 只有 title/handler，内部最终确认 Button 没有 identifier 参数（Components/FCConfirmationDialog.swift:20、116）。这不能证明运行时子元素继承 identifier；有关归属不明处保留「未确认」。

## 2. 同类操作的方式对比

计数对象：删除按 §1 的操作分支行；确认按源码 presentation 声明；编辑/保存按页面与控件组合；一个共享面板不因三个消费者重复计数。不同统计对象不能相加成“缺陷总数”，方式不同本身也不等于违规。

### 删除

统计 §1 明确删除/移除/清空业务数据的 **16 行**（含删除重试；不把归档、放弃训练、导出临时清理混入）。共有 **9 种入口组合**：

| 做法 | 行数 | 页面 / 证据 |
|---|---:|---|
| swipeActions | 3 | 训练动作无已完成组、有已完成组、训练组；ActiveSessionView.swift:365、406 |
| 分区标题 Button（直接删除或再确认） | 5 | 训练分区两种 disposition；模板空分区及非空两种 disposition；ActiveSessionView.swift:188、191；TemplateEditorView.swift:255、258、299 |
| 行内 Button | 1 | 模板移除动作；TemplateEditorView.swift:280 |
| FCActionRow → 自定义确认 | 2 | 模板删除、档案删除；TemplateEditorView.swift:213；ArchiveSettingsView.swift:75 |
| 全屏确认页 + 名称匹配 + FCButton | 1 | 永久删除 Student；DeleteStudentFlow.swift:158 |
| 行尾 trash Button → 系统确认 | 1 | 单条 measurement；BodyMeasurementEntryView.swift:417 |
| 页面红字 Button → 系统确认 | 1 | 清空指标数据；BodyMeasurementEntryView.swift:300 |
| toolbar 可见 Menu → 系统确认 | 1 | 删除自定义指标；BodyMeasurementEntryView.swift:400 |
| 错误结果 retry Button | 1 | 删除本机档案重试；ArchiveSettingsView.swift:87 |

### 确认 / 危险操作

| 做法 | 数量 | 页面 / 证据 |
|---|---:|---|
| fcConfirmationDialog presentation | 5 处声明 | 训练临时课结算 ActiveSessionView.swift:215；模板删除 TemplateEditorView.swift:225；结束课包 CoursePackageListView.swift:158；档案删除 ArchiveSettingsView.swift:104；取消课程 CourseActionSheet.swift:85 |
| 系统 confirmationDialog | 8 处声明 | 训练分区删除 :180、移入分区 :195；模板分区删除 :247；新课包结束旧包 :230；预约冲突覆盖 :566；BodyMeasurementEntry 的指标/单条/全部删除 :338、352、372。移入分区是选择目标，不与 7 处后果性确认混算 |
| 系统 alert | 0 处声明 | Features 全目录静态搜索未发现；不推断其他目录 |
| fullScreenCover 的独立说明与确认 | 3 个数据删除/归档页面 | ArchiveStudentView、DeleteStudentFlow、DeleteExerciseFlow；DeleteStudentFlow.swift:32、158；DeleteExerciseFlow.swift:18 |
| 训练结束的全屏分支 | 4 个提交控件 | 放弃、丢弃草稿、时长确认、删除动作确认；FinishSessionFlow.swift:18、23、89；DeleteExerciseFlow.swift:18。最后一个与上一行页面重叠 |
| sheet 内选择范围/后果 | 2 个共用面板 | 周期预约 scope（AppointmentEditorView.swift:735）；课程操作及缺席二级（CourseActionSheet.swift:151、196） |
| 独立确认页面 | 1 个替换页面 | ArchiveReplaceConfirmView（ArchiveReplaceView.swift:133、149），展示新旧事实后替换 |
| 原页/步骤页说明 + 明确提交 | 2 个流程 | 恢复备份（BackupRestoreFlow.swift:98、124）；档案导出事实确认后生成（ArchiveDeliveryWarningView.swift:25、ArchivePasswordView.swift:40） |
| 执行后限时撤销 | 1 类 | 新确认组的组行 4 秒撤销；FCSetRow.swift:69；ActiveSessionViewModel.swift:489 |
| 不额外弹确认，直接写入 | 见 §3 的 7 个后果性候选 | 此处不把可切回偏好、普通新增表单等计作危险操作 |

### 返回 / 取消

本组按方式计 **6 种**。源码中共有 **41 处 FCPageHeader 声明**（包括加载状态和按状态提供 back 的头部；此数不是 41 个始终可用的返回按钮），与系统返回、显式取消、保存后退出并存。

| 做法 | 数量口径及出现页面 | 证据 |
|---|---|---|
| FCPageHeader 内联返回 / 条件 back | 41 处头部声明；覆盖 §4.a 所列二级页、档案各导出步骤及加载分支 | Components/FCPageHeader.swift:117；ExerciseLibraryView.swift:114；ArchiveExportViewModel.swift:58 |
| 系统导航栏取消 toolbar | 2 个页面 | ArchiveStudentView 的 DeleteStudentFlow.swift:51；DeleteStudentFlow.swift:89 |
| 原位取消编辑并重新带入 | 1 个流程 | 训练组 SetEditor.swift:94 |
| 全屏页普通文字 Button 返回/取消 | 4 处声明 | FinishSessionFlow.swift:27、35、93；DeleteExerciseFlow.swift:22 |
| sheet 内显式返回/取消 | 3 个本轮定位控件 | CourseActionSheet.swift:210；AppointmentEditorView.swift:766；BodyDataListView.swift:254 |
| 保存后退出 / 选择出口退出 | 3 个编辑流程 | SessionEditView.swift:58 保存后 pop；CustomExerciseEditorView.swift:162 保存后 onSaved；SessionSummaryView.swift:146、154 两个出口均 persistNotes（隐藏返回 :169） |

边界：遮罩关闭由共享 FCBottomSheet.swift:112 / FCConfirmationDialog.swift:218 的手势实现；这些是额外关闭路径，不当成保存或回滚保证。系统边缘返回由 fcSecondaryPage 接入，具体运行时手势可达性未确认。模板编辑自动持久化，返回没有撤回整页修改的事务（TemplateEditorView.swift:62、70、98）。

### 编辑进入方式

**5 种方式 / 5 个编辑流程**；同一流程有快捷方式时同列：

| 做法 | 页面 | 代码位置 |
|---|---|---|
| 详情页头文字操作 | StudentDetail → StudentEditor | StudentDetailView.swift:171 |
| 课程行 → 共用 sheet → FCActionRow | Today / Calendar / StudentDetail → AppointmentEditor（计 1 个共用流程） | CourseActionSheet.swift:177 |
| 可见铅笔 + 长按快捷方式 → 原位编辑 | ActiveSession 的组 | ActiveSessionView.swift:606；FCSetRow.swift:66、132 |
| 页面 FCActionRow → 编辑页 | 历史训练详情 → SessionEdit | SessionDetailView.swift:181 |
| 动作库行 → options sheet → FCActionRow → 编辑页 | ExerciseLibrary → CustomExerciseEditor | ExerciseLibraryView.swift:167、318 |

另有同页直接覆盖录入 **1 类**：BodyMeasurementEntry（:240、288），不经单独历史行编辑页。模板名称/重点是直接输入自动保存（TemplateEditorView.swift:177、182），不把它描述为 draft→Save 流程。

### 保存方式

**6 种模式**；计列明的业务编辑/录入流程，临时导出 generation 和系统 handoff 单列在 §1：

| 做法 | 数量 | 页面 / 证据 |
|---|---:|---|
| 底部 safeAreaInset 固定 FCButton | 2 个表单 | StudentEditorView.swift:217；AppointmentEditorView.swift:540 |
| 页面内容内显式 FCButton | 6 个编辑/录入流程 | SetEditor.swift:88、103；CustomExerciseEditorView.swift:162；SessionEditView.swift:58；CoursePackageEditorView.swift:209；ManualCreditAdjustmentView.swift:121；BodyMeasurementEntryView.swift:288 |
| sheet 内 FCButton | 6 类提交 | 快速新建动作 QuickCreateExerciseFlow.swift:81、88；训练分区 ActiveSessionView.swift:557；模板 TemplateListView.swift:125；指标 BodyDataListView.swift:251；总结另存模板 SessionSummaryView.swift:179；详情另存模板 SessionDetailView.swift:163 |
| 两个出口均先保存 | 1 个流程 / 2 个出口 | 训练总结生成报告和跳过分享；SessionSummaryView.swift:146、154 |
| onChange 立即持久化 | 1 个页面 / 2 类字段 | 模板名称和训练重点；TemplateEditorView.swift:177、182 |
| 切换立即保存偏好 | 3 类消费者 / 9 类设置 | 动作库 4 个标记（ExerciseLibraryView.swift:281–308）；BodyMeasurementEntry 2 种单位（:251、268）；ArchiveSettings 3 种本机设置（:26、35、44） |

## 3. 违反项目硬规则的候选

### 规则出处与判定边界

- **可发现入口**：AGENTS.md「Visual work: component-first」第 4 条引用入口与布局清单；components.md §1.4:74–77、§2 DS-BASE:113 禁止数据修改仅靠长按/contextMenu；CLAUDE.md「Discoverable affordances — no contextMenu-only actions」:95–103 明确允许 swipeActions 和可见 Menu。
- **identifier**：components.md §1.4 的清单字段含 accessibilityIdentifier；AGENTS.md 同上。没有找到“每个内部控件必须有独立 identifier”的逐字硬规则。下列缺 id 是本次 T2 要求列出的候选，不能伪装为已经证实的独立 identifier 硬规则违例；整体 accessibility element 与子按钮需区分。
- **确认形式**：components.md §4.4 DS-CONFIRM-DIALOG:272–277 规定所有破坏性/不可逆操作的确认用共享组件，禁系统 alert / confirmationDialog；§4.3 DS-ACTION-ROW:243 要求 destructive 行弹出 DS-CONFIRM-DIALOG。
- **后果与确认**：CLAUDE.md「Ambiguous, consequential behavior — ask, don't silently pick one reading」:105–119 约束后果重大的需求歧义；不是“每个修改都必须二次弹窗”。因此下列无额外确认条目只列风险候选，是否违反业务规则为未确认。

### 3.1 contextMenu / 长按唯一入口

**0 类。** 两个扫描目录未发现实际 contextMenu 声明；FCSetRow.swift:66 的长按编辑还有 :132 铅笔入口。BodyMeasurementEntryView.swift:389 的 Menu 是可见 toolbar 入口，不是 contextMenu。P0-D10 / D13 的左滑符合可发现入口规则。

### 3.2 数据修改控件缺显式 identifier

下表 **34 个候选位置**（按消费者源码位置，条件分支复用同一 Button 不重复计；最终确认与前置入口分列）。§1 已给执行链；此处只定位 id 缺口。带容器标识的条目不等于整行无标识。

| # | 页面 / 控件 | file:line | 证据边界 |
|---|---|---|---|
| M01 | 训练动作移到无分区最终选择 | Features/ActiveSession/ActiveSessionView.swift:203 | 前置 moveToSection 有 id |
| M02 | 训练动作移到已有分区最终选择 | Features/ActiveSession/ActiveSessionView.swift:207 | 前置有 id |
| M03 | 训练新分区创建提交 | Features/ActiveSession/ActiveSessionView.swift:557 | 开面板入口有 id |
| M04 | 训练分区删除入口 | Features/ActiveSession/ActiveSessionView.swift:474 | header 容器有 id |
| M05 | 训练删分区、移出成员确认 | Features/ActiveSession/ActiveSessionView.swift:188 | 系统 Button 无 |
| M06 | 训练删分区及动作确认 | Features/ActiveSession/ActiveSessionView.swift:191 | 系统 Button 无 |
| M07 | 临时课扣课确认 | Features/ActiveSession/ActiveSessionView.swift:311 | FCConfirmationDialog 内按钮无 |
| M08 | 新建模板提交 | Features/Templates/TemplateListView.swift:125 | templates.add 只标开面板入口 |
| M09 | 模板重点选择并自动写入 | Features/Templates/TemplateEditorView.swift:182 | FCBodyPartPicker 内部 Button 无 id |
| M10 | 模板删除最终确认 | Features/Templates/TemplateEditorView.swift:232 | 入口 templates.delete 有 id |
| M11 | 模板动作移到无分区 | Features/Templates/TemplateEditorView.swift:269 | 行容器有 id |
| M12 | 模板动作移到已有分区 | Features/Templates/TemplateEditorView.swift:274 | 行容器有 id |
| M13 | 模板动作移除 | Features/Templates/TemplateEditorView.swift:280 | 行容器有 id |
| M14 | 模板分区删除入口 | Features/Templates/TemplateEditorView.swift:299 | header 容器有 id |
| M15 | 模板分区移出成员确认 | Features/Templates/TemplateEditorView.swift:255 | 无 |
| M16 | 模板分区及动作删除确认 | Features/Templates/TemplateEditorView.swift:258 | 无 |
| M17 | 已归档列表恢复 | Features/Students/StudentList/StudentListView.swift:445 | 只有 label |
| M18 | 课程开始训练 | Features/Appointments/CourseActionSheet.swift:157 | 无 |
| M19 | 课程取消最终确认 | Features/Appointments/CourseActionSheet.swift:92 | 自定义确认内部 Button 无 |
| M20 | 缺席不扣课 | Features/Appointments/CourseActionSheet.swift:200 | 无 |
| M21 | 缺席扣课 | Features/Appointments/CourseActionSheet.swift:205 | 无 |
| M22 | 周期编辑仅本次提交 | Features/Appointments/AppointmentEditorView.swift:751 | 无 |
| M23 | 周期编辑本次及未来提交 | Features/Appointments/AppointmentEditorView.swift:758 | 无 |
| M24 | 冲突覆盖确认 | Features/Appointments/AppointmentEditorView.swift:571 | 无 |
| M25 | 结束旧包并保存新包确认 | Features/CoursePackages/CoursePackageEditorView.swift:235 | 无 |
| M26 | 结束课包最终确认 | Features/CoursePackages/CoursePackageListView.swift:165 | 入口有 id |
| M27 | 新建自定义指标提交 | Features/BodyData/BodyDataListView.swift:251 | 无 |
| M28 | 指标停用/恢复共用 Button | Features/BodyData/BodyMeasurementEntryView.swift:393 | 两个结果复用同位置 |
| M29 | 删除指标最终确认 | Features/BodyData/BodyMeasurementEntryView.swift:343 | 无 |
| M30 | 取消课程前置入口 | Features/Appointments/CourseActionSheet.swift:182 | 无 |
| M31 | 删除指标前置入口 | Features/BodyData/BodyMeasurementEntryView.swift:400 | 无 |
| M32 | 删除单条 measurement 前置入口 | Features/BodyData/BodyMeasurementEntryView.swift:417 | 行有 bodyMeasurementRow id |
| M33 | 删除档案最终确认 | Features/ArchiveViewer/ArchiveSettingsView.swift:111 | 前置和 retry 有 id |
| M34 | 分享三个内容选择的共用 Button | Features/ShareReport/ShareReportFlowView.swift:322 | 三个消费者 :290、292、294 无独立 id；父组 shareReportModules |

M34 改内存 DTO，其余是直接写业务数据/偏好的入口或其前置确认。草稿缺 id 另见 §1 草稿表，不混入 M01–M34 的消费者位置计数。FCConfirmationDialog 的共性根因定位为 Components/FCConfirmationDialog.swift:20、116（Action 无 id 参数，最终 Button 不赋 id）。

以下**不直接判无标识违例**：FCSetRow 的确认、铅笔、撤销子按钮虽无独立 id，但行有 setAt(index)，并按组件合同合并成元素与命名 accessibilityAction（FCSetRow.swift:83–96）；ArchiveSettings 的 segmented 选择有容器 id；ArchiveExportGroup 有组合元素及 accessibilityAction（FCListRow.swift:294）。子控件在实际 UI automation 中是否独立可定位未确认。

### 3.3 有后果、难直接撤销且无额外确认：7 个风险候选

| # | 操作与静态事实 | file:line | 规则关联 / 未确认 |
|---|---|---|---|
| R01 | 已完成组左滑删除，无确认、无恢复入口；还会清除已有 undo | Features/ActiveSession/ActiveSessionView.swift:365；ActiveSessionViewModel.swift:470 | components.md §4.4 危险确认原则；P0-D11 认可左滑删除但未规定必须弹窗；是否违规未确认 |
| R02 | 模板动作移除立即调用 useCases，无确认/undo | Features/Templates/TemplateEditorView.swift:280、98 | 同上；不是等待最终保存的 draft；是否必须确认未确认 |
| R03 | canComplete 分支结束训练直接完成，可能自动课时结算 | Features/ActiveSession/ActiveSessionViewModel.swift:512、575、588 | 生命周期及课时后果；既有业务授权是否已充分覆盖未确认 |
| R04 | 缺席并扣课：二级 sheet 明确选择后执行，无再确认 | Features/Appointments/CourseActionSheet.swift:205、35 | 已有明确选择，不能写为完全没确认；充分性未确认 |
| R05 | 人工调减：表单直接保存流水，可追加反向调整但非撤回 | Features/CoursePackages/ManualCreditAdjustmentView.swift:121、35 | 已有显式 Save；是否需额外确认未确认 |
| R06 | 备份替换：有 warning / suggestBackup / confirm，无二次弹窗 | Features/BackupRestore/BackupRestoreFlow.swift:98、124、67 | 已有确认文案；是否需共享确认组件/是否足够未确认 |
| R07 | 当天 measurement 覆盖：有 overwriteHint，保存即覆盖，无旧值恢复入口 | Features/BodyData/BodyMeasurementEntryView.swift:240、288、141 | 是否现有提示和 Save 已满足确认未确认 |

没有把可反向切回的偏好、可恢复归档、普通新增、临时文件清理算作上述 7 个候选。模板空分区删除和无已完成组动作删除也无确认/undo（§1），其实际信息损失程度未确认，**另列 2 个边界项，不冒充 7 个强后果候选**。

### 3.4 危险确认组件形式：7 个有直接规则证据的候选

| 页面 / 确认 | file:line | 与硬规则的关系 |
|---|---|---|
| 训练删除分区 | Features/ActiveSession/ActiveSessionView.swift:180 | 系统 confirmationDialog，components.md §4.4:277 禁止 |
| 模板删除分区 | Features/Templates/TemplateEditorView.swift:247 | 同上 |
| 课程冲突覆盖 | Features/Appointments/AppointmentEditorView.swift:566 | 同上；后果为覆盖冲突后提交 |
| 新课包终止旧包 | Features/CoursePackages/CoursePackageEditorView.swift:230 | 同上 |
| 删除自定义指标 | Features/BodyData/BodyMeasurementEntryView.swift:338 | 同上 |
| 删除单条 measurement | Features/BodyData/BodyMeasurementEntryView.swift:352 | 同上 |
| 清空 measurement | Features/BodyData/BodyMeasurementEntryView.swift:372 | 同上 |

移动分区的系统 confirmationDialog（ActiveSessionView.swift:195）是选择目标，不凭 API 名称判危险确认违规。独立全屏删除/归档页与独立档案替换页也未使用该组件，但有既有专门流程设计（例如 P0-D10 引用含已完成组删除说明页）；**权威适用关系未确认**，不将这类页面直接计入 7 个系统危险确认候选。


## 4. 已知的 3 个遗留项，逐条核实

### a. 状态栏遮挡与 fcSecondaryPage

静态源码及 `git show eba18fe` 表明：该提交把训练页原顶部 overlay 改为零高度顶部 `safeAreaInset`，背景为 `surfacePage`，并使用 `ignoresSafeAreaEdges: .top`（Features/ActiveSession/ActiveSessionView.swift:156）。`fcSecondaryPage` 自身只隐藏导航栏和接入返回手势，不提供顶部遮盖（Components/FCPageHeader.swift:202）。

当前共 **34 个调用点 / 31 个文件**，不是旧 Δ7（implementation-map.md:70）的「其余 28 个」。只有训练页发现同样处理；其余 **33 个调用点**未发现。下表每行是调用点，不能将「没有同样处理」直接等同运行时已遮挡。所有行均**需要真机/模拟器确认**。

| 页面 / View | 调用位置（Features/ 下） | 是否可滚动（静态结构） | 同样顶部遮盖 | 结论边界 |
|---|---|---|---|---|
| ExerciseLibraryView | ExerciseLibrary/ExerciseLibraryView.swift:77 | ScrollView:41 | 无 | 需要真机/模拟器确认 |
| ResourceHubView | ResourceHub/ResourceHubView.swift:46 | ScrollView:14 | 无 | 需要真机/模拟器确认 |
| ArchiveExercisesView | ArchiveViewer/ArchiveExercisesView.swift:62 | ScrollView:22 | 无 | 需要真机/模拟器确认 |
| ArchiveAboutView | ArchiveViewer/ArchiveAboutView.swift:42 | ScrollView:12 | 无 | 需要真机/模拟器确认 |
| ArchiveRecordsView | ArchiveViewer/ArchiveRecordsView.swift:81 | ScrollView:37 | 无 | 需要真机/模拟器确认 |
| ArchiveTrendsView | ArchiveViewer/ArchiveTrendsView.swift:71 | ScrollView:45 | 无 | 需要真机/模拟器确认 |
| ArchiveBodyDataView | ArchiveViewer/ArchiveBodyDataView.swift:44 | ScrollView:21 | 无 | 需要真机/模拟器确认 |
| ArchiveMetricHistoryView | ArchiveViewer/ArchiveBodyDataView.swift:101 | ScrollView:81 | 无 | 需要真机/模拟器确认 |
| ArchiveSettingsView | ArchiveViewer/ArchiveSettingsView.swift:101 | ScrollView:16 | 无 | 需要真机/模拟器确认 |
| BodyDataListView | BodyData/BodyDataListView.swift:230 | ScrollView:184 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| BackupExportFlowView | BackupRestore/BackupExportFlow.swift:148 | ScrollView:125 | 无 | 需要真机/模拟器确认 |
| TemplateListView | Templates/TemplateListView.swift:118 | ScrollView:79 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| CoursePackageEditorView | CoursePackages/CoursePackageEditorView.swift:221 | ScrollView:122 | 无 | 需要真机/模拟器确认 |
| HistoryListView | History/HistoryListView.swift:408 | ScrollView:379 | 无 | 需要真机/模拟器确认 |
| TrendsView | Trends/TrendsView.swift:206 | ScrollView:191 | 无 | 需要真机/模拟器确认 |
| ManualCreditAdjustmentView | CoursePackages/ManualCreditAdjustmentView.swift:133 | ScrollView:64 | 无 | 需要真机/模拟器确认 |
| CalendarView | Calendar/CalendarView.swift:169 | ScrollView:148 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| CreditAdjustmentTrailView | CoursePackages/CreditAdjustmentTrailView.swift:192 | ScrollView:169 | 无 | 需要真机/模拟器确认 |
| ShareReportFlowView | ShareReport/ShareReportFlowView.swift:209 | ScrollView:174 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| ShareReportPreviewPage | ShareReport/ShareReportFlowView.swift:434 | ScrollView:408 | 无 | 需要真机/模拟器确认 |
| AppointmentEditorView | Appointments/AppointmentEditorView.swift:553 | ScrollView:449 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| ActiveSessionView | ActiveSession/ActiveSessionView.swift:167 | 外层 ScrollView:66；内层 List:375 禁止滚动 | 有，:156–165 | 本轮仍需要真机/模拟器确认 |
| CoursePackageListView | CoursePackages/CoursePackageListView.swift:155 | ScrollView:103 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| ArchiveExportFlowView | ArchiveExport/ArchiveExportFlowView.swift:44 | loading VStack:57 不滚动；failed / ready 经 ArchiveExportPage:115 的 ScrollView | 无 | 各状态需要真机/模拟器确认 |
| ArchiveImportSummaryView | ArchiveImport/ArchiveImportSummaryView.swift:51 | ScrollView:10 | 无 | 需要真机/模拟器确认 |
| ArchiveImportBlockedView | ArchiveImport/ArchiveImportBlockedView.swift:47 | ScrollView:15 | 无 | 需要真机/模拟器确认 |
| ArchiveImportView | ArchiveImport/ArchiveImportView.swift:47 | ScrollView:15 | 无 | 需要真机/模拟器确认 |
| SettingsView | Settings/SettingsView.swift:44 | ScrollView:13 | 无 | 需要真机/模拟器确认 |
| ArchiveReplaceFormView | ArchiveImport/ArchiveReplaceView.swift:86 | ScrollView:54 | 无 | 需要真机/模拟器确认 |
| ArchiveReplaceConfirmView | ArchiveImport/ArchiveReplaceView.swift:155 | ScrollView:133 | 无 | 需要真机/模拟器确认 |
| StudentDetailView | Students/StudentDetail/StudentDetailView.swift:150 | ScrollView:121 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| StudentListView.archivedBody | Students/StudentList/StudentListView.swift:414 | 归档分支 ScrollView:375 | 无 | 需要真机/模拟器确认 |
| StudentEditorView | Students/Onboarding/StudentEditorView.swift:237 | ScrollView:122 | 无；底部 inset 不计 | 需要真机/模拟器确认 |
| OnboardingView | Students/Onboarding/OnboardingView.swift:59 | VStack:40 内 ScrollView:48，操作在滚动区外 | 无 | 需要真机/模拟器确认 |

32 个调用点直接对应 ScrollView，1 个是 Onboarding 内嵌滚动，1 个是 ArchiveExportFlow 按状态滚动。短内容是否实际产生滚动、顶部是否有其他布局间接避免遮挡，均未确认。

### b. Δ8「删除分区的红字」

定义：`design/experience-p0/implementation-map.md:71`，位置「分区标题的删除分区」，现状「红色小字常驻」，目标「不变」，处理「不改，记入 T2」。

当前 `Features/ActiveSession/ActiveSessionView.swift:470` 的标题 HStack 中仍有文字 Button（:474），用 `activeSession.deleteSection`、`.fcFont(.caption)`、`statusDestructive`（:477–480）。样式与 Δ8 一致，没有把 T2 遗留误报为 P0 未实现。该 Button 无独立 identifier，只有标题容器 `activeSessionSectionHeader(section.id)`（:485）。

“常驻”有代码条件：仅训练中，且遍历动作时遇到分区边界并找到分区才显示（:466–474）；没有证据表明空分区有独立标题入口。Δ8 未展开这些条件。点击后有成员分区进入 `pendingSectionDeletion`，无成员直接删除（Features/ActiveSession/ActiveSessionViewModel.swift:222）；系统 confirmationDialog 提供移出动作和连动作删除（ActiveSessionView.swift:180）。这两项后果未由 Δ8 单独定义；确认组件形式另见 §3。**Δ8 明确样式没有偏离，交互仍是待 T2 收敛的现状，没有已收敛证据。**

### c. CoreTrainingUITests 失效引用

测试文件均为 `ios/FineCoachUITests/ActiveSession/CoreTrainingUITests.swift`。按唯一正向查询 identifier 统计 **6 个**；已检查 App/FCAccessibilityID.swift 动态生成方式，而非只搜字面量。

| 已不存在的 identifier / 控件 | 测试 file:line | 当前生产证据 |
|---|---|---|
| activeSession.addSet / 添加组 | CoreTrainingUITests.swift:45、52、57、90、161、399 | Features/ActiveSession/SetEditor.swift:100 只有确认；P0-D11（implementation-map.md:37）删除旧入口 |
| activeSession.copyPrevious / 复制上一组 | CoreTrainingUITests.swift:23 | SetEditor.swift:100；implementation-map.md:140 明确去掉 |
| activeSession.sideBilateral / 旧左右侧切换 | CoreTrainingUITests.swift:60 | SetEditor.swift:74 无独立侧别切换；:115 单侧输入；当前 activeSession.splitSides 在 App/FCAccessibilityID.swift:335 |
| activeSession.moveDown / 下移 | CoreTrainingUITests.swift:98 | Features/ActiveSession/ActiveSessionView.swift:403 动作操作为删除和移入分区；P0-D9（implementation-map.md:35）去掉排序 |
| activeSession.moveUp / 上移 | CoreTrainingUITests.swift:102 | 同上 ActiveSessionView.swift:403 |
| activeSession.undoSet / 旧独立撤销 | CoreTrainingUITests.swift:122 | Components/FCSetRow.swift:69 改为组行短暂撤销；ActiveSessionView.swift:607 只给行 setAt(index)；ActiveSessionViewModel.swift:489 撤销删除组。测试:124–127 的状态假设也已不同 |

另有 **1 个过时控件查询路径**：`app.navigationBars.buttons.element(boundBy: 0)`（CoreTrainingUITests.swift:341–345）。当前训练页经 ActiveSessionView.swift:167 隐藏系统导航栏（Components/FCPageHeader.swift:202），返回入口是内联 FCPageHeader（ActiveSessionView.swift:495）。未运行测试，不宣称具体运行时失败。

排除误报：`placeholder.training`（测试:324）是缺席的 identifier，但用于否定断言，单列 **1 个不存在的负向查询**，不计入 6 个失效正向入口；同名 localization key 和 PlaceholderDestinationView 仍在 App/RootNavigation.swift:365、372、386。exercise.at / set.at / setState / catalogRow / studentEditor.sex.female 仍有动态生成及赋值（App/FCAccessibilityID.swift:421、433、519；ActiveSessionView.swift:448、611、617；QuickCreateExerciseFlow.swift:30）。`activeSession.deleteExercise` 仍在 ActiveSessionView.swift:411；测试:108 未先左滑属于交互路径变化，不能报 identifier 不存在。


## 汇总

| 类别 | 数量 / 口径 |
|---|---|
| §1 入口清单 | 184 行：业务数据/状态/偏好 87，草稿/临时训练状态 69，档案/分享/清理 28；不是 184 个独立 command，包含分支、前置和重试 |
| 删除交互差异 | 16 个删除结果分支，9 种入口组合（§2）；归档/放弃/临时清理不混算 |
| 确认实现差异 | 自定义确认 5 处；系统 confirmationDialog 8 处，其中 7 处后果性确认、1 处目标选择；系统 alert 0 处。独立确认页、全屏流程、sheet 与原页明确提交并存 |
| 返回/取消差异 | 6 种方式；41 处 FCPageHeader 声明不等于返回按钮数量；各方式定位与边界见 §2 |
| 编辑进入差异 | 5 种入口 / 5 个编辑流程；另有 1 类同页覆盖录入和模板直接自动保存 |
| 保存差异 | 6 种模式；各模式页面/控件计数见 §2，不因共享消费者重复计数 |
| contextMenu / 长按唯一修改入口 | 0 类（仅限本次两个目录的静态扫描） |
| 缺显式 identifier 候选 | 34 个消费者源码位置：M01–M34；其中 1 个位置的 3 个分享选择只改内存 DTO；草稿表另有 21 行无显式 id，不与 34 混加为独立控件数量 |
| 后果性无额外确认候选 | 7 个 R01–R07；另 2 个信息损失程度未确认边界项；不是已裁定的业务硬规则违例 |
| 确认组件形式硬规则候选 | 7 个系统危险 confirmationDialog 声明；与 identifier / R 条目可能重叠 |
| 状态栏遗留项 | 34 调用 / 31 文件；1 调用有同样遮盖，33 调用无；34 行均需要真机/模拟器确认，不能报 33 个已验证遮挡缺陷 |
| Δ8 红字 | 1 个已知遗留项：明确样式与定义一致；显示条件/空分区入口和确认形式另列事实，未收敛 |
| CoreTrainingUITests | 6 个失效正向 identifier，1 个过时导航栏查询路径；另 1 个不存在但用于否定断言的 identifier；deleteExercise 是路径变化，非 ID 消失 |

覆盖边界与未确认：

- 已扫描指定 Features 的 75 个 Swift 文件及 Components 的 24 个 Swift 文件；这两个目录没有主动排除的子目录。不把纯筛选/展开/导航、SwiftUI Preview 中空 callback 计为业务 mutation；导航引发写入的已追踪路径（创建训练、打开分享）已纳入。
- App/FCAccessibilityID.swift、RootNavigation.swift 与必要的 Core use case 只为验证标识和后果追链；没有审计 App/Core 全部自动写入、迁移、后台事件、平台 adapter 或其他测试目录。ShareReport 的首次生成和 handoff 已追到 HistoryUseCases；没有由此推断所有系统 handoff 已完成。
- 草稿表按字段操作类型列出，模式选项、日期 Picker 内系统子控件和部位 chip 实例不按每个实例展开；无障碍树中容器 id 与子控件定位、手势是否成功、safe area 和 Dynamic Type 实际表现均未确认。
- 不可直接恢复与不可撤回只表示未找到相应 UI 路径，没有通读所有底层恢复机制来证明物理不可恢复。旧状态保留、写入原子性、错误恢复和业务执行是否成功未运行验证。
- 规则适用关系未确认的独立全屏/档案确认页、风险候选是否需要额外确认、空分区实际可达性均保留未确认；本文不作产品裁决或修复建议。
- 本轮只做文档静态核对：代码引用存在性、identifier 定义/动态构造、计数、Markdown 表列数及提交范围；没有运行 xcodebuild、任何测试、模拟器、截图或真机验收。
