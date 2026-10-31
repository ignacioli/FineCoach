import SwiftUI
import UIKit

/// The single-session report card (T069j, `29-share-preview`). It renders
/// ONLY a `ShareReportDTO` — the privacy gate (`ShareReportPolicy`) decides
/// what the card can ever show; body data is never part of the DTO
/// (M1B-FR-030). Used both for the on-screen preview and, via
/// `ShareReportCardRenderer`, for the shared image(s).
struct ShareReportCardView: View {
    enum Style {
        /// The fixed-width shared image, with the footer.
        case shareCard
        /// The in-app 训练记录 page (`35-session-detail`): same sections,
        /// full width, no footer; the page supplies its own padding.
        case page
    }

    /// One unit the shared image may be split between (owner 2026-09-29:
    /// split a too-long report into ordered images, never lower its
    /// resolution). A block is never cut in half.
    enum Block: Hashable {
        case header
        case stats
        case trainedParts
        /// Exercise at this index; index 0 carries the "动作" section label.
        case exercise(Int)
        case personalBests
        case summary
        case footer
    }

    let dto: ShareReportDTO
    var style: Style = .shareCard
    /// The unit label printed after weights. "kg" everywhere except the archive viewer, whose
    /// local display setting may ask for "lb" (the DTO values are converted by the caller).
    var weightUnit: String = "kg"
    /// The blocks to draw; `nil` draws the whole report.
    var blocks: [Block]?

    /// Every block of this report, in reading order.
    static func blocks(for dto: ShareReportDTO, style: Style = .shareCard) -> [Block] {
        var result: [Block] = [.header]
        if !ShareReportCardPresentation.stats(dto).isEmpty { result.append(.stats) }
        if let parts = trainedParts(dto), !parts.isEmpty { result.append(.trainedParts) }
        result.append(contentsOf: dto.exercises.indices.map(Block.exercise))
        if !dto.gainRows.isEmpty || dto.milestoneSessionNumber != nil || dto.attendanceStreakWeeks != nil {
            result.append(.personalBests)
        }
        if let summary = dto.studentFacingSummary, !summary.isEmpty { result.append(.summary) }
        if style == .shareCard { result.append(.footer) }
        return result
    }

    /// Space above `block` when something precedes it on the same image:
    /// consecutive exercises sit `space4` apart inside their section; every
    /// other block starts a new section `space6` below.
    static func spacing(before block: Block) -> CGFloat {
        if case .exercise(let index) = block, index > 0 { return FCPrimitives.space4 }
        return FCPrimitives.space6
    }

