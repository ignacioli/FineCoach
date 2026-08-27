import Foundation

public struct FictitiousStudentFixture: Codable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let trainingGoal: String
    public let syntheticNote: String

    public init(
        id: UUID,
        displayName: String,
        trainingGoal: String,
        syntheticNote: String
    ) {
        self.id = id
        self.displayName = displayName
        self.trainingGoal = trainingGoal
        self.syntheticNote = syntheticNote
    }
}

public enum FictitiousFixtures {
    public static let student = FictitiousStudentFixture(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        displayName: "林青",
        trainingGoal: "提升基础力量",
        syntheticNote: "合成测试备注：保持动作节奏。"
    )

    public static let secondStudent = FictitiousStudentFixture(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        displayName: "周宁",
        trainingGoal: "建立稳定训练习惯",
        syntheticNote: "合成测试备注：按计划记录。"
    )
}
