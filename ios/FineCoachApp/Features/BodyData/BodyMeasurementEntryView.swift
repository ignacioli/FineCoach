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

    let studentID: StableUUID
    let metricID: StableUUID
    private let useCases: BodyDataUseCases

    init(studentID: StableUUID, metricID: StableUUID, useCases: BodyDataUseCases) {
        self.studentID = studentID
        self.metricID = metricID
        self.useCases = useCases
    }

    /// Whether today already has a recorded value -- if so, saving EDITS it
    /// rather than creating a second row for the same day.
    var todaysMeasurement: BodyMeasurement? {
        guard let today = history.map(\.localCalendarDay).max() else { return nil }
        return history.first { $0.localCalendarDay == today }
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
            _ = try await useCases.recordMeasurement(
                studentID: studentID,
                metricID: metricID,
                value: valueText,
                enteredUnit: unitText
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
                FCTextField(String(localized: "bodyMeasurementEntry.unitPlaceholder"), text: $viewModel.unitText)

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
                Text("\(measurement.value.canonicalString) \(measurement.enteredUnit)")
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
