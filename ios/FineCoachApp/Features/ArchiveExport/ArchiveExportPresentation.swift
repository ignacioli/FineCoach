import Foundation

// M2 export presentation (T030, T031): pure text derivation for the selection and preview
// pages. No state, no business rules; the rules live in `ArchiveModuleSelection` and
// `ArchiveExportPolicy`. Copy follows design/m2-hifi/implementation-map.md §3.1 / §4.2.

enum ArchiveExportPresentation {
    // MARK: Selection (M2-02)

    static func groupTitle(_ group: ArchiveModuleGroup) -> String {
        switch group {
        case .basicProfile: return String(localized: "archive.export.group.basicProfile")
        case .trainingContent: return String(localized: "archive.export.group.trainingContent")
        case .bodyData: return String(localized: "archive.export.group.bodyData")
        }
    }

    static func itemTitle(_ item: ArchiveModuleItem, availability: ArchiveModuleAvailability) -> String {
        switch item {
        case .displayName: return String(localized: "archive.export.item.displayName")
        case .sex: return String(localized: "archive.export.item.sex")
        case .trainingRecords: return String(localized: "archive.export.item.trainingRecords")
        case .trends: return String(localized: "archive.export.item.trends")
        case .summaries: return String(localized: "archive.export.item.summaries")
        case .exerciseInfo: return String(localized: "archive.export.item.exerciseInfo")
        case .bodyMetric(let id):
            guard let facts = availability.bodyMetrics.first(where: { $0.id == id }) else {
                return ""
            }
            switch facts.kind {
            case .builtIn(let metric):
                return metric.displayName
            case .custom:
                return String(format: String(localized: "archive.export.item.customMetric"), facts.name ?? "")
            }
        }
    }

    static func itemNote(_ item: ArchiveModuleItem, availability: ArchiveModuleAvailability) -> String? {
        switch item {
        case .displayName, .sex:
            return nil
        case .trainingRecords:
            return String(
                format: String(localized: "archive.export.note.trainingRecords"), availability.completedSessionCount)
        case .trends:
            return String(localized: "archive.export.note.trends")
        case .summaries:
            return String(format: String(localized: "archive.export.note.summaries"), availability.summaryCount)
        case .exerciseInfo:
            return String(format: String(localized: "archive.export.note.exerciseInfo"), availability.exerciseCount)
        case .bodyMetric(let id):
            let count = availability.bodyMetrics.first { $0.id == id }?.measurementCount ?? 0
            return String(format: String(localized: "archive.export.note.measurements"), count)
        }
    }

    static func reason(_ reason: ArchiveItemUnavailableReason) -> String {
        switch reason {
        case .noData: return String(localized: "archive.export.reason.noData")
        case .requiresTrainingRecords: return String(localized: "archive.export.reason.requiresTrainingRecords")
        }
    }

    /// The trailing note of a group row: what the group holds, and for body data how many of
    /// the metrics are in (「2 / 3 项指标」).
    static func groupNote(_ group: ArchiveModuleGroup, selection: ArchiveModuleSelection) -> String {
        let availability = selection.availability
        let selectable = selection.items(in: group).filter { selection.state(of: $0).isSelectable }
        switch group {
        case .basicProfile:
            return
                selectable
                .map { itemTitle($0, availability: availability) }
                .joined(separator: String(localized: "archive.export.list.separator"))
        case .trainingContent:
            return String(
                format: String(localized: "archive.export.group.trainingContent.note"),
                availability.completedSessionCount,
                selectable.count
            )
        case .bodyData:
            let selected = selectable.filter { selection.state(of: $0).isSelected }.count
            if selected == selectable.count {
                return String(format: String(localized: "archive.export.group.bodyData.note.all"), selectable.count)
            }
            return String(
                format: String(localized: "archive.export.group.bodyData.note.partial"),
                selected,
                selectable.count
            )
        }
    }

    static func accessibilityKey(_ item: ArchiveModuleItem) -> String {
        switch item {
        case .displayName: return "displayName"
        case .sex: return "sex"
        case .trainingRecords: return "trainingRecords"
        case .trends: return "trends"
        case .summaries: return "summaries"
        case .exerciseInfo: return "exerciseInfo"
        case .bodyMetric(let id): return "bodyMetric.\(id.rawValue.uuidString)"
        }
    }

    static func accessibilityKey(_ group: ArchiveModuleGroup) -> String {
        switch group {
        case .basicProfile: return "basicProfile"
        case .trainingContent: return "trainingContent"
        case .bodyData: return "bodyData"
        }
    }

