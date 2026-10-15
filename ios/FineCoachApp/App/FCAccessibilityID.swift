import Foundation

public enum FCAccessibilityID {
    public static let privacyCover = "privacy.cover"

    public static let archiveViewerRoot = "archive.viewer.root"

    // M2 first launch, import and viewer (M2-07 to M2-18).
    public static let firstLaunchRoot = "firstLaunch.root"
    public static let firstLaunchCoach = "firstLaunch.coach"
    public static let firstLaunchImport = "firstLaunch.import"
    public static let onboardingBack = "onboarding.back"
    public static let archiveImportRoot = "archiveImport.root"
    public static let archiveImportBack = "archiveImport.back"
    public static let archiveImportFile = "archiveImport.file"
    public static let archiveImportPassword = "archiveImport.password"
    public static let archiveImportSubmit = "archiveImport.submit"
    public static let archiveImportProgress = "archiveImport.progress"
    public static let archiveImportFailure = "archiveImport.failure"
    public static let archiveImportRetry = "archiveImport.retry"
    public static let archiveReplaceRoot = "archiveReplace.root"
    public static let archiveReplaceBack = "archiveReplace.back"
    public static let archiveReplaceFile = "archiveReplace.file"
    public static let archiveReplacePassword = "archiveReplace.password"
    public static let archiveReplaceSubmit = "archiveReplace.submit"
    public static let archiveReplaceProgress = "archiveReplace.progress"
    public static let archiveReplaceFailure = "archiveReplace.failure"
    public static let archiveReplaceRetry = "archiveReplace.retry"
    public static let archiveReplaceConfirmRoot = "archiveReplace.confirmRoot"
    public static let archiveReplaceConfirmBack = "archiveReplace.confirmBack"
    public static let archiveReplaceConfirm = "archiveReplace.confirm"
    public static let archiveBlockedRoot = "archiveBlocked.root"
    public static let archiveBlockedBack = "archiveBlocked.back"
    public static let archiveBlockedAcknowledge = "archiveBlocked.acknowledge"
    public static let archiveSummaryRoot = "archiveSummary.root"
    public static let archiveSummaryBack = "archiveSummary.back"
    public static let archiveSummaryStart = "archiveSummary.start"
    public static let archiveHomeSettings = "archiveHome.settings"
    public static let archiveHomeBanner = "archiveHome.banner"
    public static let archiveHomeRecords = "archiveHome.records"
    public static let archiveHomeBody = "archiveHome.body"
    public static let archiveHomeTrends = "archiveHome.trends"
    public static let archiveHomeExercises = "archiveHome.exercises"
    public static let archiveHomeAbout = "archiveHome.about"
    public static let archiveRecordsRoot = "archiveRecords.root"
    public static let archiveRecordsBack = "archiveRecords.back"
    public static let archiveRecordsSearch = "archiveRecords.search"
    public static let archiveRecordsFilterDate = "archiveRecords.filter.date"
    public static let archiveRecordsFilterFocus = "archiveRecords.filter.focus"
    public static let archiveRecordsFilterClear = "archiveRecords.filter.clear"
    public static let archiveRecordsEmpty = "archiveRecords.empty"
    public static func archiveRecordsRow(_ index: Int) -> String { "archiveRecords.row.\(index)" }
    public static let archiveSessionRoot = "archiveSession.root"
    public static let archiveSessionReadonly = "archiveSession.readonly"
    public static let archiveBodyRoot = "archiveBody.root"
    public static let archiveBodyBack = "archiveBody.back"
    public static func archiveBodyMetric(_ key: String) -> String { "archiveBody.metric.\(key)" }
    public static let archiveMetricRoot = "archiveMetric.root"
    public static let archiveMetricBack = "archiveMetric.back"
    public static let archiveTrendsRoot = "archiveTrends.root"
    public static let archiveTrendsBack = "archiveTrends.back"
    public static let archiveTrendsExercise = "archiveTrends.exercise"
    public static let archiveTrendsMetric = "archiveTrends.metric"
    public static let archiveExercisesRoot = "archiveExercises.root"
    public static let archiveExercisesBack = "archiveExercises.back"
    public static let archiveExercisesSearch = "archiveExercises.search"
    public static let archiveExercisesEmpty = "archiveExercises.empty"
    public static func archiveExercisesRow(_ index: Int) -> String { "archiveExercises.row.\(index)" }
    public static let archiveAboutRoot = "archiveAbout.root"
    public static let archiveAboutBack = "archiveAbout.back"
    public static let archiveAboutAttribution = "archiveAbout.attribution"
    public static let archiveAboutLicenseLink = "archiveAbout.licenseLink"
    public static let archiveSettingsRoot = "archiveSettings.root"
    public static let archiveSettingsBack = "archiveSettings.back"
    public static let archiveSettingsWeight = "archiveSettings.weight"
    public static let archiveSettingsLength = "archiveSettings.length"
    public static let archiveSettingsDensity = "archiveSettings.density"
    public static let archiveSettingsImportNewer = "archiveSettings.importNewer"
    public static let archiveSettingsDelete = "archiveSettings.delete"
    public static let archiveSettingsDeleteFailure = "archiveSettings.deleteFailure"
    public static let archiveSettingsDeleteRetry = "archiveSettings.deleteRetry"
    public static let archiveViewerLoadError = "archiveViewer.loadError"

