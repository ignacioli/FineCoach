import Foundation

/// Canonical display spelling only; provenance records remain unchanged.
enum ExerciseLicensePresentation {
    static func displayName(_ raw: String) -> String {
        switch raw {
        case "CC-BY-SA 4", "CC-BY-SA 4.0", "CC-BY-SA-4.0": return "CC BY-SA 4.0"
        case "CC-BY-SA 3", "CC-BY-SA 3.0", "CC-BY-SA-3.0": return "CC BY-SA 3.0"
        case "CC0", "CC0-1.0": return "CC0 1.0"
        default: return raw
        }
    }

    static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map(displayName).filter { seen.insert($0).inserted }
    }
}

struct CoachAboutSource: Equatable, Identifiable {
    let id: String
    let count: Int
    let licenses: [String]

    var displayName: String {
        id == "finecoach-built" ? String(localized: "about.source.built") : id
    }

    var text: String {
        String(
            format: String(localized: "about.source.format"),
            displayName, count, licenses.joined(separator: " / "))
    }

    static func rows(catalog: PlaceholderExerciseCatalog) throws -> [Self] {
        let records = Dictionary(uniqueKeysWithValues: catalog.provenance.records.map { ($0.recordID, $0) })
        var grouped: [String: [String]] = [:]
        for exercise in catalog.exercises {
            guard let record = records[exercise.provenanceRef] else { throw DomainError.incompatibleInput }
            let source = String(record.sourceIdentifier.split(separator: ":", maxSplits: 1)[0])
            grouped[source, default: []].append(record.licenseIdentifier)
        }
        return grouped.map { source, licenses in
            Self(
                id: source, count: licenses.count, licenses: ExerciseLicensePresentation.uniqueNames(licenses).sorted())
        }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }
}
