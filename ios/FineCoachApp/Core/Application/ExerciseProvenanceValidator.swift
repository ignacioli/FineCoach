import Foundation

public enum ExerciseProvenanceValidator: Sendable {
    private static let manifestRequiredKeys = [
        "catalogID",
        "contentVersion",
        "isFictionalPlaceholder",
        "records",
    ]
    private static let recordRequiredKeys = [
        "recordID",
        "sourceIdentifier",
        "authorOrOwner",
        "licenseIdentifier",
        "licenseText",
        "redistributionAllowed",
        "attributionRequirement",
        "contentVersion",
        "reviewDate",
        "reviewerEvidence",
    ]
    private static let recordRequiredStringKeys = [
        "recordID",
        "sourceIdentifier",
        "authorOrOwner",
        "licenseIdentifier",
        "licenseText",
        "attributionRequirement",
        "contentVersion",
        "reviewDate",
        "reviewerEvidence",
    ]

    public static func validate(
        _ manifest: ExerciseProvenanceManifest,
        gate: ExerciseProvenanceGate
    ) -> ExerciseProvenanceValidationResult {
        var issues: [ExerciseProvenanceIssue] = []
        appendEmptyStringIssue(manifest.catalogID, field: "catalogID", recordID: nil, into: &issues)
        appendEmptyStringIssue(manifest.contentVersion, field: "contentVersion", recordID: nil, into: &issues)

        switch gate {
        case .distributable:
            if manifest.isFictionalPlaceholder {
                issues.append(
                    ExerciseProvenanceIssue(
                        field: "isFictionalPlaceholder",
                        reason: "placeholder must not pass as shippable content"
                    )
                )
            }
        case .developmentPlaceholder:
            if !manifest.isFictionalPlaceholder {
                issues.append(
                    ExerciseProvenanceIssue(
                        field: "isFictionalPlaceholder",
                        reason: "placeholder must not impersonate distributable content"
                    )
                )
            }
        }

        for record in manifest.records {
            appendRecordIssues(record, gate: gate, into: &issues)
        }

        return ExerciseProvenanceValidationResult(isAccepted: issues.isEmpty, issues: issues)
    }