    // M2 export flow (M2-01 to M2-06).
    public static let detailExportArchive = "studentDetail.exportArchive"
    public static let archiveExportRoot = "archiveExport.root"
    public static let archiveExportBack = "archiveExport.back"
    public static let archiveExportActionError = "archiveExport.actionError"
    public static let archiveExportLoadError = "archiveExport.loadError"
    public static let archiveExportPreview = "archiveExport.preview"
    public static let archiveExportExclusionViewAll = "archiveExport.exclusion.viewAll"
    public static let archiveExportExclusionList = "archiveExport.exclusion.list"
    public static let archiveExportFreeTextNotice = "archiveExport.preview.freeTextNotice"
    public static let archiveExportSectionNames = "archiveExport.preview.sectionNames"
    public static let archiveExportPlaceholderNote = "archiveExport.preview.placeholderNote"
    public static let archiveExportContinue = "archiveExport.continue"
    public static let archiveExportConfirmFacts = "archiveExport.confirmFacts"
    public static let archiveExportPassword = "archiveExport.password"
    public static let archiveExportPasswordConfirm = "archiveExport.passwordConfirm"
    public static let archiveExportPasswordError = "archiveExport.passwordError"
    public static let archiveExportGenerate = "archiveExport.generate"
    public static let archiveExportDeliveryResult = "archiveExport.deliveryResult"
    public static let archiveExportDeliver = "archiveExport.deliver"
    public static let archiveExportDone = "archiveExport.done"

    public static func archiveExportGroup(_ key: String) -> String {
        "archiveExport.group.\(key)"
    }

    public static func archiveExportItem(_ key: String) -> String {
        "archiveExport.item.\(key)"
    }

    public static let onboardingTitle = "onboarding.title"
    public static let onboardingLead = "onboarding.lead"
    public static let onboardingLocalRule = "onboarding.local"
    public static let onboardingShareRule = "onboarding.share"
    public static let onboardingDataLink = "onboarding.dataLink"
    public static let onboardingSheet = "onboarding.sheet"
    public static let onboardingSheetClose = "onboarding.sheet.close"
    public static let onboardingStart = "onboarding.start"
    public static let onboardingSkip = "onboarding.skip"

    public static let calendarRoot = "calendar.root"
    public static let appointmentEditorRoot = "appointmentEditor.root"
    public static let appointmentEditorSave = "appointmentEditor.save"
    public static let calendarPreviousMonth = "calendar.previousMonth"
    public static let calendarNextMonth = "calendar.nextMonth"
    public static let calendarAdd = "calendar.add"

    public static func calendarDay(_ day: Int) -> String {
        "calendar.day.\(day)"
    }

