import SwiftUI

/// Every metric visible to a Student -- the 8 fixed built-ins plus any
/// custom metrics they've created (T039, M1B-FR-023). Body data may be
/// entirely absent; that renders a real empty state, never fabricated
/// placeholder numbers (M1B-FR-023).
@MainActor
final class BodyDataListViewModel: ObservableObject {
    @Published var metrics: [BodyMetricDefinition] = []
    /// Most-recent recorded value per metric, keyed by `metricID` -- loaded
    /// via a single batch call alongside `metrics` in `reload()`. Metrics
    /// with no recorded measurement are simply absent (no placeholder row).
    @Published var latestByMetric: [StableUUID: BodyMeasurement] = [:]
    @Published var errorMessage: String?
    @Published var showingNewCustomMetric = false
    @Published var newMetricName = ""
    @Published var newMetricUnit = ""
    /// Error from `createCustomMetric()` (most commonly a same-name conflict,
    /// M1B-FR-023), shown INSIDE the new-custom-metric sheet -- `errorMessage`
    /// above renders behind the sheet's modal layer and is invisible while
    /// the sheet is open, so this failure needs its own surfaced state.
    @Published var newMetricErrorMessage: String?

    let studentID: StableUUID
    private let useCases: BodyDataUseCases
    private let unitPreferences: BodyDataUnitPreferences

    init(studentID: StableUUID, useCases: BodyDataUseCases, unitPreferences: BodyDataUnitPreferences = .shared) {
        self.studentID = studentID
        self.useCases = useCases
        self.unitPreferences = unitPreferences
    }

    var builtInMetrics: [BodyMetricDefinition] {
        metrics.filter { $0.kind == .builtIn }
    }

    /// Active custom metrics first, then archived (archived still shown so
    /// their history stays reachable, per M1B-FR-023).
    var customMetrics: [BodyMetricDefinition] {
        metrics.filter { $0.kind == .custom }
            .sorted { ($0.lifecycle == .active ? 0 : 1) < ($1.lifecycle == .active ? 0 : 1) }
    }

    /// Split out of `customMetrics` into their own visual groups so an
    /// archived ("停用") metric never reads as visually indistinct from one
    /// that is still active (coaches were mixing up "archived" with
    /// "can't be deleted").
    var activeCustomMetrics: [BodyMetricDefinition] {
        customMetrics.filter { $0.lifecycle == .active }
    }

    var archivedCustomMetrics: [BodyMetricDefinition] {
        customMetrics.filter { $0.lifecycle == .archived }
    }

    func reload() async {
        do {
            metrics = try await useCases.metrics(studentID: studentID)
            latestByMetric = try await useCases.latestMeasurements(studentID: studentID)
            errorMessage = nil
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyData.error.generic")
        }
    }

    /// Converts a metric's latest recorded value into its currently
    /// preferred display form -- built-in weight/length metrics are
    /// converted through `BuiltInUnitConversion` using the coach's saved
    /// display-unit preference (mirrors
    /// `BodyMeasurementEntryViewModel.displayValue(for:)`); percent and
    /// custom metrics show their stored value/unit unchanged.
    func latestDisplayValue(for metric: BodyMetricDefinition) -> String? {
        guard let measurement = latestByMetric[metric.id] else { return nil }
        guard metric.kind == .builtIn else {
            return "\(measurement.value.canonicalString) \(measurement.enteredUnit)"
        }
        switch metric.unitRuleKind {
        case .weight:
            let unit = unitPreferences.weightUnit
            let converted =
                (try? BuiltInUnitConversion.weight(canonicalKilograms: measurement.value, displayedAs: unit))
                ?? measurement.value
            return "\(converted.canonicalString) \(unit.rawValue)"
        case .length:
            let unit = unitPreferences.lengthUnit
            let converted =
                (try? BuiltInUnitConversion.length(canonicalCentimeters: measurement.value, displayedAs: unit))
                ?? measurement.value
            return "\(converted.canonicalString) \(unit.rawValue)"
        case .percent, .customUnit:
            return "\(measurement.value.canonicalString) \(measurement.enteredUnit)"
        }
    }

    func createCustomMetric() async {
        do {
            _ = try await useCases.createCustomMetric(
                studentID: studentID,
                name: newMetricName,
                unit: newMetricUnit
            )
            newMetricName = ""
            newMetricUnit = ""
            newMetricErrorMessage = nil
            showingNewCustomMetric = false
            await reload()
        } catch {
            // Deliberately NOT dismissing the sheet and NOT touching the
            // list-level `errorMessage` -- the coach is still inside the
            // sheet and needs to see why the save failed right there.
            newMetricErrorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyData.error.generic")
        }
    }

    /// Clears any stale error from a previous failed attempt when the coach
    /// (re)opens the new-custom-metric sheet.
    func presentNewCustomMetricSheet() {
        newMetricErrorMessage = nil
        showingNewCustomMetric = true
    }

    func cancelNewCustomMetric() {
        newMetricErrorMessage = nil
        showingNewCustomMetric = false
    }

