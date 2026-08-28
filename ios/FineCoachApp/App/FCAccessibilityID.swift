import Foundation

public enum FCAccessibilityID {
    public static let onboardingTitle = "onboarding.title"
    public static let onboardingLead = "onboarding.lead"
    public static let onboardingLocalRule = "onboarding.local"
    public static let onboardingShareRule = "onboarding.share"
    public static let onboardingStart = "onboarding.start"
    public static let onboardingSkip = "onboarding.skip"

    public static let studentList = "studentList.root"
    public static let studentListAdd = "studentList.add"
    public static let studentListSearch = "studentList.search"
    public static let studentListEmpty = "studentList.empty"
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
    public static let detailArchivedStatus = "studentDetail.archivedStatus"

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
    public static let activeSessionSaveExercise = "activeSession.saveExercise"
    public static let activeSessionMoveUp = "activeSession.moveUp"
    public static let activeSessionMoveDown = "activeSession.moveDown"
    public static let activeSessionDeleteExercise = "activeSession.deleteExercise"
    public static let activeSessionDeleteExerciseConfirm = "activeSession.deleteExerciseConfirm"
    public static let activeSessionAddSet = "activeSession.addSet"
    public static let activeSessionWeight = "activeSession.weight"
    public static let activeSessionReps = "activeSession.reps"
    public static let activeSessionDuration = "activeSession.duration"
    public static let activeSessionSideNone = "activeSession.sideNone"
    public static let activeSessionSideBilateral = "activeSession.sideBilateral"
    public static let activeSessionLeft = "activeSession.left"
    public static let activeSessionRight = "activeSession.right"
    public static let activeSessionConfirmSet = "activeSession.confirmSet"
    public static let activeSessionCopyPrevious = "activeSession.copyPrevious"
    public static let activeSessionCopyLastSame = "activeSession.copyLastSame"
    public static let activeSessionUndoSet = "activeSession.undoSet"
    public static let activeSessionStats = "activeSession.stats"
    public static let activeSessionFinish = "activeSession.finish"
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

    public static let exerciseLibraryEntry = "exerciseLibrary.entry"
    public static let exerciseLibraryRoot = "exerciseLibrary.root"
    public static let exerciseLibrarySearch = "exerciseLibrary.search"
    public static let exerciseLibraryAddCustom = "exerciseLibrary.addCustom"
    public static let exerciseLibraryShowHidden = "exerciseLibrary.showHidden"
    public static let exerciseLibraryConflict = "exerciseLibrary.conflict"

    public static func exerciseLibraryFavorite(_ id: StableExerciseID) -> String {
        "exerciseLibrary.favorite.\(id.rawValue)"
    }

    public static func exerciseLibraryHide(_ id: StableExerciseID) -> String {
        "exerciseLibrary.hide.\(id.rawValue)"
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

    public static func setAt(_ index: Int) -> String {
        "activeSession.set.at.\(index)"
    }

    public static func setState(_ state: SetRecordingState) -> String {
        "activeSession.setState.\(state.rawValue)"
    }

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
