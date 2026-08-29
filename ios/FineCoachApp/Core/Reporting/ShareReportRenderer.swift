import Foundation
import UIKit

public struct ShareReportRenderResult: Equatable, Sendable {
    public let pages: [Data]
    public let filenames: [String]
    public let peakRasterBytes: Int

    public init(pages: [Data], filenames: [String], peakRasterBytes: Int) {
        self.pages = pages
        self.filenames = filenames
        self.peakRasterBytes = peakRasterBytes
    }
}

public struct ShareReportRenderer: Sendable {
    public static let peakRasterBudgetBytes = 32 * 1024 * 1024

    private static let pagePointSize = CGSize(width: 390, height: 844)
    private static let horizontalInset: CGFloat = 24
    private static let topInset: CGFloat = 32
    private static let lineSpacing: CGFloat = 6
    private static let sectionSpacing: CGFloat = 16

    public init() {}

    public func render(dto: ShareReportDTO, scale: CGFloat) throws -> ShareReportRenderResult {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let pageSize = Self.pagePointSize
        let pixelWidth = Int((pageSize.width * scale).rounded(.up))
        let pixelHeight = Int((pageSize.height * scale).rounded(.up))
        let peakRasterBytes = pixelWidth * pixelHeight * 4
        guard peakRasterBytes <= Self.peakRasterBudgetBytes else {
            throw DomainError.invalidFileOperation
        }

        let attributes = Self.textAttributes
        let grouped = paginate(layoutBlocks(dto: dto), pageSize: pageSize, attributes: attributes)
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)
        let pages = grouped.map { lines in
            renderer.pngData { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
                var y = Self.topInset
                let maxWidth = pageSize.width - Self.horizontalInset * 2
                for (lineIndex, line) in lines.enumerated() {
                    let needed = Self.lineHeight(line, maxWidth: maxWidth, attributes: attributes)
                    (line as NSString).draw(
                        with: CGRect(
                            x: Self.horizontalInset,
                            y: y,
                            width: maxWidth,
                            height: needed
                        ),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    )
                    y += needed
                    if lineIndex == 0 {
                        y += Self.sectionSpacing / 2
                    }
                }
            }
        }
        let filenames = pages.enumerated().map { index, _ in
            String(format: "report-%03d.png", index + 1)
        }
        return ShareReportRenderResult(pages: pages, filenames: filenames, peakRasterBytes: peakRasterBytes)
    }

    private func layoutBlocks(dto: ShareReportDTO) -> [String] {
        ShareReportPolicy.previewLines(for: dto)
    }

    private func paginate(
        _ blocks: [String],
        pageSize: CGSize,
        attributes: [NSAttributedString.Key: Any]
    ) -> [[String]] {
        let maxWidth = pageSize.width - Self.horizontalInset * 2
        let maxY = pageSize.height - Self.topInset
        var pages: [[String]] = []
        var current: [String] = []
        var y = Self.topInset
        for line in blocks {
            let needed = Self.lineHeight(line, maxWidth: maxWidth, attributes: attributes)
            let extra = current.isEmpty ? Self.sectionSpacing / 2 : 0
            if !current.isEmpty, y + needed + extra > maxY {
                pages.append(current)
                current = []
                y = Self.topInset
            }
            current.append(line)
            y += needed + extra
        }
        if !current.isEmpty {
            pages.append(current)
        }
        return pages.isEmpty ? [["训练报告"]] : pages
    }

    private static func lineHeight(
        _ line: String,
        maxWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let textSize = (line as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral.size
        return max(ceil(textSize.height), 20) + lineSpacing
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.black,
        ]
    }
}
