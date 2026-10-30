import XCTest

@testable import FineCoach

final class FCAmbientEmptySceneTests: XCTestCase {
    func testSteamEnvelopeAndPhaseOffsets() {
        let period = 3.6
        let start = FCAmbientEmptyScene.frame(at: 0, blinkSchedule: [])
        XCTAssertEqual(start.steam.map(\.opacity), [0, 0, 0])
        let peak = FCAmbientEmptyScene.frame(at: period * 0.25, blinkSchedule: [])
        XCTAssertEqual(peak.steam[0].opacity, 0.6, accuracy: 0.000001)
        let tail = FCAmbientEmptyScene.frame(at: period * 0.7, blinkSchedule: [])
        XCTAssertEqual(tail.steam[0].opacity, 0.35, accuracy: 0.000001)
        let end = FCAmbientEmptyScene.frame(at: period, blinkSchedule: [])
        XCTAssertEqual(end.steam[0].opacity, 0, accuracy: 0.000001)
        for index in 0..<3 {
            let shifted = FCAmbientEmptyScene.frame(at: period * 0.25 + Double(index) * 1.2, blinkSchedule: [])
            XCTAssertEqual(shifted.steam[index].opacity, peak.steam[0].opacity, accuracy: 0.000001)
            XCTAssertEqual(shifted.steam[index].x, peak.steam[0].x, accuracy: 0.000001)
            XCTAssertEqual(shifted.steam[index].y, peak.steam[0].y, accuracy: 0.000001)
        }
    }

    func testBreathAndInjectedBlinkWindows() {
        XCTAssertEqual(FCAmbientEmptyScene.frame(at: 0, blinkSchedule: []).breathScale, 1)
        XCTAssertEqual(FCAmbientEmptyScene.frame(at: 2.1, blinkSchedule: []).breathScale, 1.008, accuracy: 0.000001)
        let schedule = [4.0, 4.32]
        for (time, closed) in [(3.99, false), (4.0, true), (4.139, true), (4.14, false), (4.32, true), (4.461, false)] {
            XCTAssertEqual(FCAmbientEmptyScene.frame(at: time, blinkSchedule: schedule).closedEyes, closed)
        }
    }

    func testReducedMotionFrameIsStillWithTwoSteamWisps() {
        for time in [0.0, 2.1, 4.0, 100.0] {
            let frame = FCAmbientEmptyScene.frame(at: time, blinkSchedule: [time], reducedMotion: true)
            XCTAssertEqual(frame.breathScale, 1)
            XCTAssertFalse(frame.closedEyes)
            XCTAssertEqual(frame.steam.count, 2)
            for steam in frame.steam {
                XCTAssertEqual(steam.opacity, 0.45)
                XCTAssertEqual(steam.x, 0)
                XCTAssertEqual(steam.y, 0)
            }
        }
    }

    func testBlinkScheduleUsesInjectedGeneratorAndApprovedIntervals() {
        struct Generator: RandomNumberGenerator {
            var state: UInt64 = 42
            mutating func next() -> UInt64 {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                return state
            }
        }
        var first = Generator()
        var second = Generator()
        for _ in 0..<100 {
            let schedule = FCAmbientEmptyScene.makeBlinkSchedule(after: 10, using: &first)
            XCTAssertEqual(schedule, FCAmbientEmptyScene.makeBlinkSchedule(after: 10, using: &second))
            XCTAssertTrue((14...17).contains(schedule[0]))
            XCTAssertTrue((1...2).contains(schedule.count))
            if schedule.count == 2 { XCTAssertEqual(schedule[1] - schedule[0], 0.32, accuracy: 0.000001) }
        }
    }

    func testCafeAssetsHaveRetinaSizesAndAlpha() throws {
        for name in ["rabbit", "blink", "table"] {
            let directory = appRoot.appendingPathComponent("Resources/Assets.xcassets/mascot-cafe-\(name).imageset")
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json")))
                    as? [String: Any])
            let images = try XCTUnwrap(json["images"] as? [[String: String]])
            XCTAssertEqual(Set(images.compactMap { $0["filename"] == nil ? nil : $0["scale"] }), ["2x", "3x"])
            for (scale, side) in [("2x", 440), ("3x", 660)] {
                let filename = try XCTUnwrap(images.first { $0["scale"] == scale }?["filename"])
                let data = try Data(contentsOf: directory.appendingPathComponent(filename))
                XCTAssertGreaterThan(data.count, 26)
                XCTAssertEqual(data[16..<20].reduce(0) { $0 << 8 | Int($1) }, side)
                XCTAssertEqual(data[20..<24].reduce(0) { $0 << 8 | Int($1) }, side)
                XCTAssertEqual(data[25], 6)
            }
        }
    }

    func testSceneIsDecorativeAndPausesForVisibilityPowerAndAccessibility() throws {
        let source = try String(
            contentsOf: appRoot.appendingPathComponent("DesignSystem/Components/FCAmbientEmptyScene.swift"),
            encoding: .utf8)
        for required in [
            "accessibilityHidden(true)", "allowsHitTesting(false)", "accessibilityReduceMotion",
            "scenePhase != .active",
            "isLowPowerModeEnabled", "NSProcessInfoPowerStateDidChange", ".onDisappear",
            "TimelineView(.animation(paused: paused))",
            "elapsed +=", "startedAt = nil", "FCMotion.ambientBreathAnchor", "FCSemanticColors.textDisabled",
        ] { XCTAssertTrue(source.contains(required), required) }
        for forbidden in ["repeatForever", "sensoryFeedback", "CoreData", "UserDefaults", "Task.sleep"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        let decimal = try NSRegularExpression(pattern: #"\b\d+\.\d+\b"#)
        XCTAssertEqual(decimal.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)), 0)
        let rabbit = try XCTUnwrap(source.range(of: "layer(\"mascot-cafe-rabbit\")"))
        let blink = try XCTUnwrap(source.range(of: "layer(\"mascot-cafe-blink\")"))
        let table = try XCTUnwrap(source.range(of: "layer(\"mascot-cafe-table\")"))
        let steam = try XCTUnwrap(source.range(of: "Canvas {"))
        XCTAssertLessThan(rabbit.lowerBound, blink.lowerBound)
        XCTAssertLessThan(blink.lowerBound, table.lowerBound)
        XCTAssertLessThan(table.lowerBound, steam.lowerBound)
    }

    private var appRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("FineCoachApp")
    }
}
