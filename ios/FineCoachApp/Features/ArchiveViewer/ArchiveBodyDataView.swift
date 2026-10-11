import SwiftUI

/// M2-14 身体数据 (T048): the 06 structure (page header, section labels, metric rows) with no
/// student name and no 「＋ 自定义指标」. A row opens that metric's read-only history.
struct ArchiveBodyDataView: View {
    let content: ArchiveViewerContent
    @ObservedObject var model: ArchiveViewerModel
    let openMetric: (String) -> Void

    private var metrics: [ArchiveBodyMetric] {
        (try? content.bodyMetrics()) ?? []
    }

    private func builtIns(_ order: [BuiltInBodyMetric]) -> [ArchiveBodyMetric] {
        order.compactMap { builtIn in
            metrics.first { if case .builtIn(let value) = $0.kind { return value == builtIn } else { return false } }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FCPageHeader(
                    title: String(localized: "bodyData.title"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveBodyBack)
                )
                section(String(localized: "bodyData.basicSection"), builtIns([.weight, .bodyFatPercent, .height]))
                section(String(localized: "bodyData.girthSection"), builtIns([.chest, .waist, .hip, .upperArm, .thigh]))
                section(String(localized: "bodyData.customSection"), metrics.filter { $0.kind == .custom })
                Text(
                    String(
                        format: String(localized: "archive.viewer.body.unitSummaryFormat"),
                        model.settings.weightUnit.rawValue, model.settings.lengthUnit.rawValue)
                )
                .fcFont(.callout, weight: .regular)
                .foregroundStyle(FCSemanticColors.textSecondary)
                .padding(.top, FCPrimitives.space6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveBodyRoot)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ArchiveBodyMetric]) -> some View {
        if !items.isEmpty {
            FCSectionLabel(title)
                .padding(.top, FCPrimitives.space6)
                .padding(.bottom, FCPrimitives.space1)
            FCListRowDivider()
            ForEach(items, id: \.key) { metric in
                let display = ArchiveBodyPresentation.latest(metric, content: content, converter: model.converter)
                Button { openMetric(metric.key) } label: {
                    BodyMetricValueRow(
                        name: ArchiveBodyPresentation.name(metric), value: display.value, unit: display.unit)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(FCAccessibilityID.archiveBodyMetric(metric.key))
                FCListRowDivider()
            }
        }
    }
}

/// M2-14 sub page: every measurement of one metric, newest first, in the read-only form of the
/// M1 history rows (no delete control).
struct ArchiveMetricHistoryView: View {
    let content: ArchiveViewerContent
    let metricKey: String
    @ObservedObject var model: ArchiveViewerModel

    var body: some View {
        let metric = content.snapshot.bodyMetrics.first { $0.key == metricKey }
        let measurements = ((try? content.measurements(forMetricKey: metricKey)) ?? []).reversed()
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                FCPageHeader(
                    title: metric.map(ArchiveBodyPresentation.name) ?? String(localized: "bodyData.title"),
                    back: .init(accessibilityIdentifier: FCAccessibilityID.archiveMetricBack)
                )
                FCSectionLabel(String(localized: "bodyMeasurementEntry.historySection"))
                ForEach(Array(measurements), id: \.localDay) { measurement in
                    let quantity = metric.map { model.converter.measurement(measurement, of: $0) }
                    BodyMeasurementHistoryRow(
                        dateText: measurement.localDay.canonicalString,
                        valueText: quantity.map { "\($0.value.canonicalString) \($0.unit)" } ?? ""
                    ) { EmptyView() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space6)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveMetricRoot)
    }
}

enum ArchiveBodyPresentation {
    static func name(_ metric: ArchiveBodyMetric) -> String {
        switch metric.kind {
        case .builtIn(let builtIn): return builtIn.displayName
        case .custom: return metric.name ?? ""
        }
    }

    /// The newest measurement in the display units; 「—」 when there is none.
    static func latest(
        _ metric: ArchiveBodyMetric, content: ArchiveViewerContent, converter: ArchiveDisplayConverter
    ) -> (value: String, unit: String) {
        guard let latest = ((try? content.measurements(forMetricKey: metric.key)) ?? []).last else {
            return (String(localized: "bodyData.noValue"), metric.unit ?? "")
        }
        let quantity = converter.measurement(latest, of: metric)
        return (quantity.value.canonicalString, quantity.unit)
    }
}