    public static func calendarAppointmentRow(_ id: StableUUID) -> String {
        "calendar.appointmentRow.\(id.rawValue.uuidString)"
    }

    public static let todayRoot = "today.root"
    public static let todaySegmentToday = "today.segment.today"
    public static let todaySegmentStudents = "today.segment.students"
    public static let todayInProgress = "today.inProgress"
    public static let todayResolvedFold = "today.resolvedFold"
    public static let todayCalendarEntry = "today.calendarEntry"
    public static let todayAddAppointment = "today.addAppointment"
    public static let settingsEntry = "settings.entry"
    public static let settingsRoot = "settings.root"
    public static let settingsNotifications = "settings.notifications"
    public static let settingsBackup = "settings.backup"
    public static let settingsAbout = "settings.about"

    public static func todayRow(_ id: StableUUID) -> String {
        "today.row.\(id.rawValue.uuidString)"
    }

    public static func todayRowActions(_ id: StableUUID) -> String {
        "today.rowActions.\(id.rawValue.uuidString)"
    }

    public static let studentList = "studentList.root"
    public static let studentListAdd = "studentList.add"
    public static let studentListSearch = "studentList.search"
    public static let studentListEmpty = "studentList.empty"
    public static let studentListEmptyAdd = "studentList.emptyAdd"
    public static let resourceHubEntry = "resourceHub.entry"
    public static let historyCompareSelect = "history.compareSelect"
    public static let studentListArchived = "studentList.archived"
    public static let studentListInProgress = "studentList.inProgress"

    public static let editorRoot = "studentEditor.root"
    public static let editorName = "studentEditor.displayName"
    public static let editorSexMale = "studentEditor.sex.male"
    public static let editorSexFemale = "studentEditor.sex.female"
    public static let editorSexOther = "studentEditor.sex.other"
    public static let editorSexUndisclosed = "studentEditor.sex.undisclosed"
    public static let editorGoal = "studentEditor.trainingGoal"
    public static let editorInjuryNotes = "studentEditor.injuryNotes"
    public static let editorPhone = "studentEditor.phone"
    public static let editorWechat = "studentEditor.wechat"
    public static let editorPrivateNote = "studentEditor.privateCoachNote"
    public static let editorSave = "studentEditor.save"
    public static let editorSkip = "studentEditor.skip"

    public static let templatesEntry = "templates.entry"
    public static let templateListRoot = "templates.root"
    public static let templateListAdd = "templates.add"
    public static let templateListDelete = "templates.delete"
    public static let templateEditorRoot = "templateEditor.root"
    public static let templateEditorName = "templateEditor.name"
    public static let templateEditorAddExercise = "templateEditor.addExercise"
    public static let templateEditorExerciseName = "templateEditor.exerciseName"
    public static let templateEditorCreateSection = "templateEditor.createSection"
    public static let templateEditorSectionName = "templateEditor.sectionName"
    public static let activeSessionSaveAsTemplate = "activeSession.saveAsTemplate"
    public static let activeSessionSaveAsTemplateName = "activeSession.saveAsTemplateName"
    public static let activeSessionSaveAsTemplateConfirm = "activeSession.saveAsTemplateConfirm"
    public static let activeSessionApplyTemplate = "activeSession.applyTemplate"
    public static let activeSessionCreateSection = "activeSession.createSection"
    public static let activeSessionSectionName = "activeSession.sectionName"
    public static let applyTemplateRoot = "applyTemplate.root"

    public static func templateRow(_ id: StableUUID) -> String {
        "templates.row.\(id.rawValue.uuidString)"
    }

    public static func templateExerciseRow(_ id: StableUUID) -> String {
        "templateEditor.exerciseRow.\(id.rawValue.uuidString)"
    }

    public static func templateSectionRow(_ id: StableUUID) -> String {
        "templateEditor.sectionRow.\(id.rawValue.uuidString)"
    }

    public static func applyTemplateRow(_ id: StableUUID) -> String {
        "applyTemplate.row.\(id.rawValue.uuidString)"
    }

