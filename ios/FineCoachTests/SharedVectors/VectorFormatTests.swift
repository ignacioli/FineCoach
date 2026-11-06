import XCTest

final class VectorFormatTests: XCTestCase {
    func testSharedConformance() throws {
        let files = try VectorFiles.files("runner-conformance")
        XCTAssertEqual(files.count, 72)
        var counts: [String: Int] = [:]
        for file in files {
            let root = try VectorFiles.decoded(file)
            let meta = try XCTUnwrap(root["meta"] as? [String: Any])
            let c = try XCTUnwrap(meta["conformance"] as? [String: Any])
            let outcome = try XCTUnwrap(c["outcome"] as? String)
            counts[outcome, default: 0] += 1
            try VectorFiles.checkConformance(file)
        }
        XCTAssertEqual(counts, ["pass": 15, "format": 44, "compare": 13])
        print("VECTOR-SUMMARY conformance=72 positive=15 negative=57")
    }
}
