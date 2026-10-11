import SwiftUI

/// M2-15 趋势与个人最佳 (T048): exercise row (opens a picker), 重量 / 次数 / 容量 switch, the
/// shared trend line, and personal bests in the 32 row style. Everything is computed live from
/// the archive's own training records (D-009).
struct ArchiveTrendsView: View {
    private enum Metric: String, CaseIterable {
        case weight
        case reps
        case volume

        var title: String {
            switch self {
            case .weight: return String(localized: "trends.metric.weight")
            case .reps: return String(localized: "trends.metric.reps")
            case .volume: return String(localized: "trends.metric.volume")
            }
        }

        func value(_ point: Comparison.SetTrendPoint) -> DecimalValue? {
            switch self {
            case .weight: return point.maxWeight
            case .reps: return point.bestReps
            case .volume: return point.volume
            }
        }
    }

    let content: ArchiveViewerContent
    @ObservedObject var model: ArchiveViewerModel

    @State private var selectedKey: String?
    @State private var metric: Metric = .weight
    @State private var isPickerPresented = false

    private var entries: [ArchiveExerciseEntry] {
        (try? content.trendExercises()) ?? []
    }

    private var selected: ArchiveExerciseEntry? {
        entries.first { $0.key == selectedKey } ?? entries.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: String(localized: "archive.export.item.trends"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveTrendsBack)
                )
                VStack(spacing: 0) {
                    FCListRowDivider()
                    FCLabelValueRow(
                        label: String(localized: "archive.viewer.trends.exercise"),
                        value: selected.map(ArchiveViewerPresentation.exerciseName) ?? "",
                        action: { isPickerPresented = true }
                    )
                    .accessibilityIdentifier(FCAccessibilityID.archiveTrendsExercise)
                    FCListRowDivider()
                }
                if let selected {
                    trend(for: selected)
                }
                personalBests
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .fcBottomSheet(isPresented: $isPickerPresented) {
            FCBottomSheet(title: String(localized: "archive.viewer.trends.exercise")) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries, id: \.key) { entry in
                            FCActionRow(
                                title: ArchiveViewerPresentation.exerciseName(entry),
                                note: entry.key == selected?.key ? String(localized: "history.filter.selected") : nil
                            ) {
                                selectedKey = entry.key
                                isPickerPresented = false
                            }
                            FCListRowDivider()
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveTrendsRoot)
    }

    // MARK: Trend

    @ViewBuilder
    private func trend(for entry: ArchiveExerciseEntry) -> some View {
        let modes = content.recordModes(forExerciseKey: entry.key)
        let mode = modes.first ?? .weightReps
        let points = (try? content.trend(forExerciseKey: entry.key, recordMode: mode)) ?? []
        let converter = model.converter
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            if entry.isAssisted {
                Text(String(localized: "trends.assistedBadge"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.statusWarning)
            }
            if mode == .weightReps {
                FCSegmentedSwitch(
                    options: Metric.allCases.map { .init(id: $0.rawValue, title: $0.title) },
                    selection: Binding(get: { metric.rawValue }, set: { metric = Metric(rawValue: $0) ?? metric })
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "trends.metricPickerLabel"))
                .accessibilityIdentifier(FCAccessibilityID.archiveTrendsMetric)
            }
            switch Comparison.TrendSampleDensity.classify(points) {
            case .empty:
                Text(String(localized: "trends.exerciseTrendEmpty"))
                    .foregroundStyle(FCSemanticColors.textSecondary)
            case .single:
                Text(String(localized: "trends.exerciseTrendSingleHint"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            case .sparse(let shown):
                chart(shown, mode: mode, dashed: true, converter: converter)
            case .sufficient(let shown):
                chart(shown, mode: mode, dashed: false, converter: converter)
            }
        }
    }

    @ViewBuilder
    private func chart(
        _ points: [Comparison.SetTrendPoint], mode: RecordMode, dashed: Bool, converter: ArchiveDisplayConverter
    ) -> some View {
        if mode == .weightReps {
            let weightUnit = converter.settings.weightUnit.rawValue
            let unit = metric == .reps ? String(localized: "archive.viewer.trends.repsUnit") : weightUnit
            TrendLineChart(
                points: points, metricLabel: metric.title, unit: unit, dashed: dashed,
                value: { point in
                    guard let raw = metric.value(point) else { return nil }
                    let shown = metric == .reps ? raw : converter.weight(raw, storedUnit: .kilograms).value
                    return Double(shown.canonicalString)
                })
            if metric == .volume {
                Text(String(localized: "trends.volumeCaption"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        } else {
            // Other record modes have no weight axis: the best value per record below covers them.
            EmptyView()
        }
    }

    // MARK: Personal bests

    @ViewBuilder
    private var personalBests: some View {
        let bests = personalBestRows()
        if !bests.isEmpty {
            VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                FCSectionLabel(String(localized: "history.pb.title"))
                VStack(spacing: 0) {
                    FCListRowDivider()
                    ForEach(bests, id: \.id) { row in
                        PersonalBestRowView(
                            name: row.name, kind: row.kind, value: row.value, day: row.day, detail: row.detail)
                        FCListRowDivider()
                    }
                }
            }
        }
    }

    private struct BestRow {
        let id: String
        let name: String
        let kind: String
        let value: String
        let day: String?
        let detail: String?
    }

    private func personalBestRows() -> [BestRow] {
        var rows: [BestRow] = []
        for entry in entries {
            for mode in content.recordModes(forExerciseKey: entry.key) {
                guard let records = try? content.personalRecords(forExerciseKey: entry.key, recordMode: mode),
                    let row = ArchiveViewerPresentation.personalBestRow(
                        name: ArchiveViewerPresentation.exerciseName(entry),
                        records: records,
                        dayOf: { id in
                            content.sessionKey(for: id).flatMap(content.session(key:)).map {
                                ArchiveExportPresentation.monthDay($0.localDate)
                            }
                        },
                        converter: model.converter)
                else { continue }
                rows.append(
                    BestRow(
                        id: "\(entry.key).\(mode.rawValue)", name: ArchiveViewerPresentation.exerciseName(entry),
                        kind: row.kind, value: row.value, day: row.day, detail: row.detail))
            }
        }
        return rows
    }
}
