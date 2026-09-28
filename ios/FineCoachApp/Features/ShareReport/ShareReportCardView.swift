import SwiftUI
import UIKit

/// The single-session report card (T069j, `29-share-preview`). It renders
/// ONLY a `ShareReportDTO` — the privacy gate (`ShareReportPolicy`) decides
/// what the card can ever show; body data is never part of the DTO
/// (M1B-FR-030). Used both for the on-screen preview and, via
/// `ShareReportCardRenderer`, for the one long image that is shared.
struct ShareReportCardView: View {
    enum Style {
        /// The fixed-width shared image, with the footer.
        case shareCard
        /// The in-app 训练记录 page (`35-session-detail`): same sections,
        /// full width, no footer; the page supplies its own padding.
        case page
    }

    let dto: ShareReportDTO
    var style: Style = .shareCard

    var body: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space6) {
            header
            if !stats.isEmpty {
                statsRow
            }
            if let summary = trainedParts, !summary.isEmpty {
                section(String(localized: "shareCard.trainedParts")) {
                    FCBodyDiagram(summary: summary)
                }
            }
            if !dto.exercises.isEmpty {
                section(String(localized: "shareCard.exercises")) {
                    VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                        ForEach(Array(dto.exercises.enumerated()), id: \.offset) { _, exercise in
                            exerciseBlock(exercise)
                        }
                    }
                }
            }
            if !dto.personalBests.isEmpty {
                section(String(localized: "history.pb.title")) {
                    VStack(spacing: 0) {
                        ForEach(Array(dto.personalBests.enumerated()), id: \.offset) { _, best in
                            HStack {
                                Text(best.displayName)
                                    .fcFont(.headline)
                                    .foregroundStyle(FCSemanticColors.textPrimary)
                                Spacer(minLength: FCPrimitives.space2)
                                Text(ShareReportCardPresentation.bestValue(best))
                                    .fcFont(.titleEmphasis)
                                    .foregroundStyle(FCSemanticColors.textPrimary)
                            }
                            .padding(.vertical, FCPrimitives.space2)
                        }
                    }
                }
            }
            if let summary = dto.studentFacingSummary, !summary.isEmpty {
                section(String(localized: "shareCard.summary")) {
                    Text(summary)
                        .fcFont(.body)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if style == .shareCard {
                VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                    FCListRowDivider()
                    Text(String(localized: "shareCard.footer"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
            }
        }
        .modifier(CardFrame(style: style))
    }

    private struct CardFrame: ViewModifier {
        let style: Style

        func body(content: Content) -> some View {
            switch style {
            case .shareCard:
                content
                    .padding(.horizontal, FCPrimitives.space6)
                    .padding(.vertical, FCPrimitives.space8)
                    .frame(width: ShareReportCardRenderer.cardWidth, alignment: .leading)
                    .background(FCSemanticColors.surfacePage)
            case .page:
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space1) {
            if let date = dto.sessionDateUTC {
                Text(ShareReportCardPresentation.day(date))
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
            Text(ShareReportCardPresentation.title(dto))
                .fcFont(.titleLarge)
                .foregroundStyle(FCSemanticColors.textPrimary)
            if let name = dto.studentDisplayName, !name.isEmpty {
                Text(name)
                    .fcFont(.callout, weight: .regular)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
    }

    private var stats: [(value: String, label: String)] {
        ShareReportCardPresentation.stats(dto)
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: FCPrimitives.space4) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: FCPrimitives.space1) {
                    Text(stat.value)
                        .fcFont(.numeralLarge)
                        .foregroundStyle(FCSemanticColors.textPrimary)
                    Text(stat.label)
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var trainedParts: TrainedBodyPartsSummary? {
        guard !dto.exercises.isEmpty else { return nil }
        return TrainedBodyPartsSummary(exercises: dto.exercises.map {
            ExerciseBodyParts(primary: $0.primaryBodyPart, secondary: $0.secondaryBodyParts)
        })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space3) {
            FCListRowDivider()
            FCSectionLabel(title)
            content()
        }
    }

    /// Icon + name, then the sets three per row: "1 60kg × 12次".
    private func exerciseBlock(_ exercise: ShareReportExerciseDTO) -> some View {
        VStack(alignment: .leading, spacing: FCPrimitives.space2) {
            HStack(spacing: FCPrimitives.space2) {
                if let icon = exercise.equipmentIcon.flatMap(FCEquipmentIcon.init(rawValue:)) {
                    FCEquipmentIconView(icon)
                }
                Text(exercise.displayName)
                    .fcFont(.headline)
                    .foregroundStyle(FCSemanticColors.textPrimary)
            }
            let cells = exercise.confirmedSets.enumerated().map { index, set in
                (index + 1, TrainingSetDisplayFormatting.summary(for: set))
            }
            ForEach(Array(stride(from: 0, to: cells.count, by: 3)), id: \.self) { start in
                HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space2) {
                    ForEach(start..<min(start + 3, cells.count), id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space1) {
                            Text("\(cells[index].0)")
                                .fcFont(.caption)
                                .foregroundStyle(FCSemanticColors.textDisabled)
                            Text(cells[index].1)
                                .fcFont(.callout, weight: .regular)
                                .foregroundStyle(FCSemanticColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(0..<(3 - min(3, cells.count - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

enum ShareReportCardPresentation {
    /// "9月25日 周四" in the device time zone.
    static func day(_ instant: Date) -> String {
        HistoryPresentation.day(instant)
    }

    /// "大腿、臀训练", or "训练报告" without a body-part focus.
    static func title(_ dto: ShareReportDTO) -> String {
        guard let focus = dto.trainingFocus, !focus.isEmpty else {
            return String(localized: "shareCard.defaultTitle")
        }
        return String(format: String(localized: "shareCard.titleFormat"), focus)
    }

    /// 总组数 / 总次数 / (总容量 kg when the coach enabled it, else 分钟).
    static func stats(_ dto: ShareReportDTO) -> [(value: String, label: String)] {
        var result: [(String, String)] = []
        let sets = dto.exercises.flatMap(\.confirmedSets)
        if !dto.exercises.isEmpty {
            result.append(("\(sets.count)", String(localized: "shareCard.stat.sets")))
            let reps = sets.compactMap { $0.repetitionCount.flatMap { Double($0.canonicalString) } }.reduce(0, +)
            if reps > 0 {
                result.append((grouped(reps), String(localized: "shareCard.stat.reps")))
            }
        }
        if let volume = dto.trainingVolume, let value = Double(volume.canonicalString) {
            result.append((grouped(value), String(localized: "shareCard.stat.volume")))
        } else if let duration = dto.durationSeconds, let seconds = Double(duration.canonicalString), seconds > 0 {
            let minutes = max(1, Int((seconds / 60).rounded()))
            result.append(("\(minutes)", String(localized: "shareCard.stat.minutes")))
        }
        return result
    }

    static func bestValue(_ best: ShareReportPersonalBestDTO) -> String {
        switch best.kind {
        case .highestWeight:
            let weight = best.weightValue?.canonicalString ?? ""
            if let reps = best.repetitionCount?.canonicalString {
                return String(format: String(localized: "history.pb.setDetailFormat"), weight, reps)
            }
            return "\(weight) kg"
        case .longestDuration:
            return DurationTextParser.formatForEditing(secondsText: best.durationSeconds?.canonicalString ?? "0")
        case .longestDistance:
            return "\(best.distanceValue?.canonicalString ?? "") km"
        }
    }

    private static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Renders the card to ONE long PNG (M1A-FR-038 allows a long image; owner
/// 2026-09-28 chose one). Input is only the DTO, and the raster stays within
/// the same peak budget as `ShareReportRenderer` — scaled down if a very
/// long report would exceed it.
@MainActor
enum ShareReportCardRenderer {
    static let cardWidth: CGFloat = 390

    static func render(dto: ShareReportDTO, preferredScale: CGFloat = 2) throws -> Data {
        let renderer = ImageRenderer(content: ShareReportCardView(dto: dto))
        renderer.proposedSize = ProposedViewSize(width: cardWidth, height: nil)
        renderer.scale = 1
        guard let probe = renderer.uiImage else {
            throw DomainError.invalidFileOperation
        }
        let pointArea = probe.size.width * probe.size.height
        let maxScale = (Double(ShareReportRenderer.peakRasterBudgetBytes) / (4 * pointArea)).squareRoot()
        renderer.scale = min(preferredScale, CGFloat(maxScale))
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw DomainError.invalidFileOperation
        }
        return data
    }
}