    public static func activeSessionSectionHeader(_ id: StableUUID) -> String {
        "activeSession.sectionHeader.\(id.rawValue.uuidString)"
    }

    public static let coursePackageListRoot = "coursePackages.root"
    public static let coursePackageListAdd = "coursePackages.add"
    public static let coursePackageListEnd = "coursePackages.end"
    public static let coursePackageListManualAdjust = "coursePackages.manualAdjust"
    public static let coursePackageListViewTrail = "coursePackages.viewTrail"

    public static func coursePackageRow(_ id: StableUUID) -> String {
        "coursePackages.row.\(id.rawValue.uuidString)"
    }

    public static let bodyDataListRoot = "bodyData.root"
    public static let bodyDataAddCustomMetric = "bodyData.addCustomMetric"
    public static let bodyDataEmptyState = "bodyData.emptyState"
    public static let bodyDataNewCustomMetricError = "bodyData.newCustomMetric.error"

    public static func bodyDataMetricRow(_ id: StableUUID) -> String {
        "bodyData.metricRow.\(id.rawValue.uuidString)"
    }

    public static let bodyMeasurementEntryRoot = "bodyMeasurementEntry.root"
    public static let bodyMeasurementEntryValueField = "bodyMeasurementEntry.valueField"
    public static let bodyMeasurementEntrySave = "bodyMeasurementEntry.save"
    public static let bodyMeasurementEntryUnitToggle = "bodyMeasurementEntry.unitToggle"

    public static func bodyMeasurementRow(_ id: StableUUID) -> String {
        "bodyMeasurementEntry.row.\(id.rawValue.uuidString)"
    }

    public static let bodyMeasurementDeleteConfirm = "bodyMeasurementEntry.deleteConfirm"
    public static let bodyMeasurementDeleteAll = "bodyMeasurementEntry.deleteAll"
    public static let bodyMeasurementDeleteAllConfirm = "bodyMeasurementEntry.deleteAllConfirm"

    public static let trendsRoot = "trends.root"
    public static let trendsFilterDateRange = "trends.filterDateRange"
    public static let trendsFilterFocus = "trends.filterFocus"
    public static let trendsFilterExercise = "trends.filterExercise"
    public static let trendsNoMatches = "trends.noMatches"
    public static let trendsComparisonSection = "trends.comparisonSection"
    public static let trendsExerciseTrendSection = "trends.exerciseTrendSection"
    public static let trendsMetricPicker = "trends.metricPicker"
    public static let trendsPersonalRecordSection = "trends.personalRecordSection"
    public static let trendsTabPicker = "trends.tabPicker"
    public static let trendsAssistedBadge = "trends.assistedBadge"

    public static let coursePackageEditorRoot = "coursePackageEditor.root"
    public static let coursePackageEditorName = "coursePackageEditor.name"
    public static let coursePackageEditorTotalCredits = "coursePackageEditor.totalCredits"
    public static let coursePackageEditorSave = "coursePackageEditor.save"

    public static let manualAdjustmentRoot = "manualAdjustment.root"
    public static let manualAdjustmentDirection = "manualAdjustment.direction"
    public static let manualAdjustmentAmount = "manualAdjustment.amount"
    public static let manualAdjustmentReason = "manualAdjustment.reason"
    public static let manualAdjustmentSave = "manualAdjustment.save"

    public static let creditTrailRoot = "creditTrail.root"

    public static func creditTrailRow(_ id: StableUUID) -> String {
        "creditTrail.row.\(id.rawValue.uuidString)"
    }

    public static let detailRoot = "studentDetail.root"
    public static let detailStartTraining = "studentDetail.startTraining"
    public static let detailContinueTraining = "studentDetail.continueTraining"
    public static let detailRecentTraining = "studentDetail.recentTraining"
    public static let detailHistory = "studentDetail.history"
    public static let detailNotesFold = "studentDetail.injuryNotesFold"
    public static let detailNotesBody = "studentDetail.injuryNotesBody"
    public static let detailMore = "studentDetail.more"
    public static let detailArchive = "studentDetail.archive"
    public static let detailRestore = "studentDetail.restore"
    public static let detailDelete = "studentDetail.delete"
    public static let detailBackup = "studentDetail.backup"
    public static let detailArchivedStatus = "studentDetail.archivedStatus"
    public static let detailCoursePackages = "studentDetail.coursePackages"
    public static let detailNextClass = "studentDetail.nextClass"
    public static let detailBodyData = "studentDetail.bodyData"
    public static let detailTrends = "studentDetail.trends"

