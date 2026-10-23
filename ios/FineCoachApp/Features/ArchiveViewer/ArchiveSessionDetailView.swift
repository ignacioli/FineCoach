import SwiftUI

/// M2-13 训练记录详情 (T047): the sections of the M1 35 page, fed from archive values, with the
/// edit / save-as-template / generate-report controls removed and 「只读记录」 at the end.
/// Without exercise info the exercises are 「动作 N」 with no equipment icon, and the trained
/// body-parts diagram is not drawn (its colours come from exercise info; the card omits it when
/// no exercise carries a body part).
struct ArchiveSessionDetailView: View {
    let content: ArchiveViewerContent
    let sessionKey: String
    @ObservedObject var model: ArchiveViewerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FCPrimitives.space6) {
                FCPageHeader(title: String(localized: "detail.title"), back: .init())

                if let session = content.session(key: sessionKey),
                    let dto = ArchiveSessionRecord.dto(session: session, content: content, converter: model.converter)
                {
                    ShareReportCardView(dto: dto, style: .page, weightUnit: model.settings.weightUnit.rawValue)
                }
                VStack(alignment: .leading, spacing: FCPrimitives.space2) {
                    FCListRowDivider()
                    FCStatusLabel(
                        text: String(localized: "archive.viewer.session.readonly"),
                        symbolName: "info",
                        badgeColor: FCSemanticColors.actionPrimary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, FCPrimitives.space2)
                    .accessibilityIdentifier(FCAccessibilityID.archiveSessionReadonly)
                }
            }
            .padding(.horizontal, FCPrimitives.space4)
            .padding(.bottom, FCPrimitives.space4)
        }
        .background(FCSemanticColors.surfacePage)
        .fcSecondaryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FCAccessibilityID.archiveSessionRoot)
    }
}
