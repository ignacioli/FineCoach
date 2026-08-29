#if DEBUG
    import FineCoach
    import UIKit
    import XCTest

    final class ShareReportRendererTests: XCTestCase {
        private let sessionDate = Date(timeIntervalSince1970: 1_700_000_000)
        private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func testSameDTOAndScaleRendersDeterministicPagesAndFilenames() throws {
            let renderer = ShareReportRenderer()
            let dto = try makeNamedDTO()
            let first = try renderer.render(dto: dto, scale: CGFloat(2))
            let second = try renderer.render(dto: dto, scale: CGFloat(2))
            XCTAssertEqual(first.pages, second.pages)
            XCTAssertEqual(first.filenames, second.filenames)
            assertValidRender(first, leakTokens: leakTokens(for: dto))
        }

        func testEachRenderedPageStartsWithPNGMagic() throws {
            let result = try ShareReportRenderer().render(dto: try makeNamedDTO(), scale: CGFloat(1))
            XCTAssertGreaterThanOrEqual(result.pages.count, 1)
            for page in result.pages {
                XCTAssertGreaterThanOrEqual(page.count, pngSignature.count)
                XCTAssertEqual(Data(page.prefix(pngSignature.count)), pngSignature)
            }
        }

        func testFilenamesAreGenericReportBasenamesWithoutStudentOrDateLeak() throws {
            let dto = try makeNamedDTO()
            let result = try ShareReportRenderer().render(dto: dto, scale: CGFloat(2))
            XCTAssertEqual(result.pages.count, result.filenames.count)
            XCTAssertGreaterThanOrEqual(result.filenames.count, 1)
            for (index, filename) in result.filenames.enumerated() {
                XCTAssertEqual(filename, String(format: "report-%03d.png", index + 1))
                XCTAssertEqual((filename as NSString).lastPathComponent, filename)
                XCTAssertFalse(filename.contains("/"))
            }
            let forbiddenFilenameTokens = leakTokens(for: dto) + ["林青"]
            for filename in result.filenames {
                for token in forbiddenFilenameTokens {
                    XCTAssertFalse(
                        filename.contains(token),
                        "generic filename must not contain DTO text"
                    )
                }
            }
        }

        func testLargeDTOPeakRasterBytesStayWithinBudget() throws {
            XCTAssertEqual(ShareReportRenderer.peakRasterBudgetBytes, 32 * 1024 * 1024)
            let dto = try makeLargeDTO()
            let result = try ShareReportRenderer().render(dto: dto, scale: CGFloat(2))
            assertValidRender(result, leakTokens: leakTokens(for: dto))
            XCTAssertLessThanOrEqual(result.peakRasterBytes, ShareReportRenderer.peakRasterBudgetBytes)
        }

        func testContentOrderStableForIdenticalDTOsAndValidWhenSummaryDiffers() throws {
            let renderer = ShareReportRenderer()
            let firstDTO = try makeNamedDTO()
            let secondDTO = try makeNamedDTO()
            let first = try renderer.render(dto: firstDTO, scale: CGFloat(2))
            let second = try renderer.render(dto: secondDTO, scale: CGFloat(2))
            XCTAssertEqual(first, second)
            assertValidRender(first, leakTokens: leakTokens(for: firstDTO))

            let alteredDTO = try makeNamedDTO(studentFacingSummary: "节奏放慢，髋膝保持同向。")
            let altered = try renderer.render(dto: alteredDTO, scale: CGFloat(2))
            assertValidRender(altered, leakTokens: leakTokens(for: alteredDTO))
        }

        func testRendererAPISurfaceAcceptsDTOOnly() throws {
            let renderer = ShareReportRenderer()
            let dto = try makeNamedDTO()
            try rendererAcceptsOnlyDTO(renderer, dto)

            let result = try renderer.render(dto: dto, scale: CGFloat(1))
            assertValidRender(result, leakTokens: leakTokens(for: dto))
            let resultLabels = Set(Mirror(reflecting: result).children.compactMap(\.label))
            XCTAssertEqual(resultLabels, ["filenames", "pages", "peakRasterBytes"])

            let rendererLabels = Mirror(reflecting: renderer).children.compactMap(\.label)
            XCTAssertFalse(rendererLabels.contains { $0.localizedCaseInsensitiveContains("student") })
            XCTAssertFalse(rendererLabels.contains { $0.localizedCaseInsensitiveContains("session") })
            XCTAssertFalse(rendererLabels.contains { $0.localizedCaseInsensitiveContains("note") })
        }

        func testEmptyNameDTORendersAtLeastOnePNG() throws {
            let dto = ShareReportDTO(
                schemaVersion: 1,
                studentDisplayName: nil,
                sessionDateUTC: nil,
                durationSeconds: nil,
                trainingFocus: nil,
                studentFacingSummary: nil,
                trainingVolume: nil,
                exercises: []
            )
            let result = try ShareReportRenderer().render(dto: dto, scale: CGFloat(1))
            XCTAssertGreaterThanOrEqual(result.pages.count, 1)
            assertValidRender(result, leakTokens: ["林青"])
        }

        private func makeNamedDTO(studentFacingSummary: String? = "保持髋膝同向，动作节奏稳定。") throws -> ShareReportDTO {
            ShareReportDTO(
                schemaVersion: 1,
                studentDisplayName: "林青",
                sessionDateUTC: sessionDate,
                durationSeconds: try DecimalValue("3600"),
                trainingFocus: "下肢力量",
                studentFacingSummary: studentFacingSummary,
                trainingVolume: try DecimalValue("2400"),
                exercises: [
                    ShareReportExerciseDTO(
                        displayName: "杠铃深蹲",
                        confirmedSets: [
                            ShareReportSetDTO(
                                orderIndex: 0,
                                recordMode: .weightReps,
                                weightValue: try DecimalValue("60"),
                                repetitionCount: try DecimalValue("8"),
                                durationSeconds: nil,
                                unit: .kilograms,
                                side: .none,
                                leftValue: nil,
                                rightValue: nil
                            )
                        ]
                    )
                ]
            )
        }

        private func makeLargeDTO() throws -> ShareReportDTO {
            let weight = try DecimalValue("40")
            let reps = try DecimalValue("8")
            let exercises: [ShareReportExerciseDTO] = (1...40).map { exerciseIndex in
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
                return ShareReportExerciseDTO(
                    displayName: "动作\(exerciseIndex)",
                    confirmedSets: sets
                )
            }
            return ShareReportDTO(
                schemaVersion: 1,
                studentDisplayName: "林青",
                sessionDateUTC: sessionDate,
                durationSeconds: try DecimalValue("5400"),
                trainingFocus: "下肢力量",
                studentFacingSummary: "保持髋膝同向，动作节奏稳定。",
                trainingVolume: try DecimalValue("12800"),
                exercises: exercises
            )
        }

        private func leakTokens(for dto: ShareReportDTO) -> [String] {
            var tokens = ["林青"]
            if let name = dto.studentDisplayName {
                tokens.append(name)
            }
            if let date = dto.sessionDateUTC {
                tokens.append(ISO8601DateFormatter().string(from: date))
                let day = DateFormatter()
                day.locale = Locale(identifier: "en_US_POSIX")
                day.timeZone = TimeZone(secondsFromGMT: 0)
                day.dateFormat = "yyyy-MM-dd"
                tokens.append(day.string(from: date))
            }
            if let focus = dto.trainingFocus {
                tokens.append(focus)
            }
            if let summary = dto.studentFacingSummary {
                tokens.append(summary)
            }
            tokens.append(contentsOf: dto.exercises.map(\.displayName))
            return tokens.filter { !$0.isEmpty }
        }

        private func assertValidRender(
            _ result: ShareReportRenderResult,
            leakTokens: [String],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertGreaterThanOrEqual(result.pages.count, 1, file: file, line: line)
            XCTAssertEqual(result.pages.count, result.filenames.count, file: file, line: line)
            XCTAssertLessThanOrEqual(
                result.peakRasterBytes,
                ShareReportRenderer.peakRasterBudgetBytes,
                file: file,
                line: line
            )
            for (index, page) in result.pages.enumerated() {
                XCTAssertGreaterThanOrEqual(page.count, pngSignature.count, file: file, line: line)
                XCTAssertEqual(Data(page.prefix(pngSignature.count)), pngSignature, file: file, line: line)
                let filename = result.filenames[index]
                XCTAssertEqual(filename, String(format: "report-%03d.png", index + 1), file: file, line: line)
                XCTAssertEqual((filename as NSString).lastPathComponent, filename, file: file, line: line)
                for token in leakTokens {
                    XCTAssertFalse(filename.contains(token), file: file, line: line)
                }
            }
        }
    }

    /// Compile-time canary: `render(dto:scale:)` is the only renderer entry.
    /// There is no `render(session:)` (or Student / NSManagedObject / note) overload; do not add one here.
    private func rendererAcceptsOnlyDTO(_ renderer: ShareReportRenderer, _ dto: ShareReportDTO) throws {
        _ = try renderer.render(dto: dto, scale: 1)
    }
#else
    import FineCoach
    import XCTest

    final class ShareReportRendererTests: XCTestCase {
        func testReleaseKeepsShareReportRendererBudgetWithoutUIKitRenderer() {
            XCTAssertEqual(ShareReportRenderer.peakRasterBudgetBytes, 32 * 1024 * 1024)
        }
    }
#endif