    public static let archiveConfirm = "archive.confirm"
    public static let deleteName = "deleteStudent.confirmName"
    public static let deleteConfirm = "deleteStudent.confirm"
    public static let deleteBlocked = "deleteStudent.blocked"
    public static let deleteBackup = "deleteStudent.backup"

    public static let activeSessionRoot = "activeSession.root"
    public static let activeSessionAddExercise = "activeSession.addExercise"
    public static let activeSessionExerciseName = "activeSession.exerciseName"
    public static let activeSessionModeWeightReps = "activeSession.mode.weightReps"
    public static let activeSessionModeReps = "activeSession.mode.reps"
    public static let activeSessionModeDuration = "activeSession.mode.duration"
    public static let activeSessionModeCardio = "activeSession.mode.cardio"
    public static let activeSessionSaveExercise = "activeSession.saveExercise"
    public static let activeSessionMoveToSection = "activeSession.moveToSection"
    public static let activeSessionDeleteExercise = "activeSession.deleteExercise"
    public static let activeSessionDeleteExerciseConfirm = "activeSession.deleteExerciseConfirm"
    public static let activeSessionWeight = "activeSession.weight"
    public static let activeSessionWeightDecrement = "activeSession.weight.decrement"
    public static let activeSessionWeightIncrement = "activeSession.weight.increment"
    public static let activeSessionWeightStepHint = "activeSession.weightStepHint"
    public static let activeSessionReps = "activeSession.reps"
    public static let activeSessionRepsDecrement = "activeSession.reps.decrement"
    public static let activeSessionRepsIncrement = "activeSession.reps.increment"
    public static let activeSessionDuration = "activeSession.duration"
    public static let activeSessionDistance = "activeSession.distance"
    public static let activeSessionSpeed = "activeSession.speed"
    public static let activeSessionResistance = "activeSession.resistance"
    public static let activeSessionLeft = "activeSession.left"
    public static let activeSessionRight = "activeSession.right"
    public static let activeSessionConfirmSet = "activeSession.confirmSet"
    public static let activeSessionSaveSetEdit = "activeSession.saveSetEdit"
    public static let activeSessionCancelSetEdit = "activeSession.cancelSetEdit"
    public static let activeSessionStats = "activeSession.stats"
    public static let activeSessionFinish = "activeSession.finish"
    public static let activeSessionRest = "activeSession.rest"
    public static let activeSessionRestRemaining = "activeSession.rest.remaining"
    public static let activeSessionRestMinus = "activeSession.rest.minus"
    public static let activeSessionRestPlus = "activeSession.rest.plus"
    public static let activeSessionRestSkip = "activeSession.rest.skip"
    public static let activeSessionRestEnded = "activeSession.rest.ended"
    public static let activeSessionRestClose = "activeSession.rest.close"
    public static let activeSessionAbandonConfirm = "activeSession.abandonConfirm"
    public static let activeSessionDiscardDrafts = "activeSession.discardDrafts"
    public static let activeSessionReturnToDrafts = "activeSession.returnToDrafts"
    public static let activeSessionCompletedStatus = "activeSession.completedStatus"
    public static let activeSessionEmptyHint = "activeSession.emptyHint"
    public static let activeSessionSaveStatusSaving = "activeSession.saveStatus.saving"
    public static let activeSessionSaveStatusSaved = "activeSession.saveStatus.saved"
    public static let activeSessionSaveStatusFailed = "activeSession.saveStatus.failed"
    public static let activeSessionRetry = "activeSession.retry"
    public static let activeSessionFinishBlocked = "activeSession.finishBlocked"
    public static let activeSessionDurationReview = "activeSession.durationReview"
    public static let activeSessionDurationValue = "activeSession.durationValue"
    public static let activeSessionDurationConfirm = "activeSession.durationConfirm"
    public static let activeSessionSaveExerciseToLibrary = "activeSession.saveExerciseToLibrary"
    public static let activeSessionExerciseNameConflict = "activeSession.exerciseNameConflict"

