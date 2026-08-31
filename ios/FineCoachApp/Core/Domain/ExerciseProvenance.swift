import Foundation

public enum ExerciseProvenanceGate: String, Codable, Sendable {
    case developmentPlaceholder
    case distributable
}

public struct ExerciseProvenanceRecord: Hashable, Codable, Sendable {
    public var recordID: String
    public var sourceIdentifier: String
    public var authorOrOwner: String
    public var licenseIdentifier: String
    public var licenseText: String
    public var redistributionAllowed: Bool
    public var attributionRequirement: String
    public var contentVersion: String
    public var reviewDate: String
    public var reviewerEvidence: String

    public init(
        recordID: String,
        sourceIdentifier: String,
        authorOrOwner: String,
        licenseIdentifier: String,
        licenseText: String,
        redistributionAllowed: Bool,
        attributionRequirement: String,
        contentVersion: String,
        reviewDate: String,
        reviewerEvidence: String
    ) {
        self.recordID = recordID
        self.sourceIdentifier = sourceIdentifier
        self.authorOrOwner = authorOrOwner
        self.licenseIdentifier = licenseIdentifier
        self.licenseText = licenseText
        self.redistributionAllowed = redistributionAllowed
        self.attributionRequirement = attributionRequirement
        self.contentVersion = contentVersion
        self.reviewDate = reviewDate
        self.reviewerEvidence = reviewerEvidence
    }
}

public struct ExerciseProvenanceManifest: Hashable, Codable, Sendable {
    public var catalogID: String
    public var contentVersion: String
    public var isFictionalPlaceholder: Bool
    public var records: [ExerciseProvenanceRecord]

    public init(
        catalogID: String,
        contentVersion: String,
        isFictionalPlaceholder: Bool,
        records: [ExerciseProvenanceRecord]
    ) {
        self.catalogID = catalogID
        self.contentVersion = contentVersion
        self.isFictionalPlaceholder = isFictionalPlaceholder
        self.records = records
    }
}

public struct ExerciseProvenanceIssue: Hashable, Sendable {
    public var recordID: String?
    public var field: String
    public var reason: String

    public init(recordID: String? = nil, field: String, reason: String) {
        self.recordID = recordID
        self.field = field
        self.reason = reason
    }
}

public struct ExerciseProvenanceValidationResult: Hashable, Sendable {
    public var isAccepted: Bool
    public var issues: [ExerciseProvenanceIssue]

    public init(isAccepted: Bool, issues: [ExerciseProvenanceIssue]) {
        self.isAccepted = isAccepted
        self.issues = issues
    }
}

public struct PlaceholderCatalogExercise: Hashable, Codable, Sendable {
    public var id: String
    public var canonicalName: String
    public var recordMode: RecordMode
    public var provenanceRef: String
    public var primaryMuscleGroup: String?
    public var equipmentClass: String?

    public init(
        id: String,
        canonicalName: String,
        recordMode: RecordMode,
        provenanceRef: String,
        primaryMuscleGroup: String? = nil,
        equipmentClass: String? = nil
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.recordMode = recordMode
        self.provenanceRef = provenanceRef
        self.primaryMuscleGroup = primaryMuscleGroup
        self.equipmentClass = equipmentClass
    }
}

public struct PlaceholderExerciseCatalog: Hashable, Codable, Sendable {
    public var metadataVersion: String
    public var exercises: [PlaceholderCatalogExercise]
    public var provenance: ExerciseProvenanceManifest

    public init(
        metadataVersion: String,
        exercises: [PlaceholderCatalogExercise],
        provenance: ExerciseProvenanceManifest
    ) {
        self.metadataVersion = metadataVersion
        self.exercises = exercises
        self.provenance = provenance
    }
}
