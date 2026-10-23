#if DEBUG
    import UIKit
    import XCTest

    @testable import FineCoach

    /// The share flow's only renderer (`ShareReportCardRenderer`: one PNG, or ordered 2× pages).
    /// Generic filenames are owned by `TempReportLease` and covered in
    /// `TempReportLifecycleTests`; this file covers the image itself.
    @MainActor
    final class ShareReportCardRendererTests: XCTestCase {
        private let sessionDate = Date(timeIntervalSince1970: 1_700_000_000)
        private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func testShortReportIsOnePNGAtTwiceTheCardWidth() throws {
            let pages = try ShareReportCardRenderer.render(dto: try makeDTO(exerciseCount: 1))
            XCTAssertEqual(pages.count, 1)
            try assertFullResolutionPage(pages[0])
        }

        /// Owner 2026-09-29: a report too long for one image is split into
        /// ordered images, each still at 2× -- never downscaled.
        func testLongReportSplitsIntoFullResolutionPagesWithinLimits() throws {
            XCTAssertEqual(ShareReportCardRenderer.peakRasterBudgetBytes, 32 * 1024 * 1024)
            let dto = try makeDTO(exerciseCount: 40)
            let pages = try ShareReportCardRenderer.render(dto: dto)
            XCTAssertGreaterThan(pages.count, 1)
            for page in pages {
                try assertFullResolutionPage(page)
            }

            // Every block appears exactly once, in reading order, and the
            // footer only ends the last page.
            let layout = try ShareReportCardRenderer.paginate(dto: dto)
            XCTAssertEqual(layout.flatMap { $0 }, ShareReportCardView.blocks(for: dto))
            XCTAssertEqual(layout.last?.last, .footer)
        }

        func testEmptyDTORendersAPNG() throws {
            let dto = ShareReportDTO(
                schemaVersion: 2,
                studentDisplayName: nil,
                sessionDateUTC: nil,
                durationSeconds: nil,
                trainingFocus: nil,
                studentFacingSummary: nil,
                trainingVolume: nil,
                exercises: []
            )
            let pages = try ShareReportCardRenderer.render(dto: dto)
            XCTAssertEqual(pages.count, 1)
            try assertFullResolutionPage(pages[0])
        }

        func testGainsWithProgressAndMilestoneRenderAtFullResolution() throws {
            let base = try makeDTO(exerciseCount: 1)
            let previous = try XCTUnwrap(base.exercises.first?.confirmedSets.first)
            let current = ShareReportSetDTO(
                orderIndex: 0, recordMode: .weightReps, weightValue: try DecimalValue("40"),
                repetitionCount: try DecimalValue("10"), durationSeconds: nil,
                unit: .kilograms, side: .none, leftValue: nil, rightValue: nil)
            let dto = ShareReportDTO(
                schemaVersion: ShareReportPolicy.schemaVersion, studentDisplayName: base.studentDisplayName,
                sessionDateUTC: base.sessionDateUTC, durationSeconds: base.durationSeconds,
                trainingFocus: base.trainingFocus, studentFacingSummary: base.studentFacingSummary,
                trainingVolume: base.trainingVolume, exercises: base.exercises,
                personalBests: [
                    .init(displayName: "合成纪录动作", kind: .highestWeight, weightValue: try DecimalValue("45"))
                ],
                gainRows: [
                    .init(
                        displayName: "合成进步动作", isNewRecord: true, previous: previous, current: current)
                ],
                milestoneSessionNumber: 10)
            let blocks = ShareReportCardView.blocks(for: dto)
            XCTAssertEqual(blocks.filter { $0 == .personalBests }.count, 1)
            let pages = try ShareReportCardRenderer.render(dto: dto)
            XCTAssertEqual(pages.count, 1)
            try assertFullResolutionPage(pages[0])
            // Neither progress-only nor milestone-only reports may lose the section.
            for milestone in [Int?.none, 10] {
                let single = ShareReportDTO(
                    schemaVersion: ShareReportPolicy.schemaVersion, studentDisplayName: nil,
                    sessionDateUTC: nil, durationSeconds: nil, trainingFocus: nil,
                    studentFacingSummary: nil, trainingVolume: nil, exercises: [],
                    gainRows: milestone == nil ? dto.gainRows : [], milestoneSessionNumber: milestone)
                XCTAssertTrue(ShareReportCardView.blocks(for: single).contains(.personalBests))
            }
        }

        private func assertFullResolutionPage(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(Data(data.prefix(pngSignature.count)), pngSignature, file: file, line: line)
            let image = try XCTUnwrap(UIImage(data: data), file: file, line: line)
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            XCTAssertEqual(pixelWidth, ShareReportCardRenderer.cardWidth * 2, accuracy: 1, file: file, line: line)
            XCTAssertLessThanOrEqual(pixelHeight, ShareReportCardRenderer.maxPagePixelHeight, file: file, line: line)
            XCTAssertLessThanOrEqual(
                Int(pixelWidth * pixelHeight) * 4, ShareReportCardRenderer.peakRasterBudgetBytes, file: file, line: line
            )
        }

        private func makeDTO(exerciseCount: Int) throws -> ShareReportDTO {
            let weight = try DecimalValue("40")
            let reps = try DecimalValue("8")
            let exercises: [ShareReportExerciseDTO] = (1...exerciseCount).map { exerciseIndex in
                let sets: [ShareReportSetDTO] = (0..<8).map { setIndex in
                    ShareReportSetDTO(
                        orderIndex: UInt32(setIndex),
                        recordMode: .weightReps,
                        weightValue: weight,
                        repetitionCount: reps,
                        durationSeconds: nil,
                        unit: .kilograms,
                        side: .none,
                        leftValue: nil,
                        rightValue: nil
                    )
                }
                return ShareReportExerciseDTO(displayName: "动作\(exerciseIndex)", confirmedSets: sets)
            }
            return ShareReportDTO(
                schemaVersion: 2,
                studentDisplayName: "林青",
                sessionDateUTC: sessionDate,
                durationSeconds: try DecimalValue("5400"),
                trainingFocus: "下肢力量",
                studentFacingSummary: "保持髋膝同向，动作节奏稳定。",
                trainingVolume: try DecimalValue("12800"),
                exercises: exercises
            )
        }
    }
#endif
