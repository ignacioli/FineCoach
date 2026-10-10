import Foundation

// M2 export module selection (data-model §2, spec §6.2 / M2-FR-007, M2-FR-049, D-005, D-009,
// D-015). Pure Domain: Foundation only, no presentation strings. The UI localizes the group
// titles, item titles and unavailable reasons.

/// The three groups the selection screen presents (M2-FR-049).
public enum ArchiveModuleGroup: CaseIterable, Hashable, Sendable {
    case basicProfile
    case trainingContent
    case bodyData
}

/// One selectable row: the six fixed modules, or one body metric of the student.
public enum ArchiveModuleItem: Hashable, Sendable {
    case displayName
    case sex
    case trainingRecords
    case trends
    case summaries
    case exerciseInfo
    case bodyMetric(StableUUID)

    public var group: ArchiveModuleGroup {
        switch self {
        case .displayName, .sex: return .basicProfile
        case .trainingRecords, .trends, .summaries, .exerciseInfo: return .trainingContent
        case .bodyMetric: return .bodyData
        }
    }
}

public enum ArchiveItemUnavailableReason: Equatable, Sendable {
    /// The student has nothing for this item (D-005).
    case noData
    /// Needs 「训练记录」 selected as well (D-009 trends, D-015 exercise info).
    case requiresTrainingRecords
}

public enum ArchiveItemState: Equatable, Sendable {
    case selected
    case unselected
    case unavailable(ArchiveItemUnavailableReason)

    public var isSelected: Bool { self == .selected }

    public var isSelectable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

/// Derived from the selectable children only; never stored (data-model §2).
public enum ArchiveGroupState: Equatable, Sendable {
    case all
    case partial
    case noneSelected
    /// Every child is unavailable.
    case unavailable
}

/// What the student has, per item. Built from the export source; the counts feed the row
/// captions of M2-02 and the 「无数据」 reasons.
public struct ArchiveModuleAvailability: Equatable, Sendable {
    public struct BodyMetricFacts: Equatable, Sendable {
        public let id: StableUUID
        public let kind: ArchiveBodyMetricKind
        /// Custom metrics only; built-in names come from the app.
        public let name: String?
        public let measurementCount: Int

        public init(id: StableUUID, kind: ArchiveBodyMetricKind, name: String?, measurementCount: Int) {
            self.id = id
            self.kind = kind
            self.name = name
            self.measurementCount = measurementCount
        }
    }

    public let hasDisplayName: Bool
    public let hasSex: Bool
    public let completedSessionCount: Int
    public let earliestSessionDate: LocalDate?
    public let latestSessionDate: LocalDate?
    public let confirmedSetCount: Int
    /// Completed sessions that carry a non-empty student-facing summary.
    public let summaryCount: Int
    /// Archive exercises a training-records export would contain (one-off exercises are
    /// counted per occurrence, D-001).
    public let exerciseCount: Int
    public let bodyMetrics: [BodyMetricFacts]

    public init(
        hasDisplayName: Bool,
        hasSex: Bool,
        completedSessionCount: Int,
        earliestSessionDate: LocalDate?,
        latestSessionDate: LocalDate?,
        confirmedSetCount: Int,
        summaryCount: Int,
        exerciseCount: Int,
        bodyMetrics: [BodyMetricFacts]
    ) {
        self.hasDisplayName = hasDisplayName
        self.hasSex = hasSex
        self.completedSessionCount = completedSessionCount
        self.earliestSessionDate = earliestSessionDate
        self.latestSessionDate = latestSessionDate
        self.confirmedSetCount = confirmedSetCount
        self.summaryCount = summaryCount
        self.exerciseCount = exerciseCount
        self.bodyMetrics = bodyMetrics
    }

    func hasData(_ item: ArchiveModuleItem) -> Bool {
        switch item {
        case .displayName: return hasDisplayName
        case .sex: return hasSex
        case .trainingRecords, .trends, .exerciseInfo: return completedSessionCount > 0
        case .summaries: return summaryCount > 0
        case .bodyMetric(let id):
            return bodyMetrics.first { $0.id == id }.map { $0.measurementCount > 0 } ?? false
        }
    }

