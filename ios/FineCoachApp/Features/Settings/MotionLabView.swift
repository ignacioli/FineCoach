#if DEBUG
    import SwiftUI

    /// 开发版动效试验页 (README §14.1, §14.4 ⑤; Penpot `D-a3`). DEBUG only.
    /// The product owner plays the three candidates on a device and picks the
    /// final float distance and duration; the chosen pair is then written back
    /// into README §14. Production code keeps `FCMotion.durationEmphasis` +
    /// `FCMotion.recordFloatDistance` (= `space.3`), which is candidate B.
    ///
    /// It reads and writes no persisted data: one hard-coded example set row
    /// (`125 kg × 5`), no Student record.
    struct MotionLabView: View {
        /// The candidates from Penpot `D-a3` ⑤, kept only on this page until
        /// one is approved; they are deliberately not motion tokens.
        private enum Candidate: String, CaseIterable {
            case a = "A"
            case b = "B"
            case c = "C"

            /// A 8pt / B 12pt / C 16pt — the approved spacing tokens.
            var distance: CGFloat {
                switch self {
                case .a: return FCPrimitives.space2
                case .b: return FCMotion.recordFloatDistance
                case .c: return FCPrimitives.space4
                }
            }

            /// A 0.5 s / B 0.6 s (`motion.duration.emphasis`) / C 0.8 s.
            var duration: Double {
                switch self {
                case .a: return 0.5
                case .b: return FCMotion.durationEmphasis
                case .c: return 0.8
                }
            }

            var title: String {
                switch self {
                case .a: return String(localized: "motionLab.optionA")
                case .b: return String(localized: "motionLab.optionB")
                case .c: return String(localized: "motionLab.optionC")
                }
            }
        }

        private struct Playback: Equatable {
            let sequence: Int
            let distance: CGFloat
            let duration: Double
        }

        @State private var floatSequence = 0
        @State private var playback: Playback?
        @State private var confirmTick = 0

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: FCPrimitives.space4) {
                    FCPageHeader(title: String(localized: "motionLab.title"), back: .init())

                    Text(String(localized: "motionLab.intro"))
                        .fcFont(.caption)
                        .foregroundStyle(FCSemanticColors.textSecondary)

                    VStack(spacing: 0) {
                        FCListRowDivider()
                        FCSetRow(
                            title: String(localized: "motionLab.sampleTitle"),
                            value: String(localized: "motionLab.sampleValue"),
                            state: .completed,
                            isNewRecord: true,
                            recordFloatSequence: playback?.sequence,
                            recordFloatDistance: playback?.distance ?? FCMotion.recordFloatDistance,
                            recordFloatDuration: playback?.duration ?? FCMotion.durationEmphasis
                        )
                        .accessibilityIdentifier(FCAccessibilityID.motionLabSampleRow)
                        FCListRowDivider()
                    }

                    VStack(spacing: FCPrimitives.space2) {
                        ForEach(Candidate.allCases, id: \.self) { candidate in
                            FCSecondaryButton(title: candidate.title) {
                                play(candidate)
                            }
                            .accessibilityIdentifier(FCAccessibilityID.motionLabOption(candidate.rawValue))
                        }
                    }

                    FCButton(title: String(localized: "motionLab.plainConfirm")) {
                        confirmTick += 1
                    }
                    .accessibilityIdentifier(FCAccessibilityID.motionLabPlainConfirm)
                }
                .padding(.horizontal, FCPrimitives.space4)
                .padding(.bottom, FCPrimitives.space6)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(FCAccessibilityID.motionLabRoot)
            }
            .background(FCSemanticColors.surfacePage)
            .fcSecondaryPage()
            // A tap is a confirmation: one light impact. The float only runs
            // when Reduce Motion is off, exactly as on the training page.
            .sensoryFeedback(FCHaptic.confirm, trigger: confirmTick)
        }

        private func play(_ candidate: Candidate) {
            floatSequence += 1
            playback = Playback(
                sequence: floatSequence, distance: candidate.distance, duration: candidate.duration)
            confirmTick += 1
        }
    }
#endif
