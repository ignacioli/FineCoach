import CoreData
import Foundation

enum BackupFrameSection: UInt8 {
    case manifest = 1
    case student = 2
    case exerciseCatalog = 3
    case exercisePreference = 4
    case exerciseClaim = 5
    case session = 6
    case shareReport = 7
    case setting = 8
}

struct BackupSettingRecord: Codable, Equatable, Sendable {
    var key: String
    var typedValue: String
    var schemaVersion: Int64
}

struct BackupShareReportRecord: Codable, Equatable, Sendable {
    var report: ShareReport
    var modules: ShareReportModuleSelection?
}

struct BackupManifest: Codable, Equatable, Sendable {
    var payloadSchemaVersion: UInt16
    var studentCount: Int
    var exerciseCount: Int
    var sessionCount: Int
    var sessionExerciseCount: Int
    var setCount: Int
    var reportCount: Int
    var settingCount: Int
    var recordCount: UInt64
}

struct BackupInventory: Equatable, Sendable {
    var students: [Student]
    var catalog: [ExerciseCatalogItem]
    var preferences: [ExercisePreference]
    var claims: [ExerciseNameClaim]
    var sessions: [Session]
    var reports: [BackupShareReportRecord]
    var settings: [BackupSettingRecord]

    var sessionExerciseCount: Int {
        sessions.reduce(0) { $0 + $1.exercises.count }
    }

    var setCount: Int {
        sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
    }

    var inProgressSessions: [Session] {
        sessions.filter { $0.state == .inProgress }
    }

    func manifest(recordCount: UInt64) -> BackupManifest {
        BackupManifest(
            payloadSchemaVersion: FineCoachBackupV1.payloadSchemaVersion,
            studentCount: students.count,
            exerciseCount: catalog.count,
            sessionCount: sessions.count,
            sessionExerciseCount: sessionExerciseCount,
            setCount: setCount,
            reportCount: reports.count,
            settingCount: settings.count,
            recordCount: recordCount
        )
    }
}

enum BackupJSONCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoded = try encoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        return try BackupJSONCanonicalization.canonicalUTF8(object)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw BackupError.invalidState
        }
    }
}