    /// Every item the selection screen lists, in display order.
    var allItems: [ArchiveModuleItem] {
        [.displayName, .sex, .trainingRecords, .trends, .summaries, .exerciseInfo]
            + bodyMetrics.map { .bodyMetric($0.id) }
    }
}

/// The Coach's choice for one export flow. A new value is built for every flow with every
/// item switched on (M2-FR-007); nothing is read from or written to earlier exports.
///
/// Items without data, and items whose dependency is not met, are not selectable and count as
/// unselected. The Coach's own on/off intent for a dependent item is kept, so switching
/// 「训练记录」 off and on again restores 「趋势」 and 「动作资料」 as they were.
public struct ArchiveModuleSelection: Equatable, Sendable {
    public let availability: ArchiveModuleAvailability
    private var intent: Set<ArchiveModuleItem>

    /// Fresh default: every item switched on.
    public init(availability: ArchiveModuleAvailability) {
        self.availability = availability
        self.intent = Set(availability.allItems)
    }

    // MARK: Item and group state

    public func state(of item: ArchiveModuleItem) -> ArchiveItemState {
        guard availability.hasData(item) else {
            return .unavailable(.noData)
        }
        if Self.dependsOnTrainingRecords(item), !isTrainingRecordsEffective {
            return .unavailable(.requiresTrainingRecords)
        }
        return intent.contains(item) ? .selected : .unselected
    }

    public func items(in group: ArchiveModuleGroup) -> [ArchiveModuleItem] {
        availability.allItems.filter { $0.group == group }
    }

    public func groupState(_ group: ArchiveModuleGroup) -> ArchiveGroupState {
        let selectable = items(in: group).map(state(of:)).filter(\.isSelectable)
        guard !selectable.isEmpty else {
            return .unavailable
        }
        let selectedCount = selectable.filter(\.isSelected).count
        if selectedCount == selectable.count { return .all }
        return selectedCount == 0 ? .noneSelected : .partial
    }

    // MARK: Mutation

    /// Returns `false` and changes nothing when the item is not selectable.
    @discardableResult
    public mutating func setSelected(_ selected: Bool, item: ArchiveModuleItem) -> Bool {
        guard state(of: item).isSelectable else {
            return false
        }
        if selected { intent.insert(item) } else { intent.remove(item) }
        return true
    }

    /// Switches every item of the group that has data on or off in one step.
    public mutating func setGroup(_ group: ArchiveModuleGroup, selected: Bool) {
        for item in items(in: group) where availability.hasData(item) {
            if selected { intent.insert(item) } else { intent.remove(item) }
        }
    }

    /// The group switch behaviour: everything on unless it already is.
    public mutating func toggleGroup(_ group: ArchiveModuleGroup) {
        setGroup(group, selected: groupState(group) != .all)
    }

    // MARK: Effective result

    /// The modules the export will contain, or `nil` when nothing effective is selected
    /// (then 「预览」 is disabled).
    public var effectiveModules: ArchiveModuleSet? {
        let modules = try? ArchiveModuleSet(
            displayName: state(of: .displayName).isSelected,
            sex: state(of: .sex).isSelected,
            bodyData: !effectiveBodyMetricIDs.isEmpty,
            trainingRecords: isTrainingRecordsEffective,
            trends: state(of: .trends).isSelected,
            summaries: state(of: .summaries).isSelected,
            exerciseInfo: state(of: .exerciseInfo).isSelected
        )
        guard let modules, !modules.isEmpty else {
            return nil
        }
        return modules
    }

    /// Selected body metrics in the availability order; empty means no body data.
    public var effectiveBodyMetricIDs: [StableUUID] {
        availability.bodyMetrics.map(\.id).filter { state(of: .bodyMetric($0)).isSelected }
    }

    public var canPreview: Bool { effectiveModules != nil }

    private var isTrainingRecordsEffective: Bool {
        availability.hasData(.trainingRecords) && intent.contains(.trainingRecords)
    }

    private static func dependsOnTrainingRecords(_ item: ArchiveModuleItem) -> Bool {
        item == .trends || item == .exerciseInfo
    }
}
