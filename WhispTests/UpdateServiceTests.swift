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

    func testUpdateStateEquality() {
        let release = WhispRelease(
            version: "1.2.0",
            title: "Whisp 1.2.0",
            notes: "Test notes",
            pageURL: URL(string: "https://example.com")!,
            downloadURL: URL(string: "https://example.com/Whisp.dmg")!,
            isPrerelease: false
        )
        XCTAssertEqual(UpdateState.idle, UpdateState.idle)
        XCTAssertEqual(UpdateState.checking, UpdateState.checking)
        XCTAssertEqual(UpdateState.installing(release), UpdateState.installing(release))
        XCTAssertNotEqual(UpdateState.downloading(release), UpdateState.installing(release))
    }

    func testUpdaterScriptContainsCriticalOperations() {
        let script = UpdateService.updaterScriptContent
        XCTAssertTrue(script.contains("kill -0 \"$PID\""))
        XCTAssertTrue(script.contains("ditto \"$STAGE_APP\" \"$TARGET_APP\""))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("open \"$TARGET_APP\""))
    }
}
