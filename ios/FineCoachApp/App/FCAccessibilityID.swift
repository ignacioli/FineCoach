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
