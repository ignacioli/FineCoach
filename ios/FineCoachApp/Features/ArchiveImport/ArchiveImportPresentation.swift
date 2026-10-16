import Foundation

// Pure text derivation for the import pages (M2-08..M2-10) and the viewer's fact rows
// (M2-11, M2-17). Copy follows design/m2-hifi/implementation-map.md §3.2 / §5.

enum ArchiveImportPresentation {
    /// The failure title and message of 导入失败 (§5). `installStateUnavailable` and
    /// `alreadyInstalled` never reach this; the view model routes them elsewhere, and the
    /// remaining cases that cannot be classified use the generic file-invalid copy.
    static func failureMessage(_ failure: ArchiveImportFailure) -> String {
        switch failure {
        case .wrongPasswordOrCorrupted:
            return String(localized: "archive.import.failure.password")
        case .incompatibleVersion:
            return String(localized: "archive.import.failure.version")
        case .invalidArchive, .installStateUnavailable, .alreadyInstalled, .blockedByCoachData,
            .interrupted, .importInProgress:
            return String(localized: "archive.import.failure.invalid")
        }
    }

    /// The reason line of 「无法替换」 (§5). Every line ends with the fact that the installed
    /// archive is unchanged.
    static func replaceFailureMessage(_ failure: ArchiveReplaceFailure) -> String {
        switch failure {
        case .notNewer: return String(localized: "archive.replace.failure.notNewer")
        case .differentSource: return String(localized: "archive.replace.failure.source")
        case .differentStudent: return String(localized: "archive.replace.failure.student")
        case .wrongPasswordOrCorrupted: return String(localized: "archive.replace.failure.password")
        case .incompatibleVersion: return String(localized: "archive.replace.failure.version")
        case .invalidArchive: return String(localized: "archive.replace.failure.invalid")
        case .notInstalled: return String(localized: "archive.replace.failure.notInstalled")
        case .interrupted, .importInProgress, .noPendingReplacement:
            return String(localized: "archive.replace.failure.interrupted")
        }
    }

    /// 「个人训练档案 · 9月25日」 for a file named `FineCoach-档案-YYYYMMDD-HHmm.fcarchive`
    /// (contract §1: the name carries only the time). Any other name is shown as it is.
    static func fileDisplayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        if let range = name.range(of: #"-(\d{4})(\d{2})(\d{2})-\d{4}"#, options: .regularExpression) {
            let digits = name[range].filter(\.isNumber)
            if digits.count == 12, let month = Int(digits.dropFirst(4).prefix(2)),
                let day = Int(digits.dropFirst(6).prefix(2)),
                (1...12).contains(month), (1...31).contains(day)
            {
                return String(format: String(localized: "archive.import.file.nameFormat"), month, day)
            }
        }
        return name
    }

    /// 「2026年9月25日 18:30」 in the device's time zone.
    static func snapshotTime(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: instant)
    }

    /// 「9月25日」 of the snapshot instant in the device's time zone.
    static func snapshotMonthDay(_ instant: Date) -> String {
        let date = LocalDate(date: instant, calendar: .current)
        return ArchiveExportPresentation.monthDay(date)
    }

    static func sourceLine(_ sourceLabel: String) -> String {
        String(format: String(localized: "archive.viewer.source.format"), sourceLabel)
    }

    /// 「训练记录、身体数据、趋势与个人最佳」: what the archive holds, in the home-page order.
    static func contentSummary(_ modules: ArchiveModuleSet) -> String {
        var names: [String] = []
        if modules.displayName || modules.sex { names.append(String(localized: "archive.export.group.basicProfile")) }
        if modules.trainingRecords { names.append(String(localized: "archive.export.item.trainingRecords")) }
        if modules.bodyData { names.append(String(localized: "archive.export.group.bodyData")) }
        if modules.trends { names.append(String(localized: "archive.export.item.trends")) }
        if modules.summaries { names.append(String(localized: "archive.export.item.summaries")) }
        if modules.exerciseInfo { names.append(String(localized: "archive.export.item.exerciseInfo")) }
        return names.joined(separator: String(localized: "archive.export.list.separator"))
    }
}
