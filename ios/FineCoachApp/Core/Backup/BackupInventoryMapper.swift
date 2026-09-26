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
    // M1-B additions (data-model section 6, T042). Frame framing/parsing is
    // identical to the M1-A sections above -- same bounded/checked/fail-closed
    // codec, just new section IDs. An M1-A-only reader does not know these
    // cases exist, but never reaches them: its own (frozen, unmodified)
    // `minimumReaderVersion == 1` header check already rejects an M1-B file
    // before frame parsing starts (T043).
    case appointment = 9
    case recurrenceSeries = 10
    case coursePackage = 11
    case creditAdjustment = 12
    case trainingTemplate = 13
    case sessionSection = 14
    case bodyMetric = 15
    case bodyMeasurement = 16
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

/// Wraps the domain `Session` with the one additive M1-B field that lives
/// on `SessionMO` but is not part of the `Session` domain struct itself:
/// the optional link back to the `Appointment` that started this Session
/// (data-model section 6: "Session 的 appointmentID，作为已有 section 的增量字段").
/// Nothing in the live app writes this attribute today (M1-B links the
/// other way, via `Appointment.linkedSessionID`); it is carried through the
/// backup unchanged, whatever its current value, rather than silently
/// dropped.
struct BackupSessionRecord: Codable, Equatable, Sendable {
    var session: Session
    var appointmentID: StableUUID?
}

/// Wraps a `TrainingTemplate` with its ordered `TemplateExercise` rows.
/// Exercises live in a separate Core Data entity (`TemplateExerciseMO`,
/// FK `templateID`), but are nested in one frame per template here --
/// mirroring how a Session's Exercises/Sets are nested in one Session
/// frame -- so "ordered actions + planned data" (data-model section 6,
/// "trainingTemplates") round-trips as a single unit per template.
struct BackupTemplateRecord: Codable, Equatable, Sendable {
    var template: TrainingTemplate
    var exercises: [TemplateExercise]
}

/// `payloadSchemaVersion == 1` (M1-A) manifests have none of the M1-B count
/// fields below -- that is "this backup has zero of that entity type", not
/// malformed, so decoding fills them in as 0 via `decodeIfPresent` rather
/// than failing the whole manifest on a missing key (T043 forward-read
/// compatibility). This build always WRITES every field (payloadSchemaVersion
/// 2), so the manual `encode(to:)` below has nothing conditional in it.
struct BackupManifest: Equatable, Sendable {
    var payloadSchemaVersion: UInt16
    var studentCount: Int
    var exerciseCount: Int
    var sessionCount: Int
    var sessionExerciseCount: Int
    var setCount: Int
    var reportCount: Int
    var settingCount: Int
    var appointmentCount: Int
    var recurrenceSeriesCount: Int
    var coursePackageCount: Int
    var creditAdjustmentCount: Int
    var trainingTemplateCount: Int
    var templateExerciseCount: Int
    var sessionSectionCount: Int
    var bodyMetricCount: Int
    var bodyMeasurementCount: Int
    var recordCount: UInt64
}

