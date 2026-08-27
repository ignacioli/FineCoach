import FineCoach
import XCTest

final class SetupSmokeTests: XCTestCase {
    func testAppModuleLoadsWithStableFoundationTypes() throws {
        let identifier = StableUUID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        XCTAssertEqual(identifier.rawValue.uuidString.lowercased(), "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(FictitiousFixtures.student.displayName, "林青")
    }
}
