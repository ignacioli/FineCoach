import SwiftUI

public struct FCAmbientEmptyScene: View {
    let side: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?
    @State private var blinkSchedule: [TimeInterval] = []

    public init(side: CGFloat) {
        self.side = side
    }

    private var paused: Bool {
        reduceMotion || !visible || scenePhase != .active || lowPower
    }

    public var body: some View {
        TimelineView(.animation(paused: paused)) { context in
            let time = elapsed + (startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0)
            let frame = Self.frame(at: time, blinkSchedule: blinkSchedule, reducedMotion: reduceMotion)
            ZStack {
                ZStack {
                    layer("mascot-cafe-rabbit")
                    layer("mascot-cafe-blink").opacity(frame.closedEyes ? 1 : 0)
                }
                .scaleEffect(frame.breathScale, anchor: FCMotion.ambientBreathAnchor)
                layer("mascot-cafe-table")
                Canvas { context, _ in
                    let ratio = side / FCMotion.ambientReferenceSide
                    for (index, steam) in frame.steam.enumerated() {
                        var path = Self.steamPath(index: index)
                        path = path.applying(
                            CGAffineTransform(translationX: steam.x, y: steam.y)
                                .concatenating(CGAffineTransform(scaleX: ratio, y: ratio)))
                        context.stroke(
                            path, with: .color(FCSemanticColors.textDisabled.opacity(steam.opacity)),
                            style: StrokeStyle(lineWidth: FCMotion.ambientSteamLineWidth * ratio, lineCap: .round))
                    }
                }
            }
            .onChange(of: time) { _, value in
                if value >= (blinkSchedule.last ?? 0) - FCMotion.ambientBlinkInterval.upperBound {
                    extendBlinkSchedule()
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            if blinkSchedule.isEmpty { extendBlinkSchedule() }
            visible = true
            updateClock()
        }
        .onDisappear {
            visible = false
            updateClock()
        }
        .onChange(of: paused) { _, _ in updateClock() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            updateClock()
        }
    }

    private func layer(_ name: String) -> some View {
        Image(name).resizable().scaledToFit()
    }

    private func updateClock(now: Date = .now) {
        if paused {
            if let startedAt { elapsed += max(0, now.timeIntervalSince(startedAt)) }
            startedAt = nil
        } else if startedAt == nil {
            startedAt = now
        }
    }

    private func extendBlinkSchedule() {
        var generator = SystemRandomNumberGenerator()
        blinkSchedule += Self.makeBlinkSchedule(after: blinkSchedule.last ?? 0, using: &generator)
    }

    static func makeBlinkSchedule<R: RandomNumberGenerator>(
        after start: TimeInterval, using generator: inout R
    ) -> [TimeInterval] {
        let next = start + Double.random(in: FCMotion.ambientBlinkInterval, using: &generator)
        if Double.random(in: 0..<1, using: &generator) < FCMotion.ambientBlinkDoubleProbability {
            return [next, next + FCMotion.ambientBlinkDoubleDelay]
        }
        return [next]
    }

    struct Steam {
        let opacity: Double
        let x: CGFloat
        let y: CGFloat
    }

    struct Frame {
        let steam: [Steam]
        let breathScale: Double
        let closedEyes: Bool
    }

    static func frame(at elapsed: TimeInterval, blinkSchedule: [TimeInterval], reducedMotion: Bool = false) -> Frame {
        if reducedMotion {
            return Frame(
                steam: Array(repeating: Steam(opacity: FCMotion.ambientSteamStaticOpacity, x: 0, y: 0), count: 2),
                breathScale: 1, closedEyes: false)
        }
        let steam = FCMotion.ambientSteamOrigins.indices.map { index -> Steam in
            let local = elapsed - Double(index) * FCMotion.ambientSteamPhase
            guard local >= 0 else { return Steam(opacity: 0, x: 0, y: 0) }
            let progress =
                local.truncatingRemainder(dividingBy: FCMotion.ambientSteamPeriod) / FCMotion.ambientSteamPeriod
            let opacity: Double
            if progress <= FCMotion.ambientSteamPeakTime {
                opacity =
                    FCMotion.ambientSteamPeakOpacity * FCMotion.ambientEase(progress / FCMotion.ambientSteamPeakTime)
            } else if progress <= FCMotion.ambientSteamTailTime {
                let fraction =
                    (progress - FCMotion.ambientSteamPeakTime)
                    / (FCMotion.ambientSteamTailTime - FCMotion.ambientSteamPeakTime)
                opacity =
                    FCMotion.ambientSteamPeakOpacity
                    + (FCMotion.ambientSteamTailOpacity - FCMotion.ambientSteamPeakOpacity)
                    * FCMotion.ambientEase(fraction)
            } else {
                opacity =
                    FCMotion.ambientSteamTailOpacity
                    * (1
                        - FCMotion.ambientEase(
                            (progress - FCMotion.ambientSteamTailTime) / (1 - FCMotion.ambientSteamTailTime)))
            }
            return Steam(
                opacity: opacity, x: FCMotion.ambientSteamDrift * FCMotion.ambientEase(progress),
                y: -FCMotion.ambientSteamRise * FCMotion.ambientEase(progress))
        }
        let breathProgress =
            elapsed.truncatingRemainder(dividingBy: FCMotion.ambientBreathPeriod)
            / FCMotion.ambientBreathPeriod
        let breath = FCMotion.ambientEase(breathProgress <= 1 / 2 ? breathProgress * 2 : (1 - breathProgress) * 2)
        return Frame(
            steam: steam, breathScale: 1 + (FCMotion.ambientBreathScale - 1) * breath,
            closedEyes: blinkSchedule.contains { elapsed >= $0 && elapsed < $0 + FCMotion.ambientBlinkDuration })
    }

    private static func steamPath(index: Int) -> Path {
        let origin = FCMotion.ambientSteamOrigins[index]
        let dx = FCMotion.ambientSteamControlX
        let y1 = FCMotion.ambientSteamControlY1
        let y2 = FCMotion.ambientSteamControlY2
        let half = FCMotion.ambientSteamHalfHeight
        var path = Path()
        path.move(to: origin)
        path.addCurve(
            to: CGPoint(x: origin.x, y: origin.y - half),
            control1: CGPoint(x: origin.x - dx, y: origin.y - y1),
            control2: CGPoint(x: origin.x + dx, y: origin.y - y2))
        path.addCurve(
            to: CGPoint(x: origin.x, y: origin.y - half - FCMotion.ambientSteamFinalHeights[index]),
            control1: CGPoint(x: origin.x - dx, y: origin.y - half - y1),
            control2: CGPoint(x: origin.x + dx, y: origin.y - half - y2))
        return path
    }
}

#if DEBUG
    #Preview("Ambient") {
        FCAmbientEmptyScene(side: FCMotion.ambientReferenceSide)
    }
    #Preview("Compact") {
        FCAmbientEmptyScene(side: 160)
    }
#endif