extension BackupManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case payloadSchemaVersion
        case studentCount
        case exerciseCount
        case sessionCount
        case sessionExerciseCount
        case setCount
        case reportCount
        case settingCount
        case appointmentCount
        case recurrenceSeriesCount
        case coursePackageCount
        case creditAdjustmentCount
        case trainingTemplateCount
        case templateExerciseCount
        case sessionSectionCount
        case bodyMetricCount
        case bodyMeasurementCount
        case recordCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payloadSchemaVersion = try container.decode(UInt16.self, forKey: .payloadSchemaVersion)
        studentCount = try container.decode(Int.self, forKey: .studentCount)
        exerciseCount = try container.decode(Int.self, forKey: .exerciseCount)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        sessionExerciseCount = try container.decode(Int.self, forKey: .sessionExerciseCount)
        setCount = try container.decode(Int.self, forKey: .setCount)
        reportCount = try container.decode(Int.self, forKey: .reportCount)
        settingCount = try container.decode(Int.self, forKey: .settingCount)
        appointmentCount = try container.decodeIfPresent(Int.self, forKey: .appointmentCount) ?? 0
        recurrenceSeriesCount = try container.decodeIfPresent(Int.self, forKey: .recurrenceSeriesCount) ?? 0
        coursePackageCount = try container.decodeIfPresent(Int.self, forKey: .coursePackageCount) ?? 0
        creditAdjustmentCount = try container.decodeIfPresent(Int.self, forKey: .creditAdjustmentCount) ?? 0
        trainingTemplateCount = try container.decodeIfPresent(Int.self, forKey: .trainingTemplateCount) ?? 0
        templateExerciseCount = try container.decodeIfPresent(Int.self, forKey: .templateExerciseCount) ?? 0
        sessionSectionCount = try container.decodeIfPresent(Int.self, forKey: .sessionSectionCount) ?? 0
        bodyMetricCount = try container.decodeIfPresent(Int.self, forKey: .bodyMetricCount) ?? 0
        bodyMeasurementCount = try container.decodeIfPresent(Int.self, forKey: .bodyMeasurementCount) ?? 0
        recordCount = try container.decode(UInt64.self, forKey: .recordCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payloadSchemaVersion, forKey: .payloadSchemaVersion)
        try container.encode(studentCount, forKey: .studentCount)
        try container.encode(exerciseCount, forKey: .exerciseCount)
        try container.encode(sessionCount, forKey: .sessionCount)
        try container.encode(sessionExerciseCount, forKey: .sessionExerciseCount)
        try container.encode(setCount, forKey: .setCount)
        try container.encode(reportCount, forKey: .reportCount)
        try container.encode(settingCount, forKey: .settingCount)
        try container.encode(appointmentCount, forKey: .appointmentCount)
        try container.encode(recurrenceSeriesCount, forKey: .recurrenceSeriesCount)
        try container.encode(coursePackageCount, forKey: .coursePackageCount)
        try container.encode(creditAdjustmentCount, forKey: .creditAdjustmentCount)
        try container.encode(trainingTemplateCount, forKey: .trainingTemplateCount)
        try container.encode(templateExerciseCount, forKey: .templateExerciseCount)
        try container.encode(sessionSectionCount, forKey: .sessionSectionCount)
        try container.encode(bodyMetricCount, forKey: .bodyMetricCount)
        try container.encode(bodyMeasurementCount, forKey: .bodyMeasurementCount)
        try container.encode(recordCount, forKey: .recordCount)
    }
}

struct BackupInventory: Equatable, Sendable {
    var students: [Student]
    var catalog: [ExerciseCatalogItem]
    var preferences: [ExercisePreference]
    var claims: [ExerciseNameClaim]
    var sessions: [BackupSessionRecord]
    var reports: [BackupShareReportRecord]
    var settings: [BackupSettingRecord]
    // M1-B additions (data-model section 6 / spec section 6.7, T042).
    var appointments: [Appointment]
    var recurrenceSeries: [RecurrenceSeries]
    var coursePackages: [CoursePackage]
    var creditAdjustments: [CreditAdjustment]
    var templates: [BackupTemplateRecord]
    var sessionSections: [SessionSection]
    var bodyMetrics: [BodyMetricDefinition]
    var bodyMeasurements: [BodyMeasurement]

    var sessionExerciseCount: Int {
        sessions.reduce(0) { $0 + $1.session.exercises.count }
    }

    var setCount: Int {
        sessions.reduce(0) { $0 + $1.session.exercises.reduce(0) { $0 + $1.sets.count } }
    }

    var templateExerciseCount: Int {
        templates.reduce(0) { $0 + $1.exercises.count }
    }

