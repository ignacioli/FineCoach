import CoreData
import Foundation

enum CandidateGenerationBuilder {
    static func apply(
        _ inventory: BackupInventory,
        in context: NSManagedObjectContext
    ) throws -> Session? {
        let inProgress = inventory.inProgressSessions
        guard inProgress.count <= 1 else {
            throw BackupError.invalidState
        }
        // `CoursePackage.status == .active` is authoritative M1-B inventory
        // data; the `ActiveCoursePackageClaimMO` uniqueness row is a derived
        // enforcement structure that is never itself part of the backup
        // (spec section 6.7 lists only `status`), so a corrupt/malicious file
        // claiming two simultaneously-active packages for one Student MUST
        // fail closed here, the same way >1 in-progress Session does above.
        let activePackagesByStudent = Dictionary(
            grouping: inventory.coursePackages.filter { $0.status == .active },
            by: \.studentID
        )
        guard activePackagesByStudent.values.allSatisfy({ $0.count <= 1 }) else {
            throw BackupError.invalidState
        }

        for student in inventory.students {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: StudentManagedObjectMapping.entityName,
                into: context
            )
            StudentManagedObjectMapping.apply(student, to: object)
        }
        for item in inventory.catalog {
            _ = try ExerciseManagedObjectMapping.upsertCatalogItem(item, in: context)
        }
        for preference in inventory.preferences {
            _ = try ExerciseManagedObjectMapping.upsertPreference(preference, in: context)
        }
        for claim in inventory.claims {
            try ExerciseManagedObjectMapping.acquireUnifiedClaim(claim, in: context)
        }

        for package in inventory.coursePackages {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: CoursePackageManagedObjectMapping.entityName,
                into: context
            )
            CoursePackageManagedObjectMapping.apply(package, to: object)
        }
        for (studentID, activePackages) in activePackagesByStudent {
            guard let package = activePackages.first else {
                continue
            }
            CoursePackageManagedObjectMapping.insertClaim(
                studentID: studentID.rawValue,
                packageID: package.id.rawValue,
                in: context
            )
        }
        for adjustment in inventory.creditAdjustments {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: CoursePackageManagedObjectMapping.adjustmentEntityName,
                into: context
            )
            CoursePackageManagedObjectMapping.apply(adjustment, to: object)
        }

        for series in inventory.recurrenceSeries {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: RecurrenceSeriesManagedObjectMapping.entityName,
                into: context
            )
            RecurrenceSeriesManagedObjectMapping.apply(series, to: object)
        }
        for appointment in inventory.appointments {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: AppointmentManagedObjectMapping.entityName,
                into: context
            )
            AppointmentManagedObjectMapping.apply(appointment, to: object)
        }

        let orderedSessions =
            inventory.sessions.filter { $0.session.state != .inProgress }
            + inventory.sessions.filter { $0.session.state == .inProgress }
        for record in orderedSessions {
            let restored = try SessionManagedObjectMapping.upsertAggregate(record.session, in: context)
            if let appointmentID = record.appointmentID {
                let sessionObject = try SessionManagedObjectMapping.requireSession(
                    id: restored.id.rawValue,
                    in: context
                )
                sessionObject.setValue(appointmentID.rawValue, forKey: "appointmentID")
            }
        }

        for record in inventory.templates {
            let templateObject = NSEntityDescription.insertNewObject(
                forEntityName: TemplateManagedObjectMapping.templateEntityName,
                into: context
            )
            TemplateManagedObjectMapping.apply(record.template, to: templateObject)
            for exercise in record.exercises {
                let exerciseObject = NSEntityDescription.insertNewObject(
                    forEntityName: TemplateManagedObjectMapping.exerciseEntityName,
                    into: context
                )
                try TemplateManagedObjectMapping.apply(exercise, to: exerciseObject)
            }
        }
        for section in inventory.sessionSections {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: SessionSectionManagedObjectMapping.entityName,
                into: context
            )
            SessionSectionManagedObjectMapping.apply(section, to: object)
        }
        for metric in inventory.bodyMetrics {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: BodyMetricManagedObjectMapping.metricEntityName,
                into: context
            )
            try BodyMetricManagedObjectMapping.apply(metric, to: object)
        }
        for measurement in inventory.bodyMeasurements {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: BodyMetricManagedObjectMapping.measurementEntityName,
                into: context
            )
            BodyMetricManagedObjectMapping.apply(measurement, to: object)
        }

        for record in inventory.reports {
            _ = try HistoryReportManagedObjectMapping.upsertReport(
                record.report,
                modules: record.modules,
                in: context
            )
        }
        for setting in inventory.settings {
            let request = NSFetchRequest<NSManagedObject>(
                entityName: StudentManagedObjectMapping.settingEntityName
            )
            request.predicate = NSPredicate(format: "key == %@", setting.key)
            request.fetchLimit = 1
            let object =
                try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(
                    forEntityName: StudentManagedObjectMapping.settingEntityName,
                    into: context
                )
            object.setValue(setting.key, forKey: "key")
            object.setValue(setting.typedValue, forKey: "typedValue")
            object.setValue(setting.schemaVersion, forKey: "schemaVersion")
        }

        if let active = inProgress.first {
            return try SessionManagedObjectMapping.loadAggregate(
                from: try SessionManagedObjectMapping.requireSession(id: active.id.rawValue, in: context),
                in: context
            )
        }
        if let pointer = try SessionManagedObjectMapping.fetchPointer(in: context) {
            context.delete(pointer)
        }
        return nil
    }
}
