// fictional-data: fixed shared S1 scenarios; no production store is opened.
import CryptoKit
import Foundation
import XCTest

@testable import FineCoach

@MainActor
final class S1SharedVectorTests: XCTestCase {
    func testRequired() async throws { try await run("s1-student-required-fields") }
    func testOptional() async throws { try await run("s1-student-optional-fields-roundtrip") }
    func testSameName() async throws { try await run("s1-student-same-name-distinct-ids") }
    func testStart() async throws { try await run("s1-session-start-reuses-student-active-session") }
    func testValidity() async throws { try await run("s1-set-completion-validity") }
    func testCopy() async throws { try await run("s1-set-copy-stays-pending") }
    func testEnd() async throws { try await run("s1-package-ending-retains-history") }
    func testReplace() async throws { try await run("s1-package-replacement-confirmation-gate") }
    func testDebit() async throws { try await run("s1-package-session-debit-idempotent") }
    func testRefund() async throws { try await run("s1-package-reopen-refunds-once") }
    func testRecent() async throws { try await run("s1-history-most-recent-completed-session") }
    func testStatistics() async throws { try await run("s1-statistics-completed-only") }
    func testBalance() async throws { try await run("s1-package-ledger-balance") }

    private func run(_ id: String) async throws {
        let manifestURL = VectorFiles.root.appendingPathComponent("s1-manifest.json")
        XCTAssertEqual(try digest(manifestURL), "223d58c463fd4a24ba64981516cff05835b5c28eab42d38d6773cdb50cf06f12")
        let manifest = try VectorFiles.decoded(manifestURL)
        let entries = try XCTUnwrap(manifest["vectors"] as? [[String: Any]])
        XCTAssertEqual(manifest["count"] as? Int, 13)
        XCTAssertEqual(entries.count, 13)
        XCTAssertEqual(Set(entries.compactMap { $0["id"] as? String }).count, 13)
        let entry = try XCTUnwrap(entries.first { $0["id"] as? String == id })
        let file = VectorFiles.root.appendingPathComponent(try XCTUnwrap(entry["path"] as? String))
        XCTAssertTrue(file.standardizedFileURL.path.hasPrefix(VectorFiles.root.standardizedFileURL.path + "/"))
        XCTAssertEqual(try digest(file), entry["sha256"] as? String)
        let root = try VectorFiles.decoded(file)
        XCTAssertEqual(root["id"] as? String, id)
        let given = try XCTUnwrap(root["given"] as? [String: Any])
        let clockData = try XCTUnwrap(given["clock"] as? [String: String])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(clockData["now"])))
        let args = try XCTUnwrap(given["state"] as? [String: Any])
        let op = try XCTUnwrap(entry["iosAdapter"] as? String)
        if op == "credit-ledger.balance" {
            try SharedVectorRunner(conformance: false).run(Data(contentsOf: file), filename: file.lastPathComponent)
        } else {
            // Execute the real async boundary once, then use S0's strict resolver/comparator.
            // The dispatch closure checks that resolved args are the inputs actually executed.
            let actual = try await scenario(op, args, now)
            try SharedVectorRunner(conformance: false).run(
                Data(contentsOf: file), filename: file.lastPathComponent, extraOps: [op]
            ) { dispatched, resolved in
                guard dispatched == op, NSDictionary(dictionary: resolved).isEqual(to: args) else {
                    throw VectorFailure(kind: "format", field: "/when/args", id: id)
                }
                return actual
            }
        }
        try VectorFiles.report(file)
        print("S1-MANIFEST sha256=\(try digest(manifestURL)) count=13")
    }

    private func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func scenario(_ op: String, _ a: [String: Any], _ now: Date) async throws -> Any {
        let values = try XCTUnwrap(a["ids"] as? [String])
        let ids = S1VectorIDs(values)
        let clock = TestClock(utcDate: now)
        func id() -> StableUUID { StableUUID(ids.makeID()) }
        func draft(_ a: [String: Any]) -> StudentDraft {
            StudentDraft(displayName: a["displayName"] as! String, sex: (a["sex"] as? String).flatMap(StudentSex.init(rawValue:)),
                trainingGoal: a["trainingGoal"] as? String ?? "", injuryNotes: a["injuryNotes"] as? String ?? "",
                privateCoachNote: a["privateCoachNote"] as? String ?? "", phone: a["phone"] as? String ?? "",
                wechatID: a["wechatID"] as? String ?? "")
        }
        func fields(_ s: Student) -> [Any] {
            [s.trainingGoal?.value, s.injuryNotes?.value, s.privateCoachNote?.value, s.phone?.value, s.wechatID?.value].map { $0 as Any? ?? NSNull() }
        }
        func set(_ input: [String: Any]) throws -> TrainingSet {
            try TrainingSet.makeDraft(id: id(), sessionExerciseID: id(), orderIndex: 0, input: s1Input(input), now: now)
        }
        switch op {
        case "student.required":
            return ["errors": try (a["drafts"] as! [[String: Any]]).map { d -> String in
                do { _ = try draft(d).makeStudent(id: id(), now: now); throw S1AdapterError.expectedFailure }
                catch let e as DomainError { return String(describing: e) }
            }]
        case "student.optional":
            let filled = try draft(a).makeStudent(id: id(), now: now)
            let cleared = try filled.updating(from: StudentDraft(displayName: a["displayName"] as! String, sex: .female), now: now)
            return ["filled": fields(filled), "cleared": fields(cleared), "sameID": filled.id == cleared.id]
        case "student.same-name":
            let x = try draft(a).makeStudent(id: id(), now: now)
            let y = try draft(a).makeStudent(id: id(), now: now)
            return ["sameName": x.displayName == y.displayName, "distinctIDs": x.id != y.id]
        case "set.validity":
            return ["outcomes": try (a["inputs"] as! [[String: Any]]).map { input -> String in
                do { return try set(input).confirmed(now: now).state.rawValue }
                catch let e as DomainError { return String(describing: e) }
            }]
        case "set.copy":
            let original = try set(a["input"] as! [String: Any]).confirmed(now: now)
            let copied = try original.copiedAsPending(id: id(), orderIndex: 1, now: now)
            return ["state": copied.state.rawValue, "contributes": copied.contributesToStatistics,
                "distinctID": copied.id != original.id, "completedAtUTC": copied.completedAtUTC as Any? ?? NSNull()]
        case "package.end":
            let original = try CoursePackage(id: id(), studentID: id(), totalCredits: a["totalCredits"] as! Int, createdAtUTC: now, updatedAtUTC: now)
            let ended = try original.ending(now: now)
            return ["status": ended.status.rawValue, "totalCredits": ended.totalCredits, "sameID": original.id == ended.id]
        case "set.statistics":
            var s = Session.start(id: id(), studentID: id(), now: now)
            let eid = id(), sid = id()
            s = try s.addingSessionOnlyExercise(id: eid, displayName: "虚构动作", recordMode: .weightReps, now: now)
            let input = s1Input(a["input"] as! [String: Any])
            s = try s.addingSet(exerciseID: eid, setID: sid, input: input, now: now).confirmingSet(setID: sid, now: now)
            s = try s.copyingSet(sourceSetID: sid, newSetID: id(), now: now)
            s = try s.addingSet(exerciseID: eid, setID: id(), input: input, now: now)
            return ["count": s.completedSetCount, "volume": s.statistics.ordinaryTrainingVolume?.canonicalString as Any? ?? NSNull()]
        default: break
        }
        let directory = try TemporaryProtectedDirectory()
        let persistence = try PersistenceController(storeURL: directory.url.appendingPathComponent("s1-vector.sqlite"))
        do {
            let students = CoreDataStudentRepository(writer: persistence.writer)
            let sessionsRepo = CoreDataSessionRepository(writer: persistence.writer)
            let studentCases = StudentUseCases(repository: students, clock: clock, ids: ids)
            let sessions = ActiveSessionUseCases(sessionRepository: sessionsRepo, studentRepository: students,
                exerciseRepository: CoreDataExerciseRepository(writer: persistence.writer),
                sectionRepository: CoreDataSessionSectionRepository(writer: persistence.writer),
                recoveryStore: ActiveSessionRecoveryStore(url: directory.url.appendingPathComponent("recovery.json")),
                storeGenerationUUID: UUID(uuidString: values[31])!, clock: clock, ids: ids)
            let credits = CreditLedgerUseCases(repository: CoreDataCoursePackageRepository(writer: persistence.writer), clock: clock, ids: ids)
            func student() async throws -> Student {
                try await studentCases.create(draft: StudentDraft(displayName: "虚构甲", sex: .female))
            }
            func package(_ s: StableUUID) async throws -> CoursePackage {
                try await credits.createActivePackage(studentID: s, name: nil, totalCredits: a["totalCredits"] as! Int, startDate: nil, endDate: nil)
            }
            func complete(_ s: StableUUID) async throws -> Session {
                let session = try await sessions.startOrOpen(studentID: s)
                let withExercise = try await sessions.addSessionOnlyExercise(sessionID: session.id, displayName: "虚构动作", recordMode: .weightReps)
                let eid = try XCTUnwrap(withExercise.exercises.first?.id)
                let withSet = try await sessions.addSet(sessionID: session.id, exerciseID: eid, input: s1Input(a["input"] as! [String: Any]))
                let sid = try XCTUnwrap(withSet.exercises.first?.sets.first?.id)
                _ = try await sessions.confirmSet(sessionID: session.id, setID: sid)
                return try await sessions.finish(sessionID: session.id)
            }
            let actual: [String: Any]
            switch op {
            case "session.start":
                let s = try await student(), other = try await student()
                let x = try await sessions.startOrOpen(studentID: s.id)
                let y = try await sessions.startOrOpen(studentID: s.id)
                let z = try await sessions.startOrOpen(studentID: other.id)
                let all = try await sessionsRepo.loadAllActive()
                actual = ["sameID": x.id == y.id, "isolated": z.id != x.id, "activeCount": all.count]
            case "package.replace":
                let s = try await student(), old = try await package(s.id)
                let editor = CoursePackageEditorViewModel(studentID: s.id, useCases: credits, today: try LocalDate(canonicalString: "2031-04-05"))
                editor.totalCredits = a["totalCredits"] as! Int
                await editor.loadExistingActivePackage()
                await editor.save()
                let blocked = editor.isConfirmingEndActive && !editor.didSave
                editor.isConfirmingEndActive = false // exact cancel action from the real view
                let afterCancel = try await credits.packages(studentID: s.id)
                await editor.save()
                await editor.confirmEndActiveAndSave()
                guard editor.didSave else { throw S1AdapterError.persistence }
                let all = try await credits.packages(studentID: s.id)
                actual = ["blocked": blocked, "countAfterCancel": afterCancel.count, "countAfterConfirm": all.count,
                    "oldStatus": try XCTUnwrap(all.first { $0.id == old.id }).status.rawValue,
                    "activeCount": all.filter { $0.status == .active }.count]
            case "package.debit":
                let s = try await student(), p = try await package(s.id), session = try await complete(s.id)
                _ = try await credits.debitOnAdhocSession(packageID: p.id, sessionID: session.id)
                _ = try await credits.debitOnAdhocSession(packageID: p.id, sessionID: session.id)
                actual = ["sessionState": session.state.rawValue, "balance": try await credits.balance(packageID: p.id),
                    "ledgerCount": try await credits.adjustments(packageID: p.id).count]
            case "package.refund":
                let s = try await student(), p = try await package(s.id), sid = id()
                _ = try await credits.debitOnSessionComplete(packageID: p.id, sessionID: sid)
                let x = try await credits.creditOnSessionReopen(packageID: p.id, sessionID: sid)
                let y = try await credits.creditOnSessionReopen(packageID: p.id, sessionID: sid)
                let none = try await credits.creditOnSessionReopen(packageID: p.id, sessionID: id())
                actual = ["balance": try await credits.balance(packageID: p.id), "ledgerCount": try await credits.adjustments(packageID: p.id).count,
                    "sameRefundID": x?.id == y?.id, "noDebitRefund": none as Any? ?? NSNull()]
            case "history.recent":
                let s = try await student()
                let empty = try await sessionsRepo.listCompleted(studentID: s.id)
                _ = try await complete(s.id)
                clock.advance(seconds: 60); ids.index = 20
                _ = try await complete(s.id)
                let all = try await sessionsRepo.listCompleted(studentID: s.id)
                actual = ["emptyCount": empty.count, "count": all.count,
                    "latestID": try XCTUnwrap(CompletedSession.mostRecent(in: all)).id.rawValue.uuidString.lowercased()]
            default: throw S1AdapterError.unmapped
            }
            try await persistence.shutdownForTesting()
            return actual
        } catch {
            try await persistence.shutdownForTesting()
            throw error
        }
    }
}

private enum S1AdapterError: Error { case expectedFailure, persistence, unmapped }
private final class S1VectorIDs: IDGenerator, @unchecked Sendable {
    private let values: [String]
    private let lock = NSLock()
    var index = 0
    init(_ values: [String]) { self.values = values }
    func makeID() -> UUID {
        lock.lock(); defer { lock.unlock() }
        precondition(index < values.count)
        defer { index += 1 }
        return UUID(uuidString: values[index])!
    }
}
private func s1Input(_ a: [String: Any]) -> TrainingSetInput {
    TrainingSetInput(recordMode: RecordMode(rawValue: a["recordMode"] as! String)!, weightValue: a["weightValue"] as? String,
        repetitionCount: a["repetitionCount"] as? String, durationSeconds: a["durationSeconds"] as? String,
        unit: MeasurementUnit(rawValue: a["unit"] as! String)!, side: SetSide(rawValue: a["side"] as! String)!,
        leftValue: a["leftValue"] as? String, rightValue: a["rightValue"] as? String, distanceValue: a["distanceValue"] as? String,
        speedValue: a["speedValue"] as? String, resistanceValue: a["resistanceValue"] as? String)
}
