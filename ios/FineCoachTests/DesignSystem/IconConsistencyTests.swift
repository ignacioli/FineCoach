import UIKit
import XCTest

@testable import FineCoach

/// T046 (plan §9-6): the 21 equipment icons in `Assets.xcassets` are
/// byte-identical to `design/m1-b-hifi/icons/*.svg`, use viewBox 24, stroke
/// width 2 with the CX-D13 kettlebell fill exception, and render as templates — replacing manual review.
/// T065: the §7.1 exercise → icon table.
final class IconConsistencyTests: XCTestCase {
    // MARK: T046 — asset ↔ design original

    func testEveryDesignIconHasExactlyOneEnumCaseAndViceVersa() throws {
        let designNames = try FileManager.default
            .contentsOfDirectory(atPath: try designIconsDirectory().path)
            .filter { $0.hasSuffix(".svg") }
            .map { String($0.dropLast(4)) }
        XCTAssertEqual(Set(designNames), Set(FCEquipmentIcon.allCases.map(\.rawValue)))
        XCTAssertEqual(FCEquipmentIcon.allCases.count, 21)
    }

    func testAssetSVGsAreByteIdenticalToDesignOriginals() throws {
        let design = try designIconsDirectory()
        let assets = try assetCatalogDirectory()
        for icon in FCEquipmentIcon.allCases {
            let original = try Data(contentsOf: design.appendingPathComponent("\(icon.rawValue).svg"))
            let imported = try Data(
                contentsOf: assets.appendingPathComponent("\(icon.assetName).imageset/\(icon.rawValue).svg")
            )
            XCTAssertEqual(
                imported, original, "\(icon.assetName) differs from design/m1-b-hifi/icons/\(icon.rawValue).svg")
        }
    }

    func testSVGGeometryIsViewBox24Stroke2NoFill() throws {
        let design = try designIconsDirectory()
        for icon in FCEquipmentIcon.allCases {
            let svg = try String(contentsOf: design.appendingPathComponent("\(icon.rawValue).svg"), encoding: .utf8)
            XCTAssertTrue(svg.contains(#"viewBox="0 0 24 24""#), "\(icon.rawValue): viewBox")
            let strokeWidths = attributeValues("stroke-width", in: svg)
            XCTAssertFalse(strokeWidths.isEmpty, "\(icon.rawValue): no stroke-width")
            XCTAssertEqual(Set(strokeWidths), ["2"], "\(icon.rawValue): stroke widths \(strokeWidths)")
            let expectedFills: Set<String> = icon == .kettlebell ? ["none", "#2A2822"] : ["none"]
            XCTAssertEqual(Set(attributeValues("fill", in: svg)), expectedFills, "\(icon.rawValue): fill")
        }
    }

    func testAssetsRenderAsTemplatesAndLoadFromTheAppBundle() throws {
        let assets = try assetCatalogDirectory()
        for icon in FCEquipmentIcon.allCases {
            let contents = try Data(
                contentsOf: assets.appendingPathComponent("\(icon.assetName).imageset/Contents.json"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any])
            let properties = try XCTUnwrap(json["properties"] as? [String: Any], icon.assetName)
            XCTAssertEqual(properties["template-rendering-intent"] as? String, "template", icon.assetName)
            XCTAssertNotNil(UIImage(named: icon.assetName, in: .main, with: nil), "\(icon.assetName) not in app bundle")
        }
    }

    // MARK: T065 — §7.1 exercise → icon table

    func testMappingTableMatchesDesignSystem() {
        for equipmentClass in ["杠铃", "哑铃", "徒手", "绳索", "史密斯机", "壶铃", "哈克机", "悍马机", "悬挂带", "单杠", "弹力带"] {
            let muscles: [String?] = ExerciseCatalogBrowse.muscleGroupOrder.map { $0 } + [nil]
            for muscle in muscles {
                XCTAssertNotNil(FCEquipmentIcon.icon(equipmentClass: equipmentClass, primaryMuscleGroup: muscle))
            }
        }
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "杠铃", primaryMuscleGroup: "背"), .barbell)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "哑铃", primaryMuscleGroup: nil), .dumbbell)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "徒手", primaryMuscleGroup: "核心"), .bodyweight)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "绳索", primaryMuscleGroup: "胸"), .cableCrossover)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "史密斯机", primaryMuscleGroup: "大腿"), .smithMachine)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "壶铃", primaryMuscleGroup: "臀"), .kettlebell)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "哈克机", primaryMuscleGroup: "大腿"), .hackSquat)

        let machine: [String: FCEquipmentIcon?] = [
            "胸": .pecDeck, "肩": .shoulderPress, "大腿": .legExtension, "臀": .hipAdduction,
            "小腿": .hackSquat, "背": .tbarRow, "臂": nil, "核心": nil,
        ]
        for (muscle, expected) in machine {
            XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "固定器械", primaryMuscleGroup: muscle), expected, muscle)
        }
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "悍马机", primaryMuscleGroup: nil), .plateLoaded)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "悬挂带", primaryMuscleGroup: nil), .suspensionTrainer)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "单杠", primaryMuscleGroup: nil), .pullUpBar)
        XCTAssertEqual(FCEquipmentIcon.icon(equipmentClass: "弹力带", primaryMuscleGroup: nil), .resistanceBand)
        for equipmentClass in ["其他"] {
            XCTAssertNil(FCEquipmentIcon.icon(equipmentClass: equipmentClass, primaryMuscleGroup: "胸"))
        }
        XCTAssertNil(FCEquipmentIcon.icon(equipmentClass: nil, primaryMuscleGroup: nil))
    }

    func testCustomExerciseHasNoIcon() {
        XCTAssertNil(FCEquipmentIcon.icon(forExerciseID: "custom-not-in-catalog"))
    }

    func testEveryBundledCatalogExerciseResolvesThroughTheTable() {
        let facets = PlaceholderExerciseCatalogLoader.facetsByID()
        XCTAssertFalse(facets.isEmpty)
        for (id, facet) in facets {
            XCTAssertEqual(
                FCEquipmentIcon.icon(forExerciseID: id),
                FCEquipmentIcon.icon(equipmentClass: facet.equipmentClass, primaryMuscleGroup: facet.primaryMuscleGroup)
            )
        }
    }

    // MARK: Helpers

    private func attributeValues(_ name: String, in svg: String) -> [String] {
        let pattern = "(?<![\\w-])\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(svg.startIndex..., in: svg)
        return regex.matches(in: svg, range: range).compactMap { match in
            Range(match.range(at: 1), in: svg).map { String(svg[$0]) }
        }
    }

    /// `ios/` located from this file's `#filePath` (the simulator reads the
    /// host filesystem; same approach as `DesignValueScanTests`). Fails — not
    /// skips — when unresolvable, because this is the T046 acceptance gate.
    private func iosRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignSystem/
            .deletingLastPathComponent()  // FineCoachTests/
            .deletingLastPathComponent()  // ios/
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("FineCoachApp").path) else {
            XCTFail("cannot resolve ios/ from #filePath: \(root.path)")
            throw CocoaError(.fileNoSuchFile)
        }
        return root
    }

    private func designIconsDirectory() throws -> URL {
        try iosRoot().deletingLastPathComponent().appendingPathComponent("design/m1-b-hifi/icons")
    }

    private func assetCatalogDirectory() throws -> URL {
        try iosRoot().appendingPathComponent("FineCoachApp/Resources/Assets.xcassets")
    }
}
