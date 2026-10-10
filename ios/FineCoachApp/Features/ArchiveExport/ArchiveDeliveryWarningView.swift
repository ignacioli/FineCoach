import SwiftUI

/// M2-04 交付前确认 (T032): the six delivery facts of M2-FR-013, in order, then ONE explicit
/// confirmation (H2). The first three are warnings (`!`, `status.warning`), the last three are
/// information (`i`).
struct ArchiveDeliveryWarningView: View {
    @ObservedObject var model: ArchiveExportViewModel

    var body: some View {
        ArchiveExportPage {
            FCPageHeader(
                title: String(localized: "archive.export.warning.title"),
                subtitle: String(localized: "archive.export.warning.subtitle")
            )
            VStack(alignment: .leading, spacing: 0) {
                FCListRowDivider()
                ForEach(ArchiveFactRow.Fact.allCases, id: \.self) { fact in
                    ArchiveFactRow(fact: fact)
                    FCListRowDivider()
                }
            }
        }
        .archiveBottomButton {
            FCButton(title: String(localized: "archive.export.warning.confirm"), isEnabled: !model.isBusy) {
                Task { await model.confirmFacts() }
            }
            .accessibilityIdentifier(FCAccessibilityID.archiveExportConfirmFacts)
        }
    }
}

/// `M2-FACT-ROW` (implementation-map §4.3): a 22×22 `FCStatusBadge` and `body` `text.primary`
/// text, one accessibility element that reads the text. Feature-specific: used only on M2-04.
struct ArchiveFactRow: View {
    /// The six facts in M2-FR-013 order. The first three are warnings.
    enum Fact: CaseIterable {
        case notABackup
        case includesPreviewedData
        case irrevocableOnceReceived
        case studentDeletesOwnCopy
        case studentDeletionDoesNotAffectYou
        case sharePasswordSeparately

        var isWarning: Bool {
            switch self {
            case .notABackup, .includesPreviewedData, .irrevocableOnceReceived: return true
            default: return false
            }
        }

        var text: String {
            switch self {
            case .notABackup: return String(localized: "archive.export.fact.notABackup")
            case .includesPreviewedData: return String(localized: "archive.export.fact.includesPreviewedData")
            case .irrevocableOnceReceived: return String(localized: "archive.export.fact.irrevocableOnceReceived")
            case .studentDeletesOwnCopy: return String(localized: "archive.export.fact.studentDeletesOwnCopy")
            case .studentDeletionDoesNotAffectYou:
                return String(localized: "archive.export.fact.studentDeletionDoesNotAffectYou")
            case .sharePasswordSeparately: return String(localized: "archive.export.fact.sharePasswordSeparately")
            }
        }
    }

    let fact: Fact

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FCPrimitives.space3) {
            FCStatusBadge(
                symbolName: fact.isWarning ? "exclamationmark" : "info",
                color: fact.isWarning ? FCSemanticColors.statusWarning : FCSemanticColors.actionPrimary
            )
            Text(fact.text)
                .fcFont(.body)
                .foregroundStyle(FCSemanticColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, FCPrimitives.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(fact.text))
    }
}