    public static func validateJSONData(
        _ data: Data,
        gate: ExerciseProvenanceGate
    ) throws -> ExerciseProvenanceValidationResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DomainError.incompatibleInput
        }
        guard let root = object as? [String: Any] else {
            throw DomainError.incompatibleInput
        }

        var issues: [ExerciseProvenanceIssue] = []
        collectJSONIssues(from: root, into: &issues)

        if let manifest = try? JSONDecoder().decode(ExerciseProvenanceManifest.self, from: data) {
            let merged = merging(issues, validate(manifest, gate: gate).issues)
            return ExerciseProvenanceValidationResult(isAccepted: merged.isEmpty, issues: merged)
        }

        if issues.isEmpty {
            throw DomainError.incompatibleInput
        }
        return ExerciseProvenanceValidationResult(isAccepted: false, issues: issues)
    }

    private static func appendRecordIssues(
        _ record: ExerciseProvenanceRecord,
        gate: ExerciseProvenanceGate,
        into issues: inout [ExerciseProvenanceIssue]
    ) {
        let recordID = issueRecordID(record.recordID)
        let fields: [(String, String)] = [
            ("recordID", record.recordID),
            ("sourceIdentifier", record.sourceIdentifier),
            ("authorOrOwner", record.authorOrOwner),
            ("licenseIdentifier", record.licenseIdentifier),
            ("licenseText", record.licenseText),
            ("attributionRequirement", record.attributionRequirement),
            ("contentVersion", record.contentVersion),
            ("reviewDate", record.reviewDate),
            ("reviewerEvidence", record.reviewerEvidence),
        ]
        for (field, value) in fields {
            appendEmptyStringIssue(value, field: field, recordID: recordID, into: &issues)
        }
        if gate == .distributable && !record.redistributionAllowed {
            issues.append(
                ExerciseProvenanceIssue(
                    recordID: recordID,
                    field: "redistributionAllowed",
                    reason: "redistribution is not allowed"
                )
            )
        }
    }

    private static func collectJSONIssues(
        from root: [String: Any],
        into issues: inout [ExerciseProvenanceIssue]
    ) {
        for key in manifestRequiredKeys where jsonValue(in: root, key: key) == nil {
            issues.append(
                ExerciseProvenanceIssue(field: key, reason: "required field is missing")
            )
        }
        appendEmptyJSONStringIssue(in: root, key: "catalogID", recordID: nil, into: &issues)
        appendEmptyJSONStringIssue(in: root, key: "contentVersion", recordID: nil, into: &issues)

        guard let recordsValue = jsonValue(in: root, key: "records") else {
            return
        }
        guard let records = recordsValue as? [Any] else {
            return
        }
        for item in records {
            guard let record = item as? [String: Any] else {
                continue
            }
            let recordID = (jsonValue(in: record, key: "recordID") as? String).flatMap(issueRecordID)
            for key in recordRequiredKeys where jsonValue(in: record, key: key) == nil {
                issues.append(
                    ExerciseProvenanceIssue(
                        recordID: recordID,
                        field: key,
                        reason: "required field is missing"
                    )
                )
            }
            for key in recordRequiredStringKeys {
                appendEmptyJSONStringIssue(in: record, key: key, recordID: recordID, into: &issues)
            }
        }
    }

    private static func appendEmptyStringIssue(
        _ rawValue: String,
        field: String,
        recordID: String?,
        into issues: inout [ExerciseProvenanceIssue]
    ) {
        guard normalized(rawValue).isEmpty else {
            return
        }
        issues.append(
            ExerciseProvenanceIssue(
                recordID: recordID,
                field: field,
                reason: "required field is empty"
            )
        )
    }

    private static func appendEmptyJSONStringIssue(
        in object: [String: Any],
        key: String,
        recordID: String?,
        into issues: inout [ExerciseProvenanceIssue]
    ) {
        guard let value = jsonValue(in: object, key: key) as? String else {
            return
        }
        appendEmptyStringIssue(value, field: key, recordID: recordID, into: &issues)
    }

    private static func jsonValue(in object: [String: Any], key: String) -> Any? {
        guard let value = object[key], !(value is NSNull) else {
            return nil
        }
        return value
    }

    private static func normalized(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func issueRecordID(_ rawValue: String) -> String? {
        let value = normalized(rawValue)
        return value.isEmpty ? nil : value
    }

    private static func merging(
        _ lhs: [ExerciseProvenanceIssue],
        _ rhs: [ExerciseProvenanceIssue]
    ) -> [ExerciseProvenanceIssue] {
        var seen = Set<ExerciseProvenanceIssue>()
        var merged: [ExerciseProvenanceIssue] = []
        for issue in lhs + rhs where seen.insert(issue).inserted {
            merged.append(issue)
        }
        return merged
    }
}

public enum PlaceholderExerciseCatalogLoader {
    public static func loadFromBundle(_ bundle: Bundle) throws -> PlaceholderExerciseCatalog {
        let candidates = [bundle, Bundle(for: PersistenceController.self)]
        for candidate in candidates {
            if let url = catalogURL(in: candidate) {
                return try decodeCatalog(at: url)
            }
        }
        throw DomainError.notFound
    }

    private static func decodeCatalog(at url: URL) throws -> PlaceholderExerciseCatalog {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DomainError.invalidFileOperation
        }
        do {
            return try JSONDecoder().decode(PlaceholderExerciseCatalog.self, from: data)
        } catch {
            throw DomainError.incompatibleInput
        }
    }

    private static func catalogURL(in bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: "provenance", withExtension: "json") {
            return url
        }
        return bundle.url(
            forResource: "provenance",
            withExtension: "json",
            subdirectory: "ExerciseCatalog"
        )
    }

    public static func facet(forExerciseID id: String) -> ExerciseCatalogBrowseFacet? {
        facetsByID()[id]
    }

    public static func facetsByID() -> [String: ExerciseCatalogBrowseFacet] {
        facetCache.facets()
    }

    /// Returns the Foundation-derived search forms for built-in catalog items.
    /// The catalog is immutable for the lifetime of a process, so this work is
    /// performed once alongside the existing facet cache rather than during
    /// every browse query.
    public static func pinyinTokens(forExerciseID id: String) -> ExercisePinyinSearchTokens? {
        pinyinCache.tokensByID()[id]
    }

    private static let facetCache = FacetCache()
    private static let pinyinCache = PinyinCache()

    private final class FacetCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: [String: ExerciseCatalogBrowseFacet]?

        func facets() -> [String: ExerciseCatalogBrowseFacet] {
            lock.lock()
            defer { lock.unlock() }
            if let cached {
                return cached
            }
            let catalog: PlaceholderExerciseCatalog
            do {
                catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle.main)
            } catch {
                cached = [:]
                return [:]
            }
            var loaded: [String: ExerciseCatalogBrowseFacet] = [:]
            loaded.reserveCapacity(catalog.exercises.count)
            for exercise in catalog.exercises {
                guard let muscle = exercise.primaryMuscleGroup, let equipment = exercise.equipmentClass
                else {
                    continue
                }
                loaded[exercise.id] = ExerciseCatalogBrowseFacet(
                    primaryMuscleGroup: muscle,
                    equipmentClass: equipment,
                    secondaryMuscleGroups: exercise.secondaryMuscleGroups ?? [],
                    isUnilateral: exercise.unilateral ?? false
                )
            }
            // Warm the built-in search forms with the same catalog read. A
            // typed search must only look up these values, never transliterate
            // the full built-in catalog on its hot path.
            _ = pinyinCache.tokensByID()
            cached = loaded
            return loaded
        }
    }

    private final class PinyinCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: [String: ExercisePinyinSearchTokens]?

        func tokensByID() -> [String: ExercisePinyinSearchTokens] {
            lock.lock()
            defer { lock.unlock() }
            if let cached {
                return cached
            }
            let catalog: PlaceholderExerciseCatalog
            do {
                catalog = try PlaceholderExerciseCatalogLoader.loadFromBundle(Bundle.main)
            } catch {
                cached = [:]
                return [:]
            }
            var loaded: [String: ExercisePinyinSearchTokens] = [:]
            loaded.reserveCapacity(catalog.exercises.count)
            for exercise in catalog.exercises {
                loaded[exercise.id] = ExercisePinyinSearch.tokens(for: exercise.canonicalName)
            }
            cached = loaded
            return loaded
        }
    }
}