    func toggleArchive(_ metric: BodyMetricDefinition) async {
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
                ?? String(localized: "bodyData.error.generic")
        }
    }

    /// Deletion is only possible with zero recorded measurements
    /// (M1B-FR-023/D-009) -- `deleteCustomMetricIfUnused` counts live and
    /// refuses otherwise; this surfaces that refusal as a real message
    /// rather than a silent no-op.
    func deleteIfUnused(_ metric: BodyMetricDefinition) async {
        do {
            try await useCases.deleteCustomMetricIfUnused(id: metric.id)
            await reload()
        } catch DomainError.conflict {
            errorMessage = String(localized: "bodyData.deleteBlocked")
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyData.error.generic")
        }
    }
}

struct BodyDataListView: View {
    @StateObject private var viewModel: BodyDataListViewModel
    @Binding var path: [RootDestination]

    init(studentID: StableUUID, useCases: BodyDataUseCases, path: Binding<[RootDestination]>) {
        _viewModel = StateObject(wrappedValue: BodyDataListViewModel(studentID: studentID, useCases: useCases))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(FCSemanticColors.destructive)
                }

                if viewModel.metrics.isEmpty {
                    Text(String(localized: "bodyData.empty"))
                        .foregroundStyle(FCSemanticColors.secondaryText)
                        .accessibilityIdentifier(FCAccessibilityID.bodyDataEmptyState)
                }

                sectionTitle(String(localized: "bodyData.builtInSection"))
                ForEach(viewModel.builtInMetrics) { metric in
                    metricRow(metric)
                }

                if !viewModel.activeCustomMetrics.isEmpty {
                    Divider()
                    sectionTitle(String(localized: "bodyData.customSection"))
                    ForEach(viewModel.activeCustomMetrics) { metric in
                        metricRow(metric)
                    }
                }

                if !viewModel.archivedCustomMetrics.isEmpty {
                    Divider()
                    sectionTitle(String(localized: "bodyData.customSection.archived"))
                    ForEach(viewModel.archivedCustomMetrics) { metric in
                        metricRow(metric)
                    }
                }

                FCButton(title: String(localized: "bodyData.addCustomMetric")) {
                    viewModel.presentNewCustomMetricSheet()
                }
                .accessibilityIdentifier(FCAccessibilityID.bodyDataAddCustomMetric)
            }
            .padding(FCPrimitives.spacingMedium)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationTitle(String(localized: "bodyData.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(FCAccessibilityID.bodyDataListRoot)
        .task { await viewModel.reload() }
        .sheet(isPresented: $viewModel.showingNewCustomMetric) {
            newCustomMetricSheet
        }
    }

    private var newCustomMetricSheet: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.spacingMedium) {
            Text(String(localized: "bodyData.newCustomMetric.title"))
                .font(.title3.weight(.semibold))
            if let newMetricErrorMessage = viewModel.newMetricErrorMessage {
                Text(newMetricErrorMessage)
                    .foregroundStyle(FCSemanticColors.destructive)
                    .accessibilityIdentifier(FCAccessibilityID.bodyDataNewCustomMetricError)
            }
            FCTextField(String(localized: "bodyData.newCustomMetric.namePlaceholder"), text: $viewModel.newMetricName)
            FCTextField(String(localized: "bodyData.newCustomMetric.unitPlaceholder"), text: $viewModel.newMetricUnit)
            FCButton(title: String(localized: "bodyData.newCustomMetric.save")) {
                Task { await viewModel.createCustomMetric() }
            }
            Button(String(localized: "bodyData.newCustomMetric.cancel")) {
                viewModel.cancelNewCustomMetric()
            }
            .frame(minHeight: 44)
        }
        .padding(FCPrimitives.spacingMedium)
        .background(FCSemanticColors.surfacePage)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FCSemanticColors.secondaryText)
    }

    private func metricRow(_ metric: BodyMetricDefinition) -> some View {
        HStack {
            Button {
                path.append(
                    .bodyMeasurementEntry(studentID: viewModel.studentID.rawValue, metricID: metric.id.rawValue))
            } label: {
                VStack(alignment: .leading, spacing: FCPrimitives.spacingSmall) {
                    HStack {
                        Text(metric.name.value)
                            .font(.headline)
                            .foregroundStyle(FCSemanticColors.primaryText)
                        if metric.lifecycle == .archived {
                            Text(String(localized: "bodyData.archived"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FCSemanticColors.secondaryText)
                        }
                    }
                    Text(metric.currentUnit)
                        .font(.caption)
                        .foregroundStyle(FCSemanticColors.secondaryText)
                    if let latestValue = viewModel.latestDisplayValue(for: metric) {
                        Text(latestValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FCSemanticColors.primaryText)
                    }
                }
                .padding(FCPrimitives.spacingMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FCSemanticColors.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: FCPrimitives.radiusMedium))
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier(FCAccessibilityID.bodyDataMetricRow(metric.id))
        .contextMenu {
            if metric.kind == .custom {
                Button(
                    metric.lifecycle == .active
                        ? String(localized: "bodyData.archive")
                        : String(localized: "bodyData.restore")
                ) {
                    Task { await viewModel.toggleArchive(metric) }
                }
                Button(String(localized: "bodyData.delete"), role: .destructive) {
                    Task { await viewModel.deleteIfUnused(metric) }
                }
            }
        }
    }
}
