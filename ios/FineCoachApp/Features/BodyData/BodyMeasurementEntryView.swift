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
}

struct BodyMeasurementEntryView: View {
    @StateObject private var viewModel: BodyMeasurementEntryViewModel

    init(studentID: StableUUID, metricID: StableUUID, useCases: BodyDataUseCases) {
        _viewModel = StateObject(
            wrappedValue: BodyMeasurementEntryViewModel(studentID: studentID, metricID: metricID, useCases: useCases)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                if viewModel.todaysMeasurement != nil {
                    Text(String(localized: "bodyMeasurementEntry.overwriteHint"))
                        .font(.footnote)
                        .foregroundStyle(FCSemanticColors.secondaryText)
                }

                FCTextField(String(localized: "bodyMeasurementEntry.valuePlaceholder"), text: $viewModel.valueText)
                    .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryValueField)
                    .keyboardType(.decimalPad)

                if viewModel.isBuiltInWeight {
                    Picker(
                        String(localized: "bodyMeasurementEntry.displayUnit"),
                        selection: Binding(
                            get: { viewModel.weightDisplayUnit },
                            set: { viewModel.setWeightDisplayUnit($0) }
                        )
                    ) {
                        ForEach(BuiltInUnitConversion.WeightDisplayUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryUnitToggle)
                } else if viewModel.isBuiltInLength {
                    Picker(
                        String(localized: "bodyMeasurementEntry.displayUnit"),
                        selection: Binding(
                            get: { viewModel.lengthDisplayUnit },
                            set: { viewModel.setLengthDisplayUnit($0) }
                        )
                    ) {
                        ForEach(BuiltInUnitConversion.LengthDisplayUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryUnitToggle)
                } else {
                    FCTextField(String(localized: "bodyMeasurementEntry.unitPlaceholder"), text: $viewModel.unitText)
                }

                FCButton(title: String(localized: "bodyMeasurementEntry.save")) {
                    Task { await viewModel.save() }
                }
                .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntrySave)

                Divider()
                Text(String(localized: "bodyMeasurementEntry.historySection"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FCSemanticColors.secondaryText)

                if viewModel.history.isEmpty {
                    Text(String(localized: "bodyMeasurementEntry.empty"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                } else {
                    ForEach(viewModel.history) { measurement in
                        historyRow(measurement)
                    }
                }
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.background)
        .navigationTitle(viewModel.metric?.name.value ?? String(localized: "bodyMeasurementEntry.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementEntryRoot)
        .task { await viewModel.reload() }
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
    }

    private func historyRow(_ measurement: BodyMeasurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                Text(measurement.localCalendarDay.canonicalString)
                    .font(.body.weight(.medium))
                Text(viewModel.displayValue(for: measurement))
                    .foregroundStyle(FCSemanticColors.secondaryText)
            }
            Spacer()
            Button {
                viewModel.pendingDeleteID = measurement.id
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(FCSemanticColors.destructive)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(FCPrimitives.spacingMedium)
        .background(FCSemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium))
        .accessibilityIdentifier(FCAccessibilityID.bodyMeasurementRow(measurement.id))
    }
}