/// Search forms derived from a display name using Foundation's Mandarin
/// transliteration. `sourceValue` lets callers detect a catalog-content change
/// before reusing an id-based precomputed token.
public struct ExercisePinyinSearchTokens: Hashable, Sendable {
    public let sourceValue: String
    public let fullPinyin: String
    public let initials: String

    public init(sourceValue: String, fullPinyin: String, initials: String) {
        self.sourceValue = sourceValue
        self.fullPinyin = fullPinyin
        self.initials = initials
    }
}

public enum ExercisePinyinSearch {
    // Product decision on 2026-10-19: fix these two polyphonic characters only.
    // Keep the surrounding spaces to preserve syllable boundaries for adjacent overrides.
    private static let fixedPolyphonicPinyin: [Character: String] = [
        "弹": " tan ",
        "地": " di ",
    ]
    private static let cache = TokenCache()

    public static func tokens(for value: String) -> ExercisePinyinSearchTokens {
        cache.tokens(for: value)
    }

    public static func normalizedQuery(_ query: String) -> String {
        removeWhitespace(
            query
                .precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        ).lowercased()
    }

    public static func matches(
        tokens: ExercisePinyinSearchTokens,
        normalizedQuery: String
    ) -> Bool {
        guard !normalizedQuery.isEmpty else {
            return false
        }
        return tokens.fullPinyin.contains(normalizedQuery) || tokens.initials.contains(normalizedQuery)
    }

    public static func matches(value: String, query: String) -> Bool {
        matches(tokens: tokens(for: value), normalizedQuery: normalizedQuery(query))
    }

    private static func removeWhitespace(_ value: String) -> String {
        value.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func makeTokens(for value: String) -> ExercisePinyinSearchTokens {
        let sourceValue = value.precomposedStringWithCanonicalMapping
        let transliterationInput =
            sourceValue
            .map { fixedPolyphonicPinyin[$0] ?? String($0) }
            .joined()
        let transformed =
            transliterationInput.applyingTransform(.mandarinToLatin, reverse: false)
            ?? transliterationInput
        let folded = transformed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let fullPinyin = removeWhitespace(folded).lowercased()
        let initials =
            transformed
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { token in
                token.first(where: { $0.isLetter || $0.isNumber }).map(String.init)
            }
            .joined()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return ExercisePinyinSearchTokens(
            sourceValue: sourceValue,
            fullPinyin: fullPinyin,
            initials: initials
        )
    }

    private final class TokenCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: ExercisePinyinSearchTokens] = [:]

        func tokens(for value: String) -> ExercisePinyinSearchTokens {
            let key = value.precomposedStringWithCanonicalMapping
            lock.lock()
            defer { lock.unlock() }
            if let cached = values[key] {
                return cached
            }
            let computed = ExercisePinyinSearch.makeTokens(for: key)
            values[key] = computed
            return computed
        }
    }
}
