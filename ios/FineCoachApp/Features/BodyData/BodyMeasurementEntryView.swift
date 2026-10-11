import SwiftUI

/// Records/edits today's value for one metric, and shows its history
/// (T039). Re-entering on the same local day EDITS that day's existing
/// value rather than adding a duplicate (M1B-FR-025/D-005) -- this view
/// surfaces that explicitly via `overwriteHint` rather than hiding it.
@MainActor
final class BodyMeasurementEntryViewModel: ObservableObject {
    @Published var metric: BodyMetricDefinition?
    @Published var history: [BodyMeasurement] = []
    @Published var valueText = ""
    @Published var unitText = ""
    @Published var errorMessage: String?
    @Published var pendingDeleteID: StableUUID?
    /// Confirmation gate for "clear all records" (a full-history delete for
    /// this metric) -- mirrors `pendingDeleteID`'s single-row confirmation
    /// pattern, just at metric scope.
    @Published var showingDeleteAllConfirm = false
    /// Confirmation gate for permanently deleting this custom metric (T069k:
    /// moved here from a long-press-only menu on the list row, now behind a
    /// visible "…" menu and a confirmation).
    @Published var showingDeleteMetricConfirm = false
    /// Set once the custom metric itself is deleted, so the view pops back.
    @Published var didDeleteMetric = false
    /// Coach's current display-unit choice for THIS metric's unit family
    /// (M1B-FR-025) -- only meaningful when `metric.kind == .builtIn` and
    /// `unitRuleKind` is `.weight`/`.length`; irrelevant otherwise. Seeded
    /// from -- and persisted back to -- `unitPreferences` on change.
    @Published var weightDisplayUnit: BuiltInUnitConversion.WeightDisplayUnit
    @Published var lengthDisplayUnit: BuiltInUnitConversion.LengthDisplayUnit

    let studentID: StableUUID
    let metricID: StableUUID
    private let useCases: BodyDataUseCases
    private let unitPreferences: BodyDataUnitPreferences

    init(
        studentID: StableUUID,
        metricID: StableUUID,
        useCases: BodyDataUseCases,
        unitPreferences: BodyDataUnitPreferences = .shared
    ) {
        self.studentID = studentID
        self.metricID = metricID
        self.useCases = useCases
        self.unitPreferences = unitPreferences
        self.weightDisplayUnit = unitPreferences.weightUnit
        self.lengthDisplayUnit = unitPreferences.lengthUnit
    }

    /// Whether today already has a recorded value -- if so, saving EDITS it
    /// rather than creating a second row for the same day.
    var todaysMeasurement: BodyMeasurement? {
        guard let today = history.map(\.localCalendarDay).max() else { return nil }
        return history.first { $0.localCalendarDay == today }
    }

    var isCustomMetric: Bool { metric?.kind == .custom }

    var isBuiltInWeight: Bool { metric?.kind == .builtIn && metric?.unitRuleKind == .weight }
    var isBuiltInLength: Bool { metric?.kind == .builtIn && metric?.unitRuleKind == .length }

    func setWeightDisplayUnit(_ unit: BuiltInUnitConversion.WeightDisplayUnit) {
        weightDisplayUnit = unit
        unitPreferences.weightUnit = unit
    }

    func setLengthDisplayUnit(_ unit: BuiltInUnitConversion.LengthDisplayUnit) {
        lengthDisplayUnit = unit
        unitPreferences.lengthUnit = unit
    }

    /// Converts a canonical `BodyMeasurement.value` into the currently
    /// selected display unit for history rows -- built-in weight/length only;
    /// percent and custom metrics show their stored value/unit unchanged
    /// (M1B-FR-025).
    func displayValue(for measurement: BodyMeasurement) -> String {
        guard let metric, metric.kind == .builtIn else {
            return "\(measurement.value.canonicalString) \(measurement.enteredUnit)"
        }
        switch metric.unitRuleKind {
        case .weight:
            let converted =
                (try? BuiltInUnitConversion.weight(canonicalKilograms: measurement.value, displayedAs: weightDisplayUnit))
                ?? measurement.value
            return "\(converted.canonicalString) \(weightDisplayUnit.rawValue)"
        case .length:
            let converted =
                (try? BuiltInUnitConversion.length(canonicalCentimeters: measurement.value, displayedAs: lengthDisplayUnit))
                ?? measurement.value
            return "\(converted.canonicalString) \(lengthDisplayUnit.rawValue)"
        case .percent, .customUnit:
            return "\(measurement.value.canonicalString) \(measurement.enteredUnit)"
        }
    }