enum BackupInventoryMapper {
    static func collect(in context: NSManagedObjectContext) throws -> BackupInventory {
        let studentObjects = try fetchAll(StudentManagedObjectMapping.entityName, in: context)
        let catalogObjects = try fetchAll(ExerciseManagedObjectMapping.catalogEntityName, in: context)
        let preferenceObjects = try fetchAll(ExerciseManagedObjectMapping.preferenceEntityName, in: context)
        let claimObjects = try fetchAll(ExerciseManagedObjectMapping.claimEntityName, in: context)
        let sessionObjects = try fetchAll(SessionManagedObjectMapping.sessionEntityName, in: context)
        let reportObjects = try fetchAll(HistoryReportManagedObjectMapping.reportEntityName, in: context)
        let settingObjects = try fetchAll(StudentManagedObjectMapping.settingEntityName, in: context)

        let students = try studentObjects.map { try StudentManagedObjectMapping.makeStudent(from: $0) }
        let catalog = try catalogObjects.map { try ExerciseManagedObjectMapping.makeCatalogItem(from: $0) }
        let preferences = try preferenceObjects.map { try ExerciseManagedObjectMapping.makePreference(from: $0) }
        let claims = try claimObjects.map { try ExerciseManagedObjectMapping.makeClaim(from: $0) }
        let sessions = try sessionObjects.map { try SessionManagedObjectMapping.loadAggregate(from: $0, in: context) }
        let reports: [BackupShareReportRecord] = try reportObjects.map { object in
            let report = try HistoryReportManagedObjectMapping.makeReport(from: object)
            let modules: ShareReportModuleSelection?
            if let data = object.value(forKey: "selectedModules") as? Data {
                modules = try? JSONDecoder().decode(ShareReportModuleSelection.self, from: data)
            } else {
                modules = nil
            }
            return BackupShareReportRecord(report: report, modules: modules)
        }
        let settings: [BackupSettingRecord] = try settingObjects.map { object in
            guard let key = object.value(forKey: "key") as? String,
                let typedValue = object.value(forKey: "typedValue") as? String
            else {
                throw DomainError.incompatibleInput
            }
            let schemaVersion = object.value(forKey: "schemaVersion") as? Int64 ?? 1
            return BackupSettingRecord(key: key, typedValue: typedValue, schemaVersion: schemaVersion)
        }

        try validateCounts(
            students: students.count,
            exercises: catalog.count,
            sessions: sessions.count,
            sessionExercises: sessions.reduce(0) { $0 + $1.exercises.count },
            sets: sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } },
            settings: settings.count
        )
        return BackupInventory(
            students: students,
            catalog: catalog,
            preferences: preferences,
            claims: claims,
            sessions: sessions,
            reports: reports,
            settings: settings
        )
    }

    static func encodeFrames(_ inventory: BackupInventory) throws -> Data {
        var records: [(BackupFrameSection, Data)] = []
        try append(section: .student, values: inventory.students, into: &records)
        try append(section: .exerciseCatalog, values: inventory.catalog, into: &records)
        try append(section: .exercisePreference, values: inventory.preferences, into: &records)
        try append(section: .exerciseClaim, values: inventory.claims, into: &records)
        try append(section: .session, values: inventory.sessions, into: &records)
        try append(section: .shareReport, values: inventory.reports, into: &records)
        try append(section: .setting, values: inventory.settings, into: &records)

        let recordCount = UInt64(records.count + 1)
        let manifestJSON = try BackupJSONCodec.canonical(inventory.manifest(recordCount: recordCount))
        var payload = Data()
        try appendFrame(section: .manifest, json: manifestJSON, to: &payload)
        for record in records {
            try appendFrame(section: record.0, json: record.1, to: &payload)
        }
        return payload
    }

    static func decodeFrames(_ payload: Data) throws -> BackupInventory {
        let frames = try parseFrames(payload)
        guard let first = frames.first, first.section == .manifest else {
            throw BackupError.invalidState
        }
        let manifest = try BackupJSONCodec.decode(BackupManifest.self, from: first.json)
        guard manifest.payloadSchemaVersion == FineCoachBackupV1.payloadSchemaVersion else {
            throw BackupError.unsupportedVersion
        }
        guard UInt64(frames.count) == manifest.recordCount else {
            throw BackupError.invalidState
        }

        var inventory = BackupInventory(
            students: [],
            catalog: [],
            preferences: [],
            claims: [],
            sessions: [],
            reports: [],
            settings: []
        )
        for frame in frames.dropFirst() {
            switch frame.section {
            case .manifest:
                throw BackupError.invalidState
            case .student:
                inventory.students.append(try BackupJSONCodec.decode(Student.self, from: frame.json))
            case .exerciseCatalog:
                inventory.catalog.append(try BackupJSONCodec.decode(ExerciseCatalogItem.self, from: frame.json))
            case .exercisePreference:
                inventory.preferences.append(try BackupJSONCodec.decode(ExercisePreference.self, from: frame.json))
            case .exerciseClaim:
                inventory.claims.append(try BackupJSONCodec.decode(ExerciseNameClaim.self, from: frame.json))
            case .session:
                inventory.sessions.append(try BackupJSONCodec.decode(Session.self, from: frame.json))
            case .shareReport:
                inventory.reports.append(try BackupJSONCodec.decode(BackupShareReportRecord.self, from: frame.json))
            case .setting:
                inventory.settings.append(try BackupJSONCodec.decode(BackupSettingRecord.self, from: frame.json))
            }
        }
        try validateCounts(
            students: inventory.students.count,
            exercises: inventory.catalog.count,
            sessions: inventory.sessions.count,
            sessionExercises: inventory.sessionExerciseCount,
            sets: inventory.setCount,
            settings: inventory.settings.count
        )
        if inventory.students.count != manifest.studentCount
            || inventory.catalog.count != manifest.exerciseCount
            || inventory.sessions.count != manifest.sessionCount
            || inventory.sessionExerciseCount != manifest.sessionExerciseCount
            || inventory.setCount != manifest.setCount
            || inventory.reports.count != manifest.reportCount
            || inventory.settings.count != manifest.settingCount
        {
            throw BackupError.invalidState
        }
        return inventory
    }

    private static func validateCounts(
        students: Int,
        exercises: Int,
        sessions: Int,
        sessionExercises: Int,
        sets: Int,
        settings: Int
    ) throws {
        guard students <= BackupSecurityCeiling.maxStudents,
            exercises <= BackupSecurityCeiling.maxExercises,
            sessions <= BackupSecurityCeiling.maxSessions,
            sessionExercises <= BackupSecurityCeiling.maxSessionExercises,
            sets <= BackupSecurityCeiling.maxSets,
            settings <= BackupSecurityCeiling.maxSettings
        else {
            throw BackupError.limitExceeded
        }
    }

    private static func append<T: Encodable>(
        section: BackupFrameSection,
        values: [T],
        into records: inout [(BackupFrameSection, Data)]
    ) throws {
        for value in values {
            records.append((section, try BackupJSONCodec.canonical(value)))
        }
    }

    private static func appendFrame(section: BackupFrameSection, json: Data, to payload: inout Data) throws {
        guard json.count <= BackupSecurityCeiling.maxRecordBytes else {
            throw BackupError.limitExceeded
        }
        payload.append(section.rawValue)
        let length = UInt32(json.count)
        payload.append(UInt8(truncatingIfNeeded: length >> 24))
        payload.append(UInt8(truncatingIfNeeded: length >> 16))
        payload.append(UInt8(truncatingIfNeeded: length >> 8))
        payload.append(UInt8(truncatingIfNeeded: length))
        payload.append(json)
    }

    private static func parseFrames(_ payload: Data) throws -> [(section: BackupFrameSection, json: Data)] {
        var offset = 0
        var frames: [(BackupFrameSection, Data)] = []
        while offset < payload.count {
            guard offset + 5 <= payload.count else {
                throw BackupError.invalidState
            }
            guard let section = BackupFrameSection(rawValue: payload[offset]) else {
                throw BackupError.invalidState
            }
            let length =
                (UInt32(payload[offset + 1]) << 24) | (UInt32(payload[offset + 2]) << 16)
                | (UInt32(payload[offset + 3]) << 8) | UInt32(payload[offset + 4])
            offset += 5
            let end = offset + Int(length)
            guard end <= payload.count, length <= BackupSecurityCeiling.maxRecordBytes else {
                throw BackupError.limitExceeded
            }
            frames.append((section, payload.subdata(in: offset..<end)))
            offset = end
        }
        guard offset == payload.count else {
            throw BackupError.invalidState
        }
        return frames
    }

    private static func fetchAll(_ entityName: String, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try context.fetch(request)
    }
}
