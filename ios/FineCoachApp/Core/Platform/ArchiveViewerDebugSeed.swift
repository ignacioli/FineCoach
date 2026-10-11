import Foundation

// DEBUG-only seed for the human review of the archive viewer (T053). Launch with
// `-FineCoachSeedViewerArchive` (add `-FineCoachResetStore` to start from an empty install):
// a fictional archive containing every module is built with the real export policy from
// invented data and installed directly as the viewer archive, so the reviewer can open M2-11
// and browse every viewer page without the file picker. Nothing here resembles a real person;
// not compiled into Release.
#if DEBUG
    enum ArchiveViewerDebugSeed {
        static let launchArgument = "-FineCoachSeedViewerArchive"

        static var isRequested: Bool {
            ProcessInfo.processInfo.arguments.contains(launchArgument)
        }

        /// Installs the seed archive unless an archive is already installed. Returns whether an
        /// archive is installed afterwards.
        @discardableResult
        static func install(into store: ArchiveSnapshotStore, now: Date = Date()) -> Bool {
            if (try? store.load()) != nil {
                return true
            }
            guard let snapshot = try? makeSnapshot(now: now) else {
                return false
            }
            return (try? store.commit(snapshot: snapshot)) != nil
        }

        /// A snapshot with every module, produced by `ArchiveExportPolicy` from the fictional
        /// source below, so it has exactly the shape a real export has.
        static func makeSnapshot(now: Date, calendar: Calendar = .current) throws -> ArchiveSnapshot {
            let source = try makeSource(now: now, calendar: calendar)
            let selection = ArchiveModuleSelection(availability: source.availability)
            return try ArchiveExportPolicy.makeSnapshot(
                source: source,
                selection: selection,
                identity: ArchiveIdentity(
                    sourceID: UUID(uuidString: "5eed0000-0000-4000-8000-000000000001")!,
                    studentArchiveID: UUID(uuidString: "5eed0000-0000-4000-8000-000000000002")!
                ),
                now: now
            )
        }

        private static func dv(_ raw: String) throws -> DecimalValue {
            try DecimalValue(raw)
        }

        private static func set(_ weight: String, _ reps: String) throws -> ArchiveSet {
            ArchiveSet(weightValue: try dv(weight), repetitionCount: try dv(reps), unit: .kilograms)
        }

        private static func makeSource(now: Date, calendar: Calendar) throws -> ArchiveExportSource {
            let catalog = { (primary: String, secondary: [String], equipment: String) in
                ArchiveExportSource.CatalogReference(
                    primaryMuscles: [primary],
                    secondaryMuscles: secondary,
                    equipment: equipment,
                    sourceName: "wger.de",
                    licenseName: "CC-BY-SA 4.0",
                    licenseText: "https://creativecommons.org/licenses/by-sa/4.0/"
                )
            }
            func exercise(
                _ id: String, _ name: String, _ catalogReference: ArchiveExportSource.CatalogReference?,
                kind: ArchiveExerciseKind, assisted: Bool = false, mode: RecordMode = .weightReps,
                sets: [ArchiveSet]
            ) -> ArchiveExportSource.Exercise {
                ArchiveExportSource.Exercise(
                    identity: kind == .oneOff ? .oneOff : .stable(id),
                    kind: kind,
                    isAssisted: assisted,
                    name: name,
                    catalog: catalogReference,
                    recordMode: mode,
                    sets: sets
                )
            }
            let bench = catalog("胸", ["肩", "臂"], "杠铃")
            let squat = catalog("大腿", ["臀"], "杠铃")

            // Eight weekly sessions ending yesterday; load and reps creep up so trends show a line.
            var sessions: [ArchiveExportSource.Session] = []
            let summaries: [Int: String] = [
                2: "今天深蹲感觉比上周稳，最后一组有点吃力。",
                5: "睡得不太好，热身多做了五分钟。",
                7: "第一次做到 90kg × 8，很开心！",
            ]
            for index in 0..<8 {
                let daysAgo = (7 - index) * 7 + 1
                let completed = now.addingTimeInterval(-Double(daysAgo) * 86_400)
                let base = 60 + index * 3
                var entries: [ArchiveExportSource.Exercise] = [
                    exercise(
                        "bench", "杠铃卧推", bench, kind: .builtIn,
                        sets: [try set("\(base)", "12"), try set("\(base + 5)", "10"), try set("\(base + 10)", "8")]),
                    exercise(
                        "squat", "杠铃深蹲", squat, kind: .builtIn,
                        sets: [try set("\(base - 10)", "12"), try set("\(base)", "10")]),
                ]
                if index % 2 == 0 {
                    entries.append(
                        exercise(
                            "pullup", "辅助引体向上", nil, kind: .custom, assisted: true,
                            sets: [try set("\(40 - index * 2)", "8"), try set("\(40 - index * 2)", "6")]))
                }
                if index == 4 {
                    entries.append(
                        exercise(
                            "", "跑步机慢跑", nil, kind: .oneOff, mode: .cardio,
                            sets: [
                                ArchiveSet(
                                    durationSeconds: try dv("1200"), unit: .seconds,
                                    distanceValue: try dv("2.5"), speedValue: try dv("7.5"))
                            ]))
                }
                sessions.append(
                    ArchiveExportSource.Session(
                        completedAtUTC: completed,
                        localDate: LocalDate(date: completed, calendar: calendar),
                        durationMinutes: 45 + index * 2,
                        trainingFocus: index % 3 == 0 ? [.chest, .thighs] : [.chest, .arms],
                        summary: summaries[index],
                        sections: [ArchiveExportSource.Section(name: nil, exercises: entries)]))
            }

            func measurements(_ values: [(Int, String)], unit: String) throws -> [ArchiveExportSource.Measurement] {
                try values.map { days, value in
                    let day = now.addingTimeInterval(-Double(days) * 86_400)
                    return ArchiveExportSource.Measurement(
                        localDay: LocalDate(date: day, calendar: calendar), value: try dv(value), enteredUnit: unit)
                }
            }
            let metrics = [
                ArchiveExportSource.BodyMetric(
                    id: BuiltInBodyMetric.weight.id, kind: .builtIn(.weight), name: nil, unit: nil,
                    measurements: try measurements([(42, "70.5"), (21, "69.8"), (2, "68.5")], unit: "kg")),
                ArchiveExportSource.BodyMetric(
                    id: BuiltInBodyMetric.bodyFatPercent.id, kind: .builtIn(.bodyFatPercent), name: nil, unit: nil,
                    measurements: try measurements([(42, "19.1"), (2, "18.2")], unit: "%")),
                ArchiveExportSource.BodyMetric(
                    id: StableUUID(UUID(uuidString: "5eed0000-0000-4000-8000-0000000000c1")!),
                    kind: .custom, name: "肩宽", unit: "cm",
                    measurements: try measurements([(42, "44"), (2, "44.5")], unit: "cm")),
            ]
            return ArchiveExportSource(
                student: .init(displayName: "王小明", sex: .male),
                sessions: sessions,
                bodyMetrics: metrics)
        }
    }

    extension AppEnvironment {
        /// DEBUG launch arguments that must act before the install state is resolved: a store
        /// reset also clears the viewer archive (so a fresh install shows M2-07), the existing
        /// Coach seeds run before the choice page can hide them, and `-FineCoachSeedViewerArchive`
        /// installs the fictional viewer archive.
        func prepareForDebugLaunchArguments(archiveStore: ArchiveSnapshotStore) async {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-FineCoachResetStore") {
                try? archiveStore.deleteAll()
            }
            if ArchiveViewerDebugSeed.isRequested {
                ArchiveViewerDebugSeed.install(into: archiveStore)
            } else if ArchiveExportDebugSeed.isRequested || arguments.contains("-FineCoachSeedInProgressSession") {
                await applyUITestSeedingIfNeeded()
            }
        }
    }
#endif
