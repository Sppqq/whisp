import XCTest
@testable import Whisp

final class UpdateServiceTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertLessThan(AppVersion("1.0.9")!, AppVersion("1.1.0")!)
        XCTAssertLessThan(AppVersion("1.1.0-beta.1")!, AppVersion("1.1.0")!)
        XCTAssertEqual(AppVersion("v1.1")!, AppVersion("1.1.0")!)
        XCTAssertGreaterThan(AppVersion("2.0.0")!, AppVersion("1.99.99")!)
    }

    func testRejectsMalformedVersions() {
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..0"))
        XCTAssertNil(AppVersion(""))
    }
}
