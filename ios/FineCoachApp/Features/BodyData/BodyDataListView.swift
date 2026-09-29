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
    /// Shown under the page title, as on `06-body-data` and 04 课包详情.
    @Published var studentName: String?
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
    private let studentUseCases: StudentUseCases?

    init(
        studentID: StableUUID,
        useCases: BodyDataUseCases,
        studentUseCases: StudentUseCases? = nil,
        unitPreferences: BodyDataUnitPreferences = .shared
    ) {
        self.studentID = studentID
        self.useCases = useCases
        self.studentUseCases = studentUseCases
        self.unitPreferences = unitPreferences
    }

    /// "基本指标" in the order the 06 artwork lists them.
    var basicMetrics: [BodyMetricDefinition] {
        builtIns([.weight, .bodyFatPercent, .height])
    }

    /// "围度" in the order the 06 artwork lists them.
    var girthMetrics: [BodyMetricDefinition] {
        builtIns([.chest, .waist, .hip, .upperArm, .thigh])
    }

    private func builtIns(_ order: [BuiltInBodyMetric]) -> [BodyMetricDefinition] {
        order.compactMap { builtIn in metrics.first { $0.kind == .builtIn && $0.id == builtIn.id } }
    }

    /// The display units currently used for built-in weight/length values,
    /// e.g. "单位 · kg / cm". Display only -- the unit is switched on the entry
    /// screen (T069k, owner 2026-09-29).
    var unitSummary: String {
        String(
            format: String(localized: "bodyData.unitSummaryFormat"),
            unitPreferences.weightUnit.rawValue,
            unitPreferences.lengthUnit.rawValue
        )
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
            if studentName == nil, let studentUseCases {
                studentName = try? await studentUseCases.student(id: studentID).displayName.value
            }
            errorMessage = nil
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(localized: "bodyData.error.generic")
        }
    }

    /// A metric's latest recorded value and unit in its currently preferred
    /// display form -- built-in weight/length metrics are converted through
    /// `BuiltInUnitConversion` using the coach's saved display-unit
    /// preference (mirrors `BodyMeasurementEntryViewModel.displayValue(for:)`);
    /// percent and custom metrics show their stored value/unit unchanged.
    /// With no recorded measurement the value is "—" and the unit is the one
    /// a new entry would use (owner 2026-09-29, T069k).
    func latestDisplay(for metric: BodyMetricDefinition) -> (value: String, unit: String) {
        let measurement = latestByMetric[metric.id]
        switch (metric.kind, metric.unitRuleKind) {
        case (.builtIn, .weight):
            let unit = unitPreferences.weightUnit
            guard let measurement else { return (String(localized: "bodyData.noValue"), unit.rawValue) }
            let converted =
                (try? BuiltInUnitConversion.weight(canonicalKilograms: measurement.value, displayedAs: unit))
                ?? measurement.value
            return (converted.canonicalString, unit.rawValue)
        case (.builtIn, .length):
            let unit = unitPreferences.lengthUnit
            guard let measurement else { return (String(localized: "bodyData.noValue"), unit.rawValue) }
            let converted =
                (try? BuiltInUnitConversion.length(canonicalCentimeters: measurement.value, displayedAs: unit))
                ?? measurement.value
            return (converted.canonicalString, unit.rawValue)
        default:
            guard let measurement else { return (String(localized: "bodyData.noValue"), metric.currentUnit) }
            return (measurement.value.canonicalString, measurement.enteredUnit)
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
}

struct BodyDataListView: View {
    @StateObject private var viewModel: BodyDataListViewModel
    /// Value and unit column widths measured from `06-body-data` (values
    /// start at x=200, units at x=290 of 390), scaled with Dynamic Type so
    /// the columns stay aligned across rows.
    @ScaledMetric(relativeTo: .title2) private var valueColumnWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .footnote) private var unitColumnWidth: CGFloat = 84
    @Binding var path: [RootDestination]

    init(
        studentID: StableUUID,
        useCases: BodyDataUseCases,
        studentUseCases: StudentUseCases? = nil,
        path: Binding<[RootDestination]>
    ) {
        _viewModel = StateObject(
            wrappedValue: BodyDataListViewModel(studentID: studentID, useCases: useCases, studentUseCases: studentUseCases)
        )
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "bodyData.title"))
                    .fcFont(.titleLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let name = viewModel.studentName {
                    Text(name)
                        .fcFont(.headline)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                        .padding(.top, FCPrimitives.space4)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FCSemanticColors.statusDestructive)
                        .padding(.top, FCPrimitives.space3)
                }

                if viewModel.metrics.isEmpty {
                    Text(String(localized: "bodyData.empty"))
                        .foregroundStyle(FCSemanticColors.textSecondary)
                        .accessibilityIdentifier(FCAccessibilityID.bodyDataEmptyState)
                }

                metricSection(String(localized: "bodyData.basicSection"), viewModel.basicMetrics)
                metricSection(String(localized: "bodyData.girthSection"), viewModel.girthMetrics)
                metricSection(String(localized: "bodyData.customSection"), viewModel.activeCustomMetrics)
                metricSection(String(localized: "bodyData.customSection.archived"), viewModel.archivedCustomMetrics)
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(viewModel.unitSummary)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                Spacer(minLength: FCPrimitives.space2)
                FCLinkButton(title: String(localized: "bodyData.addCustomMetric")) {
                    viewModel.presentNewCustomMetricSheet()
                }
                .accessibilityIdentifier(FCAccessibilityID.bodyDataAddCustomMetric)
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.vertical, FCPrimitives.space2)
            .background(FCSemanticColors.surfacePage)
        }
        .background(FCSemanticColors.surfacePage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .accessibilityIdentifier(FCAccessibilityID.bodyDataListRoot)
        .task { await viewModel.reload() }
        .sheet(isPresented: $viewModel.showingNewCustomMetric) {
            newCustomMetricSheet
        }
    }

    private var newCustomMetricSheet: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space4) {
            Text(String(localized: "bodyData.newCustomMetric.title"))
                .fcFont(.title)
            if let newMetricErrorMessage = viewModel.newMetricErrorMessage {
                Text(newMetricErrorMessage)
                    .foregroundStyle(FCSemanticColors.statusDestructive)
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
        .padding(FCPrimitives.space4)
        .background(FCSemanticColors.surfacePage)
    }

    /// One 06-artwork section: label, then a "name · value · unit" row per
    /// metric with a 1pt divider under each (design system §6). Empty
    /// sections are omitted.
    @ViewBuilder
    private func metricSection(_ title: String, _ metrics: [BodyMetricDefinition]) -> some View {
        if !metrics.isEmpty {
            FCSectionLabel(title)
                .padding(.top, FCPrimitives.space6)
                .padding(.bottom, FCPrimitives.space1)
            ForEach(metrics) { metric in
                metricRow(metric)
                FCListRowDivider()
            }
        }
    }

    private func metricRow(_ metric: BodyMetricDefinition) -> some View {
        let display = viewModel.latestDisplay(for: metric)
        return Button {
            path.append(
                .bodyMeasurementEntry(studentID: viewModel.studentID.rawValue, metricID: metric.id.rawValue))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(metric.name.value)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(display.value)
                    .fcFont(.numeralLarge)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .frame(minWidth: valueColumnWidth, alignment: .leading)
                Text(display.unit)
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
                    .frame(minWidth: unitColumnWidth, alignment: .leading)
            }
            .padding(.vertical, FCPrimitives.space3)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(FCAccessibilityID.bodyDataMetricRow(metric.id))
    }
}