    /// Turns what the coach typed in `valueText` -- entered WHILE the UI was
    /// displaying in the current `weightDisplayUnit`/`lengthDisplayUnit` --
    /// into the canonical value+unit pair to actually store (M1B-FR-025):
    /// built-ins always persist in their fixed canonical unit; percent and
    /// custom metrics pass `valueText`/`unitText` through unchanged.
    private func canonicalInputForSave() throws -> (value: String, enteredUnit: String) {
        guard let metric, metric.kind == .builtIn else {
            return (valueText, unitText)
        }
        switch metric.unitRuleKind {
        case .weight:
            let entered = try DecimalValue(valueText)
            let canonical = try BuiltInUnitConversion.canonicalKilograms(fromDisplayed: entered, unit: weightDisplayUnit)
            return (canonical.canonicalString, metric.currentUnit)
        case .length:
            let entered = try DecimalValue(valueText)
            let canonical = try BuiltInUnitConversion.canonicalCentimeters(fromDisplayed: entered, unit: lengthDisplayUnit)
            return (canonical.canonicalString, metric.currentUnit)
        case .percent, .customUnit:
            return (valueText, unitText)
        }
    }

    func reload() async {
        do {
            let metrics = try await useCases.metrics(studentID: studentID)
            metric = metrics.first { $0.id == metricID }
            history = try await useCases.history(studentID: studentID, metricID: metricID).sorted {
                $0.localCalendarDay > $1.localCalendarDay
            }
            if unitText.isEmpty {
                unitText = metric?.currentUnit ?? ""
            }
            errorMessage = nil
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyMeasurementEntry.error.generic")
        }
    }

    func save() async {
        do {
            let (value, enteredUnit) = try canonicalInputForSave()
            _ = try await useCases.recordMeasurement(
                studentID: studentID,
                metricID: metricID,
                value: value,
                enteredUnit: enteredUnit
            )
            valueText = ""
            await reload()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyMeasurementEntry.error.generic")
        }
    }

    func confirmDelete(_ id: StableUUID) async {
        do {
            try await useCases.deleteMeasurement(id: id)
            pendingDeleteID = nil
            await reload()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyMeasurementEntry.error.generic")
        }
    }

    /// 停用 / 恢复 for a custom metric (M1B-FR-023); archived metrics keep
    /// their history reachable.
    func toggleArchive() async {
        guard let metric, metric.kind == .custom else { return }
        do {
            if metric.lifecycle == .active {
                _ = try await useCases.archiveCustomMetric(id: metric.id)
            } else {
                _ = try await useCases.restoreCustomMetric(id: metric.id)
            }
            await reload()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyMeasurementEntry.error.generic")
        }
    }

    /// Deletion is only possible with zero recorded measurements
    /// (M1B-FR-023/D-009) -- `deleteCustomMetricIfUnused` counts live and
    /// refuses otherwise; this surfaces that refusal as a real message
    /// rather than a silent no-op.
    func confirmDeleteMetric() async {
        showingDeleteMetricConfirm = false
        do {
            try await useCases.deleteCustomMetricIfUnused(id: metricID)
            didDeleteMetric = true
        } catch DomainError.conflict {
            errorMessage = String(localized: "bodyData.deleteBlocked")
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyMeasurementEntry.error.generic")
        }
    }

    /// Clears every recorded measurement for this metric (with the coach
    /// having already confirmed via `showingDeleteAllConfirm`). Never
    /// touches the metric definition itself -- if this metric has zero
    /// other references, the coach can now delete it from this screen's "…"
    /// menu (`deleteCustomMetricIfUnused` re-validates the count).
    func confirmDeleteAll() async {
        do {
            try await useCases.deleteAllMeasurements(studentID: studentID, metricID: metricID)
            showingDeleteAllConfirm = false
            await reload()
        } catch {
            showingDeleteAllConfirm = false
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyMeasurementEntry.error.generic")
        }
    }
}

struct BodyMeasurementEntryView: View {
    @StateObject private var viewModel: BodyMeasurementEntryViewModel
    @Environment(\.dismiss) private var dismiss

    init(studentID: StableUUID, metricID: StableUUID, useCases: BodyDataUseCases) {
        _viewModel = StateObject(
            wrappedValue: BodyMeasurementEntryViewModel(studentID: studentID, metricID: metricID, useCases: useCases)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.statusDestructive)
                }

                if viewModel.todaysMeasurement != nil {
                    Text(String(localized: "bodyMeasurementEntry.overwriteHint"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }

                FCTextField(String(localized: "bodyMeasurementEntry.valuePlaceholder"), text: $viewModel.valueText)
                    .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryValueField)
                    .keyboardType(.decimalPad)

                if viewModel.isBuiltInWeight {
                    FCSegmentedSwitch(
                        options: BuiltInUnitConversion.WeightDisplayUnit.allCases.map {
                            .init(id: $0.rawValue, title: $0.rawValue)
                        },
                        selection: Binding(
                            get: { viewModel.weightDisplayUnit.rawValue },
                            set: { raw in
                                if let unit = BuiltInUnitConversion.WeightDisplayUnit(rawValue: raw) {
                                    viewModel.setWeightDisplayUnit(unit)
                                }
                            }
                        )
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(String(localized: "bodyMeasurementEntry.displayUnit"))
                    .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryUnitToggle)
                } else if viewModel.isBuiltInLength {
                    FCSegmentedSwitch(
                        options: BuiltInUnitConversion.LengthDisplayUnit.allCases.map {
                            .init(id: $0.rawValue, title: $0.rawValue)
                        },
                        selection: Binding(
                            get: { viewModel.lengthDisplayUnit.rawValue },
                            set: { raw in
                                if let unit = BuiltInUnitConversion.LengthDisplayUnit(rawValue: raw) {
                                    viewModel.setLengthDisplayUnit(unit)
                                }
                            }
                        )
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(String(localized: "bodyMeasurementEntry.displayUnit"))
                    .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryUnitToggle)
                } else {
                    FCTextField(String(localized: "bodyMeasurementEntry.unitPlaceholder"), text: $viewModel.unitText)
                }

                FCButton(title: String(localized: "bodyMeasurementEntry.save")) {
                    Task { await viewModel.save() }
                }
                .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntrySave)

