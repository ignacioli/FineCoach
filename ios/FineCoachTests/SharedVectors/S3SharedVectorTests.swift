// fictional-data: deterministic S3 vectors only; body values never appear in diagnostics.
import CryptoKit
import Foundation
import XCTest

@testable import FineCoach

final class S3SharedVectorTests: XCTestCase {
    func testGains() throws { try run("gains", count: 35) }
    func testInsights() throws { try run("insights", count: 24) }
    func testE1RM() throws { try run("e1rm", count: 9) }
    func testComparison() throws { try run("comparison", count: 6) }
    func testBody() throws { try run("body", count: 3) }

    private func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    private func run(_ group: String, count: Int) throws {
        let manifestURL = VectorFiles.root.appendingPathComponent("s3-manifest.json")
        let manifest = try VectorFiles.decoded(manifestURL)
        let entries = try XCTUnwrap(manifest["vectors"] as? [[String: Any]])
        XCTAssertEqual(manifest["version"] as? Int, 1)
        XCTAssertEqual(manifest["count"] as? Int, 77)
        XCTAssertEqual(entries.count, 77)
        XCTAssertEqual(Set(entries.compactMap { $0["id"] as? String }).count, 77)
        let batch = entries.filter { ($0["path"] as? String)?.hasPrefix("s3/\(group)/") == true }
        XCTAssertEqual(batch.count, count)
        for entry in batch {
            let file = VectorFiles.root.appendingPathComponent(try XCTUnwrap(entry["path"] as? String))
            XCTAssertTrue(file.standardizedFileURL.path.hasPrefix(VectorFiles.root.standardizedFileURL.path + "/"))
            XCTAssertEqual(try digest(file), entry["sha256"] as? String)
            let root = try VectorFiles.decoded(file)
            XCTAssertEqual(root["id"] as? String, entry["id"] as? String)
            let given = try XCTUnwrap(root["given"] as? [String: Any])
            let clock = try XCTUnwrap(given["clock"] as? [String: String])
            let now = try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(clock["now"])))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(given["timeZone"] as? String)))
            let op = try XCTUnwrap(entry["iosAdapter"] as? String)
            XCTAssertEqual(entry["androidAdapter"] as? String, op)
            let adapter = S3VectorAdapter(now: now, calendar: calendar)
            try SharedVectorRunner(conformance: false).run(
                Data(contentsOf: file), filename: file.lastPathComponent, extraOps: [op]
            ) { dispatched, args in
                guard dispatched == op else { throw S3AdapterError.malformed }
                return try adapter.evaluate(dispatched, args)
            }
            try VectorFiles.report(file)
        }
        print("S3-MANIFEST sha256=\(try digest(manifestURL)) count=77 group=\(group) executed=\(count)")
    }
}