    var inProgressSessions: [Session] {
        sessions.map(\.session).filter { $0.state == .inProgress }
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
            appointmentCount: appointments.count,
            recurrenceSeriesCount: recurrenceSeries.count,
            coursePackageCount: coursePackages.count,
            creditAdjustmentCount: creditAdjustments.count,
            trainingTemplateCount: templates.count,
            templateExerciseCount: templateExerciseCount,
            sessionSectionCount: sessionSections.count,
            bodyMetricCount: bodyMetrics.count,
            bodyMeasurementCount: bodyMeasurements.count,
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
        let appointmentObjects = try fetchAll(AppointmentManagedObjectMapping.entityName, in: context)
        let recurrenceSeriesObjects = try fetchAll(RecurrenceSeriesManagedObjectMapping.entityName, in: context)
        let coursePackageObjects = try fetchAll(CoursePackageManagedObjectMapping.entityName, in: context)
        let creditAdjustmentObjects = try fetchAll(
            CoursePackageManagedObjectMapping.adjustmentEntityName, in: context
        )
        let templateObjects = try fetchAll(TemplateManagedObjectMapping.templateEntityName, in: context)
        let templateExerciseObjects = try fetchAll(TemplateManagedObjectMapping.exerciseEntityName, in: context)
        let sessionSectionObjects = try fetchAll(SessionSectionManagedObjectMapping.entityName, in: context)
        let bodyMetricObjects = try fetchAll(BodyMetricManagedObjectMapping.metricEntityName, in: context)
        let bodyMeasurementObjects = try fetchAll(BodyMetricManagedObjectMapping.measurementEntityName, in: context)

        let students = try studentObjects.map { try StudentManagedObjectMapping.makeStudent(from: $0) }
        let catalog = try catalogObjects.map { try ExerciseManagedObjectMapping.makeCatalogItem(from: $0) }
        let preferences = try preferenceObjects.map { try ExerciseManagedObjectMapping.makePreference(from: $0) }
        let claims = try claimObjects.map { try ExerciseManagedObjectMapping.makeClaim(from: $0) }
        let sessions: [BackupSessionRecord] = try sessionObjects.map { object in
            let session = try SessionManagedObjectMapping.loadAggregate(from: object, in: context)
            let appointmentID = (object.value(forKey: "appointmentID") as? UUID).map { StableUUID($0) }
            return BackupSessionRecord(session: session, appointmentID: appointmentID)
        }
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
        let appointments = try appointmentObjects.map { try AppointmentManagedObjectMapping.makeAppointment(from: $0) }
        let recurrenceSeries = try recurrenceSeriesObjects.map {
            try RecurrenceSeriesManagedObjectMapping.makeSeries(from: $0)
        }
        let coursePackages = try coursePackageObjects.map { try CoursePackageManagedObjectMapping.makePackage(from: $0) }
        let creditAdjustments = try creditAdjustmentObjects.map {
            try CoursePackageManagedObjectMapping.makeAdjustment(from: $0)
        }
        let allTemplateExercises = try templateExerciseObjects.map {
            try TemplateManagedObjectMapping.makeExercise(from: $0)
        }
        let templates: [BackupTemplateRecord] = try templateObjects.map { object in
            let template = try TemplateManagedObjectMapping.makeTemplate(from: object)
            let exercises =
                allTemplateExercises
                .filter { $0.templateID == template.id }
                .sorted { $0.orderIndex < $1.orderIndex }
            return BackupTemplateRecord(template: template, exercises: exercises)
        }
        let sessionSections = try sessionSectionObjects.map { try SessionSectionManagedObjectMapping.makeSection(from: $0) }
        let bodyMetrics = try bodyMetricObjects.map { try BodyMetricManagedObjectMapping.makeMetric(from: $0) }
        let bodyMeasurements = try bodyMeasurementObjects.map {
            try BodyMetricManagedObjectMapping.makeMeasurement(from: $0)
        }

        try validateCounts(
            students: students.count,
            exercises: catalog.count,
            sessions: sessions.count,
            sessionExercises: sessions.reduce(0) { $0 + $1.session.exercises.count },
            sets: sessions.reduce(0) { $0 + $1.session.exercises.reduce(0) { $0 + $1.sets.count } },
            settings: settings.count,
            appointments: appointments.count,
            recurrenceSeries: recurrenceSeries.count,
            coursePackages: coursePackages.count,
            creditAdjustments: creditAdjustments.count,
            trainingTemplates: templates.count,
            templateExercises: allTemplateExercises.count,
            sessionSections: sessionSections.count,
            bodyMetrics: bodyMetrics.count,
            bodyMeasurements: bodyMeasurements.count
        )
        return BackupInventory(
            students: students,
            catalog: catalog,
            preferences: preferences,
            claims: claims,
            sessions: sessions,
            reports: reports,
            settings: settings,
            appointments: appointments,
            recurrenceSeries: recurrenceSeries,
            coursePackages: coursePackages,
            creditAdjustments: creditAdjustments,
            templates: templates,
            sessionSections: sessionSections,
            bodyMetrics: bodyMetrics,
            bodyMeasurements: bodyMeasurements
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
        try append(section: .appointment, values: inventory.appointments, into: &records)
        try append(section: .recurrenceSeries, values: inventory.recurrenceSeries, into: &records)
        try append(section: .coursePackage, values: inventory.coursePackages, into: &records)
        try append(section: .creditAdjustment, values: inventory.creditAdjustments, into: &records)
        try append(section: .trainingTemplate, values: inventory.templates, into: &records)
        try append(section: .sessionSection, values: inventory.sessionSections, into: &records)
        try append(section: .bodyMetric, values: inventory.bodyMetrics, into: &records)
        try append(section: .bodyMeasurement, values: inventory.bodyMeasurements, into: &records)

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
        // Defense-in-depth mirror of FineCoachBackupHeader.validateVersionFields:
        // the header-level check (before decryption even starts) is the real
        // gate for D-M1B-009's "reject any pre-Revision-1.2 backup", but this
        // payload-level manifest check exists too in case header and payload
        // ever disagree (corruption).
        guard manifest.payloadSchemaVersion >= FineCoachBackupV1.minimumSupportedPayloadSchemaVersion else {
            throw BackupError.incompatiblePayloadVersion
        }
        guard manifest.payloadSchemaVersion <= FineCoachBackupV1.payloadSchemaVersion else {
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
            settings: [],
            appointments: [],
            recurrenceSeries: [],
            coursePackages: [],
            creditAdjustments: [],
            templates: [],
            sessionSections: [],
            bodyMetrics: [],
            bodyMeasurements: []
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
                inventory.sessions.append(try BackupJSONCodec.decode(BackupSessionRecord.self, from: frame.json))
            case .shareReport:
                inventory.reports.append(try BackupJSONCodec.decode(BackupShareReportRecord.self, from: frame.json))
            case .setting:
                inventory.settings.append(try BackupJSONCodec.decode(BackupSettingRecord.self, from: frame.json))
            case .appointment:
                inventory.appointments.append(try BackupJSONCodec.decode(Appointment.self, from: frame.json))
            case .recurrenceSeries:
                inventory.recurrenceSeries.append(try BackupJSONCodec.decode(RecurrenceSeries.self, from: frame.json))
            case .coursePackage:
                inventory.coursePackages.append(try BackupJSONCodec.decode(CoursePackage.self, from: frame.json))
            case .creditAdjustment:
                inventory.creditAdjustments.append(try BackupJSONCodec.decode(CreditAdjustment.self, from: frame.json))
            case .trainingTemplate:
                inventory.templates.append(try BackupJSONCodec.decode(BackupTemplateRecord.self, from: frame.json))
            case .sessionSection:
                inventory.sessionSections.append(try BackupJSONCodec.decode(SessionSection.self, from: frame.json))
            case .bodyMetric:
                inventory.bodyMetrics.append(try BackupJSONCodec.decode(BodyMetricDefinition.self, from: frame.json))
            case .bodyMeasurement:
                inventory.bodyMeasurements.append(try BackupJSONCodec.decode(BodyMeasurement.self, from: frame.json))
            }
        }
        try validateCounts(
            students: inventory.students.count,
            exercises: inventory.catalog.count,
            sessions: inventory.sessions.count,
            sessionExercises: inventory.sessionExerciseCount,
            sets: inventory.setCount,
            settings: inventory.settings.count,
            appointments: inventory.appointments.count,
            recurrenceSeries: inventory.recurrenceSeries.count,
            coursePackages: inventory.coursePackages.count,
            creditAdjustments: inventory.creditAdjustments.count,
            trainingTemplates: inventory.templates.count,
            templateExercises: inventory.templateExerciseCount,
            sessionSections: inventory.sessionSections.count,
            bodyMetrics: inventory.bodyMetrics.count,
            bodyMeasurements: inventory.bodyMeasurements.count
        )
        if inventory.students.count != manifest.studentCount
            || inventory.catalog.count != manifest.exerciseCount
            || inventory.sessions.count != manifest.sessionCount
            || inventory.sessionExerciseCount != manifest.sessionExerciseCount
            || inventory.setCount != manifest.setCount
            || inventory.reports.count != manifest.reportCount
            || inventory.settings.count != manifest.settingCount
            || inventory.appointments.count != manifest.appointmentCount
            || inventory.recurrenceSeries.count != manifest.recurrenceSeriesCount
            || inventory.coursePackages.count != manifest.coursePackageCount
            || inventory.creditAdjustments.count != manifest.creditAdjustmentCount
            || inventory.templates.count != manifest.trainingTemplateCount
            || inventory.templateExerciseCount != manifest.templateExerciseCount
            || inventory.sessionSections.count != manifest.sessionSectionCount
            || inventory.bodyMetrics.count != manifest.bodyMetricCount
            || inventory.bodyMeasurements.count != manifest.bodyMeasurementCount
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
        settings: Int,
        appointments: Int,
        recurrenceSeries: Int,
        coursePackages: Int,
        creditAdjustments: Int,
        trainingTemplates: Int,
        templateExercises: Int,
        sessionSections: Int,
        bodyMetrics: Int,
        bodyMeasurements: Int
    ) throws {
        guard students <= BackupSecurityCeiling.maxStudents,
            exercises <= BackupSecurityCeiling.maxExercises,
            sessions <= BackupSecurityCeiling.maxSessions,
            sessionExercises <= BackupSecurityCeiling.maxSessionExercises,
            sets <= BackupSecurityCeiling.maxSets,
            settings <= BackupSecurityCeiling.maxSettings,
            appointments <= BackupSecurityCeiling.maxAppointments,
            recurrenceSeries <= BackupSecurityCeiling.maxRecurrenceSeries,
            coursePackages <= BackupSecurityCeiling.maxCoursePackages,
            creditAdjustments <= BackupSecurityCeiling.maxCreditAdjustments,
            trainingTemplates <= BackupSecurityCeiling.maxTrainingTemplates,
            templateExercises <= BackupSecurityCeiling.maxTemplateExercises,
            sessionSections <= BackupSecurityCeiling.maxSessionSections,
            bodyMetrics <= BackupSecurityCeiling.maxBodyMetrics,
            bodyMeasurements <= BackupSecurityCeiling.maxBodyMeasurements
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