    // MARK: Dates

    static func fullDate(_ date: LocalDate) -> String {
        String(format: String(localized: "archive.export.date.full"), date.year, date.month, date.day)
    }

    static func monthDay(_ date: LocalDate) -> String {
        String(format: String(localized: "archive.export.date.monthDay"), date.month, date.day)
    }

    /// 「2026年3月2日 – 9月25日」: the end drops the year when it matches the start.
    static func dateRange(from start: LocalDate, to end: LocalDate) -> String {
        if start == end {
            return fullDate(start)
        }
        let endText = start.year == end.year ? monthDay(end) : fullDate(end)
        return String(format: String(localized: "archive.export.date.range"), fullDate(start), endText)
    }

    /// A short date for list meta; the year appears only when it differs from `referenceYear`.
    static func shortDate(_ date: LocalDate, referenceYear: Int) -> String {
        date.year == referenceYear ? monthDay(date) : fullDate(date)
    }
}

/// What the preview page shows, derived from the snapshot the archive will carry (M2-FR-008).
struct ArchivePreviewModel {
    struct Entry: Identifiable, Equatable {
        let id: Int
        /// Free text, verbatim.
        let text: String
        let meta: String
    }

    struct MetricLine: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        /// Custom names are free text and render as a list row.
        let isCustom: Bool
    }

    let modules: ArchiveModuleSet
    let displayName: String?
    let sexTitle: String?
    let sessionCount: Int
    let range: String?
    let exerciseCount: Int
    let builtInExerciseCount: Int
    let customExercises: [Entry]
    /// Session section names the archive carries, deduplicated, in first-seen order. Empty
    /// unless training records are selected (the policy writes no sessions otherwise).
    let sectionNames: [String]
    let summaries: [Entry]
    let metrics: [MetricLine]

    init(snapshot: ArchiveSnapshot) {
        modules = snapshot.manifest.modules
        displayName = snapshot.student?.displayName
        sexTitle = snapshot.student?.sex.map(StudentSexPresentation.title)
        sessionCount = snapshot.sessions.count
        let dates = snapshot.sessions.map(\.localDate)
        if let first = dates.min(), let last = dates.max() {
            range = ArchiveExportPresentation.dateRange(from: first, to: last)
        } else {
            range = nil
        }
        exerciseCount = snapshot.exercises.count
        builtInExerciseCount = snapshot.exercises.filter { $0.kind == .builtIn }.count
        customExercises = snapshot.exercises.enumerated().compactMap { index, exercise in
            guard exercise.kind != .builtIn, let info = exercise.info else {
                return nil
            }
            let meta =
                exercise.kind == .custom
                ? String(localized: "archive.export.exercise.custom")
                : String(localized: "archive.export.exercise.oneOff")
            return Entry(id: index, text: info.name, meta: meta)
        }
        var seenSectionNames = Set<String>()
        sectionNames = snapshot.sessions.flatMap(\.sections).compactMap(\.name).filter {
            !$0.isEmpty && seenSectionNames.insert($0).inserted
        }
        let referenceYear = (dates + snapshot.summaries.map(\.localDate)).max()?.year ?? 0
        summaries = snapshot.summaries
            .sorted { $0.localDate > $1.localDate }
            .enumerated()
            .map {
                Entry(
                    id: $0.offset,
                    text: $0.element.text,
                    meta: ArchiveExportPresentation.shortDate($0.element.localDate, referenceYear: referenceYear)
                )
            }
        let measurementCounts = Dictionary(grouping: snapshot.bodyMeasurements, by: \.metricKey).mapValues(\.count)
        metrics = snapshot.bodyMetrics.map { metric in
            let count = measurementCounts[metric.key] ?? 0
            let unit: String
            let title: String
            switch metric.kind {
            case .builtIn(let builtIn):
                title = builtIn.displayName
                unit = builtIn.canonicalUnit
            case .custom:
                title = metric.name ?? ""
                unit = metric.unit ?? ""
            }
            let measurements = String(format: String(localized: "archive.export.note.measurements"), count)
            return MetricLine(
                id: metric.key,
                title: title,
                detail: String(format: String(localized: "archive.export.preview.metricDetail"), measurements, unit),
                isCustom: metric.kind == .custom
            )
        }
    }

    var showsBasicProfile: Bool { modules.displayName || modules.sex }
}