private enum S3AdapterError: Error { case malformed }
private struct S3VectorAdapter {
    let now: Date
    let calendar: Calendar
    private func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw S3AdapterError.malformed }
        return value
    }
    private func rows(_ value: Any?) throws -> [[String: Any]] {
        guard let value = value as? [[String: Any]] else { throw S3AdapterError.malformed }
        return value
    }
    private func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw S3AdapterError.malformed }
        return value
    }
    private func integer(_ value: Any?) throws -> Int {
        guard let value = value as? Int else { throw S3AdapterError.malformed }
        return value
    }
    private func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? Bool else { throw S3AdapterError.malformed }
        return value
    }
    private func uuid(_ value: Any?) throws -> StableUUID {
        guard let value = UUID(uuidString: try string(value)) else { throw S3AdapterError.malformed }
        return StableUUID(value)
    }
    private func instant(_ value: Any?) throws -> Date {
        guard let value = ISO8601DateFormatter().date(from: try string(value)) else { throw S3AdapterError.malformed }
        return value
    }
    private func day(_ value: Any?) throws -> LocalDate {
        let d = try object(value)
        return try LocalDate(year: integer(d["year"]), month: integer(d["month"]), day: integer(d["day"]))
    }
    private func decimal(_ value: Any?) throws -> DecimalValue? {
        guard let value = value as? String else { return nil }
        return try DecimalValue(value)
    }
    private func null(_ value: Any?) -> Any { value ?? NSNull() }
    private func mode(_ value: Any?) throws -> RecordMode {
        guard let value = RecordMode(rawValue: try string(value)) else { throw S3AdapterError.malformed }
        return value
    }
    private func session(_ row: [String: Any], _ c: [String: Any]) throws -> CompletedSession {
        let id = try uuid(row["id"])
        let eid = try uuid(row["exerciseID"])
        let at = try instant(row["completedAtUTC"])
        let recordMode = try mode(row["recordMode"])
        let sets = try rows(row["sets"]).map { s in
            let input = try object(s["input"])
            guard let unit = MeasurementUnit(rawValue: try string(input["unit"])),
                let side = SetSide(rawValue: try string(input["side"]))
            else { throw S3AdapterError.malformed }
            let draft = try TrainingSet.makeDraft(
                id: uuid(s["id"]), sessionExerciseID: eid, orderIndex: UInt32(integer(s["orderIndex"])),
                input: TrainingSetInput(
                    recordMode: mode(input["recordMode"]), weightValue: input["weightValue"] as? String,
                    repetitionCount: input["repetitionCount"] as? String,
                    durationSeconds: input["durationSeconds"] as? String,
                    unit: unit, side: side, distanceValue: input["distanceValue"] as? String), now: at)
            switch try string(s["state"]) {
            case "completed": return try draft.confirmed(now: at)
            case "pending": return try draft.confirmed(now: at).undone(now: at)
            case "draft": return draft
            default: throw S3AdapterError.malformed
            }
        }
        guard let sourceKind = ExerciseSourceKind(rawValue: try string(c["sourceKind"])) else {
            throw S3AdapterError.malformed
        }
        let exercise = try SessionExercise(
            id: eid, sessionID: id, orderIndex: UInt32(integer(c["exerciseOrder"])),
            sourceKind: sourceKind, sourceID: StableExerciseID(string(row["sourceID"])),
            displayNameSnapshot: NormalizedName(string(c["exerciseName"])), recordModeSnapshot: recordMode,
            actionPrivateNote: (c["actionPrivateNote"] as? String).map { try ValidatedText($0) }, sets: sets)
        guard let focus = row["trainingFocus"] as? [String], try object(c["actionPrivateNotes"]).isEmpty,
            c["latestReport"] is NSNull
        else { throw S3AdapterError.malformed }
        return try CompletedSession(
            id: id, studentID: uuid(row["studentID"]), studentDisplayName: NormalizedName(string(c["studentName"])),
            startedAtUTC: instant(row["startedAtUTC"]), completedAtUTC: at,
            trainingFocus: Set(
                focus.map { raw in
                    guard let part = BodyPart(rawValue: raw) else { throw S3AdapterError.malformed }
                    return part
                }),
            notes: SessionNotes(
                privateCoachNote: (c["privateCoachNote"] as? String).map { try ValidatedText($0) },
                studentFacingSummary: (c["studentFacingSummary"] as? String).map { try ValidatedText($0) },
                actionPrivateNotes: [:]),
            exercises: [exercise],
            statistics: SessionStatistics(
                completedSetCount: sets.filter(\.contributesToStatistics).count,
                displayedDurationSeconds: DecimalValue(string(c["displayedDurationSeconds"])),
                ordinaryTrainingVolume: decimal(c["ordinaryTrainingVolume"])),
            revision: UInt64(integer(c["revision"])), latestReport: nil)
    }
    func evaluate(_ op: String, _ a: [String: Any]) throws -> Any {
        let c = try object(a["context"])
        func history() throws -> [CompletedSession] { try rows(a["history"]).map { try session($0, c) } }
        func assisted() throws -> Set<StableExerciseID> {
            guard let ids = a["assisted"] as? [String] else { throw S3AdapterError.malformed }
            return try Set(ids.map { try StableExerciseID($0) })
        }
        switch op {
        case "s3.gains":
            let value = try SessionGains(
                current: session(object(a["current"]), c), history: history(), assistedExerciseIDs: assisted(),
                calendar: calendar, timeZone: calendar.timeZone)
            return [
                "holderIDs": value.recordHolderSetIDs.map { $0.rawValue.uuidString.lowercased() }.sorted(),
                "strictIDs": value.strictRecordHolderSetIDs.map { $0.rawValue.uuidString.lowercased() }.sorted(),
                "recordCount": value.records.count, "rowCount": value.rows.count, "progressCount": value.progress.count,
                "milestone": null(value.milestoneSessionNumber), "streak": null(value.attendanceStreakWeeks),
            ] as [String: Any]
        case "s3.e1rm":
            return try [
                "value": null(
                    EstimatedOneRepMax.value(
                        weight: DecimalValue(string(a["weight"])), reps: DecimalValue(string(a["reps"])),
                        exerciseID: StableExerciseID(string(a["exerciseID"])))?.canonicalString)
            ]
        case "s3.insights":
            let students = try rows(a["students"]).map { s in
                guard let sex = StudentSex(rawValue: try string(s["sex"])) else { throw S3AdapterError.malformed }
                let value = try StudentDraft(displayName: string(s["name"]), sex: sex).makeStudent(
                    id: uuid(s["id"]), now: instant(s["createdAtUTC"]))
                return try boolean(s["archived"]) ? value.archived(now: now) : value
            }
            var packages: [StableUUID: InsightEngine.PackageBalance] = [:]
            for p in try rows(a["packages"]) {
                let studentID = try uuid(p["studentID"])
                let end: LocalDate? = p["endDate"] is NSNull ? nil : try day(p["endDate"])
                let package = try CoursePackage(
                    id: uuid(p["id"]), studentID: studentID, totalCredits: integer(p["totalCredits"]), endDate: end,
                    createdAtUTC: now, updatedAtUTC: now)
                packages[studentID] = try InsightEngine.PackageBalance(package: package, balance: integer(p["balance"]))
            }
            let appointments = try rows(a["appointments"]).map { row in
                guard let status = AppointmentStatus(rawValue: try string(row["status"])) else {
                    throw S3AdapterError.malformed
                }
                return try Appointment(
                    id: uuid(row["id"]), studentID: uuid(row["studentID"]), seriesID: nil, date: day(row["date"]),
                    startTime: LocalTime(hour: integer(row["hour"]), minute: integer(row["minute"])), status: status,
                    createdAtUTC: now, updatedAtUTC: now)
            }
            guard let snoozed = a["snoozed"] as? [String] else { throw S3AdapterError.malformed }
            let keys = snoozed.map { key in
                var parts = key.components(separatedBy: ":")
                if parts.count > 1 { parts[1] = parts[1].uppercased() }
                return parts.joined(separator: ":")
            }
            let input = try InsightEngine.Input(
                students: students, packages: packages, appointments: appointments, history: history(),
                snoozedKeys: Set(keys), assistedExerciseIDs: assisted())
            let values = InsightEngine.evaluate(input: input, now: now, calendar: calendar)
            return [
                "items": values.map {
                    [
                        "kind": $0.kind.rawValue, "studentID": $0.studentID.rawValue.uuidString.lowercased(),
                        "exerciseID": null($0.exerciseID?.rawValue),
                        "metric": null($0.baselineMetric.map { String(describing: $0) }),
                    ]
                }
            ]
        case "s3.compare":
            switch try Comparison.compareSessions(session(object(a["a"]), c), session(object(a["b"]), c)) {
            case .compatible(let detail):
                return ["compatibility": "compatible", "setsA": detail.totalSetCountA, "setsB": detail.totalSetCountB]
            case .differentStudent: return ["compatibility": "differentStudent"]
            case .incompatibleTrainingFocus: return ["compatibility": "incompatible"]
            }
        case "s3.records", "s3.trend":
            let id = try StableExerciseID(string(a["exerciseID"]))
            let recordMode = try mode(a["recordMode"])
            let direction: Comparison.LoadDirection =
                try boolean(a["assisted"]) ? .decreaseIsImprovement : .increaseIsImprovement
            if op == "s3.records" {
                let r = try Comparison.personalRecords(
                    exerciseID: id, recordMode: recordMode, across: history(), loadDirection: direction)
                return [
                    "weight": null(r.highestWeight?.weight.canonicalString),
                    "repsWeight": null(r.mostRepsAtWeight?.weight.canonicalString),
                    "reps": null(r.mostRepsAtWeight?.reps.canonicalString),
                    "repsSession": null(r.mostRepsAtWeight?.sessionID.rawValue.uuidString.lowercased()),
                ]
            }
            let points = try Comparison.exerciseTrend(
                exerciseID: id, recordMode: recordMode, across: history(), loadDirection: direction)
            let density: String
            switch Comparison.TrendSampleDensity.classify(points) {
            case .empty: density = "empty"
            case .single: density = "single"
            case .sparse: density = "sparse"
            case .sufficient: density = "sufficient"
            }
            return [
                "weights": points.map { null($0.maxWeight?.canonicalString) },
                "deltas": points.map { null($0.weightDelta?.canonicalString) },
                "volumes": points.map { null($0.volume?.canonicalString) }, "density": density,
            ]
        case "s3.body-display":
            guard let weightUnit = BuiltInUnitConversion.WeightDisplayUnit(rawValue: try string(a["weightUnit"])),
                let lengthUnit = BuiltInUnitConversion.LengthDisplayUnit(rawValue: try string(a["lengthUnit"]))
            else { throw S3AdapterError.malformed }
            let value = try DecimalValue(string(a["value"]))
            return try [
                "weight": BuiltInUnitConversion.weight(canonicalKilograms: value, displayedAs: weightUnit)
                    .canonicalString,
                "length": BuiltInUnitConversion.length(
                    canonicalCentimeters: DecimalValue(string(a["centimeters"])), displayedAs: lengthUnit
                ).canonicalString, "original": value.canonicalString,
            ]
        case "s3.body-upsert":
            var index = BodyMeasurementDayIndex()
            let student = try uuid(a["studentID"])
            let metric = try uuid(a["metricID"])
            func record(_ prefix: String) throws -> BodyMeasurement {
                let date = try instant(a[prefix + "At"])
                return try index.upsert(
                    studentID: student, metricID: metric, localCalendarDay: LocalDate(date: date, calendar: calendar),
                    value: DecimalValue(string(a[prefix + "Value"])), enteredUnit: string(a[prefix + "Unit"]),
                    newID: uuid(a[prefix + "ID"]), now: date)
            }
            let first = try record("first")
            let second = try record("second")
            let points = index.history(studentID: student, metricID: metric)
            return [
                "count": points.count, "keptFirstID": second.id == first.id,
                "days": points.map(\.localCalendarDay.canonicalString), "units": points.map(\.enteredUnit),
            ]
        default: throw S3AdapterError.malformed
        }
    }
}