    public static func activeSessionCatalogRow(_ id: StableExerciseID) -> String {
        "activeSession.catalogRow.\(id.rawValue)"
    }

    public static let exerciseLibraryEntry = "exerciseLibrary.entry"
    public static let exerciseLibraryRoot = "exerciseLibrary.root"
    public static let exerciseLibrarySearch = "exerciseLibrary.search"
    public static let exerciseLibraryAddCustom = "exerciseLibrary.addCustom"
    public static let exerciseLibraryShowHidden = "exerciseLibrary.showHidden"
    public static let exerciseLibraryFilter = "exerciseLibrary.filter"
    public static let exerciseLibraryConflict = "exerciseLibrary.conflict"
    public static let exerciseLibraryMuscleAll = "exerciseLibrary.muscle.all"
    public static let exerciseLibraryEquipmentAll = "exerciseLibrary.equipment.all"

    public static func exerciseLibraryMuscle(_ group: String) -> String {
        "exerciseLibrary.muscle.\(group)"
    }

    public static func exerciseLibraryEquipment(_ group: String) -> String {
        "exerciseLibrary.equipment.\(group)"
    }

    public static func exerciseLibrarySection(_ id: String) -> String {
        "exerciseLibrary.section.\(id)"
    }

    public static func exerciseLibraryFavorite(_ id: StableExerciseID) -> String {
        "exerciseLibrary.favorite.\(id.rawValue)"
    }

    public static func exerciseLibraryHide(_ id: StableExerciseID) -> String {
        "exerciseLibrary.hide.\(id.rawValue)"
    }

    public static func exerciseLibraryAssisted(_ id: StableExerciseID) -> String {
        "exerciseLibrary.assisted.\(id.rawValue)"
    }

    public static func exerciseLibraryRow(_ id: StableExerciseID) -> String {
        "exerciseLibrary.row.\(id.rawValue)"
    }

    public static let customExerciseRoot = "customExercise.root"
    public static let customExerciseName = "customExercise.name"
    public static let customExerciseModeWeightReps = "customExercise.mode.weightReps"
    public static let customExerciseModeReps = "customExercise.mode.reps"
    public static let customExerciseModeDuration = "customExercise.mode.duration"
    public static let customExerciseSave = "customExercise.save"
    public static let customExerciseArchive = "customExercise.archive"
    public static let customExerciseRestore = "customExercise.restore"

    public static func exerciseAt(_ index: Int) -> String {
        "activeSession.exercise.at.\(index)"
    }

    public static func exerciseLastReference(_ index: Int) -> String {
        "activeSession.exercise.last.\(index)"
    }

    public static func exerciseMode(_ index: Int) -> String {
        "activeSession.exercise.mode.\(index)"
    }

    public static func setAt(_ index: Int) -> String {
        "activeSession.set.at.\(index)"
    }

    public static func setState(_ state: SetRecordingState) -> String {
        "activeSession.setState.\(state.rawValue)"
    }

    public static func setConfirmAt(_ index: Int) -> String {
        "activeSession.set.confirm.at.\(index)"
    }

    public static func setEditAt(_ index: Int) -> String {
        "activeSession.set.edit.at.\(index)"
    }

    public static func setDeleteAt(_ index: Int) -> String {
        "activeSession.set.delete.at.\(index)"
    }