    var body: some View {
        let shown = blocks ?? Self.blocks(for: dto, style: style)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { position, block in
                content(for: block)
                    .padding(.top, position == 0 ? 0 : Self.spacing(before: block))
            }
        }
        .modifier(CardFrame(style: style))
    }

    @ViewBuilder
    private func content(for block: Block) -> some View {
        switch block {
        case .header:
            header
        case .stats:
            statsRow
        case .trainedParts:
            if let summary = Self.trainedParts(dto) {
                section(String(localized: "shareCard.trainedParts")) {
                    FCBodyDiagram(summary: summary)
                }
            }
        case .exercise(let index):
            if index == 0 {
                section(String(localized: "shareCard.exercises")) {
                    exerciseBlock(dto.exercises[index])
                }
            } else {
                exerciseBlock(dto.exercises[index])
            }
        case .personalBests:
            section(String(localized: "session.gains.title")) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(dto.gainRows.enumerated()), id: \.offset) { _, row in
                        FCListRow(
                            title: row.displayName,
                            subtitle: SessionGainsPresentation.progress(
                                previous: TrainingSetDisplayFormatting.summary(for: row.previous),
                                current: TrainingSetDisplayFormatting.summary(for: row.current)),
                            showsDisclosure: false,
                            showsNewRecordBadge: row.isNewRecord)
                    }
                    if let number = dto.milestoneSessionNumber {
                        HStack(spacing: FCPrimitives.space3) {
                            // Approved D-c2 illustration size (README §9); decorative only.
                            Image("MascotHeartSticker")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .accessibilityHidden(true)
                            FCListRow(
                                title: SessionGainsPresentation.milestone(number),
                                subtitle: String(localized: "session.gains.milestone.subtitle"), showsDisclosure: false)
                        }
                    }
                    if let weeks = dto.attendanceStreakWeeks {
                        HStack(spacing: FCPrimitives.space3) {
                            Image("MascotHeartSticker")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .accessibilityHidden(true)
                            FCListRow(
                                title: SessionGainsPresentation.streak(weeks),
                                subtitle: String(localized: "session.gains.streak.subtitle"), showsDisclosure: false)
                        }
                    }
                }
            }
            .accessibilityIdentifier(FCAccessibilityID.shareReportGains)
        case .summary:
            section(String(localized: "shareCard.summary")) {
                Text(dto.studentFacingSummary ?? "")
                    .fcFont(.body)
                    .foregroundStyle(FCSemanticColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .footer:
            VStack(alignment: .leading, spacing: FCPrimitives.space3) {
                FCListRowDivider()
                Text(String(localized: "shareCard.footer"))
                    .fcFont(.caption)
                    .foregroundStyle(FCSemanticColors.textSecondary)
            }
        }
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

    private static func trainedParts(_ dto: ShareReportDTO) -> TrainedBodyPartsSummary? {
        guard !dto.exercises.isEmpty else { return nil }
        return TrainedBodyPartsSummary(
            exercises: dto.exercises.map {
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
                (index + 1, TrainingSetDisplayFormatting.summary(for: set, weightUnit: weightUnit))
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

    private static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Renders the card to ordered PNG images at a fixed 2× (M1A-FR-038 allows
/// one long image or ordered images). Owner 2026-09-29: a report too long
/// for one image is split between whole blocks -- never downscaled. Input
/// is only the DTO.
@MainActor
enum ShareReportCardRenderer {
    static let cardWidth: CGFloat = 390
    static let scale: CGFloat = 2
    static let peakRasterBudgetBytes = 32 * 1024 * 1024
    /// `ImageRenderer` returns nil past an undocumented per-side pixel limit
    /// (a 390pt-wide card failed at ~8800 px tall and rendered at ~7000 px on
    /// the iOS 26.5 simulator), so each image stays at or under 8000 px.
    static let maxPagePixelHeight: CGFloat = 8000

    /// Vertical card padding (`space8` top and bottom, see `CardFrame`).
    private static let cardVerticalPadding = FCPrimitives.space8 * 2

    static func render(dto: ShareReportDTO) throws -> [Data] {
        let pages = try paginate(dto: dto)
        return try pages.map { blocks in
            let renderer = ImageRenderer(content: ShareReportCardView(dto: dto, blocks: blocks))
            renderer.proposedSize = ProposedViewSize(width: cardWidth, height: nil)
            renderer.scale = scale
            guard let data = renderer.uiImage?.pngData() else {
                throw DomainError.invalidFileOperation
            }
            return data
        }
    }

    /// Groups the report's blocks into pages whose rendered height fits
    /// `maxPagePixelHeight` at `scale`; a single block taller than that
    /// still gets its own page.
    static func paginate(dto: ShareReportDTO) throws -> [[ShareReportCardView.Block]] {
        let maxHeight = maxPagePixelHeight / scale
        let all = ShareReportCardView.blocks(for: dto)
        if try pointHeight(dto: dto, blocks: all) <= maxHeight {
            return [all]
        }
        var pages: [[ShareReportCardView.Block]] = []
        var current: [ShareReportCardView.Block] = []
        var height = cardVerticalPadding
        for block in all {
            let blockHeight = try pointHeight(dto: dto, blocks: [block]) - cardVerticalPadding
            let added = current.isEmpty ? blockHeight : ShareReportCardView.spacing(before: block) + blockHeight
            if !current.isEmpty, height + added > maxHeight {
                pages.append(current)
                current = [block]
                height = cardVerticalPadding + blockHeight
            } else {
                current.append(block)
                height += added
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    private static func pointHeight(dto: ShareReportDTO, blocks: [ShareReportCardView.Block]) throws -> CGFloat {
        let renderer = ImageRenderer(content: ShareReportCardView(dto: dto, blocks: blocks))
        renderer.proposedSize = ProposedViewSize(width: cardWidth, height: nil)
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            throw DomainError.invalidFileOperation
        }
        return image.size.height
    }
}