                FCListRowDivider()
                HStack {
                    Text(String(localized: "bodyMeasurementEntry.historySection"))
                        .fcFont(.sectionLabel)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                    Spacer()
                    if !viewModel.history.isEmpty {
                        Button(String(localized: "bodyMeasurementEntry.deleteAll"), role: .destructive) {
                            viewModel.showingDeleteAllConfirm = true
                        }
                        .fcFont(.caption)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementDeleteAll)
                    }
                }

                if viewModel.history.isEmpty {
                    Text(String(localized: "bodyMeasurementEntry.empty"))
                        .foregroundStyle(FCSemanticColors.textSecondary)
                } else {
                    ForEach(viewModel.history) { measurement in
                        historyRow(measurement)
                    }
                }
            }
            .padding(FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(viewModel.metric?.name.value ?? String(localized: "bodyMeasurementEntry.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryRoot)
        .task { await viewModel.reload() }
        .toolbar {
            if viewModel.isCustomMetric {
                ToolbarItem(placement: .topBarTrailing) {
                    metricActionsMenu
                }
            }
        }
        .onChange(of: viewModel.didDeleteMetric) { _, deleted in
            if deleted {
                dismiss()
            }
        }
        .confirmationDialog(
            String(localized: "bodyData.deleteConfirmTitle"),
            isPresented: $viewModel.showingDeleteMetricConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "bodyData.delete"), role: .destructive) {
                Task { await viewModel.confirmDeleteMetric() }
            }
            Button(String(localized: "bodyData.deleteCancel"), role: .cancel) {
                viewModel.showingDeleteMetricConfirm = false
            }
        } message: {
            Text(String(localized: "bodyData.deleteConfirmMessage"))
        }
        .confirmationDialog(
            String(localized: "bodyMeasurementEntry.deleteConfirmTitle"),
            isPresented: Binding(
                get: { viewModel.pendingDeleteID != nil },
                set: { if !$0 { viewModel.pendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "bodyMeasurementEntry.delete"), role: .destructive) {
                if let id = viewModel.pendingDeleteID {
                    Task { await viewModel.confirmDelete(id) }
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementDeleteConfirm)
            Button(String(localized: "bodyMeasurementEntry.cancel"), role: .cancel) {
                viewModel.pendingDeleteID = nil
            }
        } message: {
            Text(String(localized: "bodyMeasurementEntry.deleteConfirmMessage"))
        }
        .confirmationDialog(
            String(localized: "bodyMeasurementEntry.deleteAllConfirmTitle"),
            isPresented: $viewModel.showingDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "bodyMeasurementEntry.deleteAll"), role: .destructive) {
                Task { await viewModel.confirmDeleteAll() }
            }
            .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementDeleteAllConfirm)
            Button(String(localized: "bodyMeasurementEntry.cancel"), role: .cancel) {
                viewModel.showingDeleteAllConfirm = false
            }
        } message: {
            Text(String(localized: "bodyMeasurementEntry.deleteAllConfirmMessage"))
        }
    }

    /// Visible "…" menu for a custom metric's lifecycle actions (CLAUDE.md
    /// "Discoverable affordances": never long-press only).
    private var metricActionsMenu: some View {
        Menu {
            Button(
                viewModel.metric?.lifecycle == .archived
                    ? String(localized: "bodyData.restore")
                    : String(localized: "bodyData.archive")
            ) {
                Task { await viewModel.toggleArchive() }
            }
            Button(String(localized: "bodyData.delete"), role: .destructive) {
                viewModel.showingDeleteMetricConfirm = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(FCSemanticColors.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "bodyData.moreActions"))
    }

    private func historyRow(_ measurement: BodyMeasurement) -> some View {
        BodyMeasurementHistoryRow(
            dateText: measurement.localCalendarDay.canonicalString,
            valueText: viewModel.displayValue(for: measurement)
        ) {
            Button {
                viewModel.pendingDeleteID = measurement.id
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(FCSemanticColors.statusDestructive)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementRow(measurement.id))
    }
}