    public static let sessionSummaryRoot = "sessionSummary.root"
    public static let sessionSummaryFocus = "sessionSummary.focus"
    public static let sessionSummaryPrivateNote = "sessionSummary.privateNote"
    public static let sessionSummaryStudentSummary = "sessionSummary.studentSummary"
    public static let sessionSummaryDuration = "sessionSummary.duration"
    public static let sessionSummaryCompletedSets = "sessionSummary.completedSets"
    public static let sessionSummarySkipShare = "sessionSummary.skipShare"
    public static let sessionSummaryGenerateReport = "sessionSummary.generateReport"

    public static let historyRoot = "history.root"
    public static func historyRow(_ index: Int) -> String {
        "history.row.\(index)"
    }

    public static let sessionDetailRoot = "sessionDetail.root"
    public static let sessionDetailEdit = "sessionDetail.edit"
    public static let sessionDetailGenerateReport = "sessionDetail.generateReport"
    public static let sessionDetailReportStale = "sessionDetail.reportStale"
    public static let sessionDetailHandedToSystem = "sessionDetail.handedToSystem"
    public static let sessionDetailCreditNote = "sessionDetail.creditNote"
    public static func historyCreditNote(_ index: Int) -> String {
        "history.creditNote.\(index)"
    }
    public static let sessionDetailReadonly = "sessionDetail.readonly"
    public static let sessionDetailSaveAsTemplate = "sessionDetail.saveAsTemplate"
    public static let sessionDetailSaveAsTemplateName = "sessionDetail.saveAsTemplateName"
    public static let sessionDetailSaveAsTemplateConfirm = "sessionDetail.saveAsTemplateConfirm"

    public static let sessionEditRoot = "sessionEdit.root"
    public static let sessionEditFocus = "sessionEdit.focus"
    public static let sessionEditSave = "sessionEdit.save"

    public static let shareReportModules = "shareReport.modules"
    public static let shareReportVolumeToggle = "shareReport.volumeToggle"
    public static let shareReportPreview = "shareReport.preview"
    public static let shareReportShare = "shareReport.share"
    public static let shareReportRetry = "shareReport.retry"
    public static let shareReportClose = "shareReport.close"
    public static let shareReportGenerateCard = "shareReport.generateCard"
    public static let shareReportPersonalBestToggle = "shareReport.personalBestToggle"
    public static let shareReportNotSentStatus = "shareReport.notSentStatus"
    public static let shareReportHandedOffStatus = "shareReport.handedOffStatus"

    public static let backupRoot = "backup.root"
    public static let backupPassword = "backup.password"
    public static let backupPasswordConfirm = "backup.passwordConfirm"
    public static let backupPasswordHint = "backup.passwordHint"
    public static let backupExport = "backup.export"
    public static let backupExportStatus = "backup.exportStatus"
    public static let backupRetry = "backup.retry"
    public static let restoreRoot = "restore.root"
    public static let restorePickFile = "restore.pickFile"
    public static let restoreWarning = "restore.warning"
    public static let restoreSuggestBackup = "restore.suggestBackup"
    public static let restorePassword = "restore.password"
    public static let restoreConfirm = "restore.confirm"
    public static let restoreRetry = "restore.retry"
    public static let restoreFailed = "restore.failed"
    public static let restoreSucceeded = "restore.succeeded"

    public static func studentRow(_ id: StableUUID) -> String {
        "studentList.row.\(id.rawValue.uuidString)"
    }

    public static func sexIdentifier(_ sex: StudentSex) -> String {
        switch sex {
        case .male: return editorSexMale
        case .female: return editorSexFemale
        case .other: return editorSexOther
        case .undisclosed: return editorSexUndisclosed
        }
    }
}

public enum StudentSexPresentation {
    public static func title(_ sex: StudentSex) -> String {
        switch sex {
        case .male: return String(localized: "student.sex.male")
        case .female: return String(localized: "student.sex.female")
        case .other: return String(localized: "student.sex.other")
        case .undisclosed: return String(localized: "student.sex.undisclosed")
        }
    }

    public static func symbolName(_ sex: StudentSex) -> String {
        switch sex {
        case .male: return "triangle"
        case .female: return "circle"
        case .other: return "diamond"
        case .undisclosed: return "minus"
        }
    }
}
