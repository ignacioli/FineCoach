import XCTest

final class SharedVectorTests: XCTestCase {
    func testRealDomainBalance() throws {
        let files = try VectorFiles.files("s1/course-packages")
        XCTAssertEqual(files.count, 5)
        let runner = SharedVectorRunner(conformance: false)
        for file in files {
            try runner.run(Data(contentsOf: file), filename: file.lastPathComponent)
            try VectorFiles.report(file)
        }
        print("VECTOR-SUMMARY normal=5")
    }
}
