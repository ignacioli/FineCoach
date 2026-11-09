import XCTest

final class SharedVectorTests: XCTestCase {
    func testRealDomainBalance() throws {
        let files = try VectorFiles.files("s1/course-packages").filter { $0.lastPathComponent.contains("__s0-") || $0.lastPathComponent.hasSuffix("__s1-package-ledger-balance.json") }
        XCTAssertEqual(files.count, 5)
        let runner = SharedVectorRunner(conformance: false)
        for file in files {
            try runner.run(Data(contentsOf: file), filename: file.lastPathComponent)
            try VectorFiles.report(file)
        }
        print("VECTOR-SUMMARY normal=5")
    }
}
