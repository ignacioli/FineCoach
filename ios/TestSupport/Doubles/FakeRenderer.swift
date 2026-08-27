import FineCoach
import Foundation

public struct FakeRenderer: Renderer, Sendable {
    public let output: [Data]

    public init(output: [Data] = [Data("fake-rendered-output".utf8)]) {
        self.output = output
    }

    public func render(_ request: RendererRequest) throws -> [Data] {
        output
    }
}
