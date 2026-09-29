#if DEBUG
    import UIKit
    import XCTest

    @testable import FineCoach

    /// The share flow's only renderer (`ShareReportCardRenderer`, one long PNG).
    /// Generic filenames are owned by `TempReportLease` and covered in
    /// `TempReportLifecycleTests`; this file covers the image itself.
    @MainActor
    final class ShareReportCardRendererTests: XCTestCase {
        private let sessionDate = Date(timeIntervalSince1970: 1_700_000_000)
        private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func testRendersOnePNGAtCardWidth() throws {
            let data = try ShareReportCardRenderer.render(dto: try makeDTO(exerciseCount: 1))
            XCTAssertEqual(Data(data.prefix(pngSignature.count)), pngSignature)
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertEqual(
                image.size.width * image.scale,
                ShareReportCardRenderer.cardWidth * 2,
                accuracy: 1
            )
        }

        func testLongReportStaysWithinPeakRasterBudget() throws {
            XCTAssertEqual(ShareReportCardRenderer.peakRasterBudgetBytes, 32 * 1024 * 1024)
            let data = try ShareReportCardRenderer.render(dto: try makeDTO(exerciseCount: 40))
            let image = try XCTUnwrap(UIImage(data: data))
            let pixelWidth = Int((image.size.width * image.scale).rounded())
            let pixelHeight = Int((image.size.height * image.scale).rounded())
            XCTAssertLessThanOrEqual(pixelWidth * pixelHeight * 4, ShareReportCardRenderer.peakRasterBudgetBytes)
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
            let data = try ShareReportCardRenderer.render(dto: dto)
            XCTAssertEqual(Data(data.prefix(pngSignature.count)), pngSignature)
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
