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

    func testPostUpdateScreenOnlyAppearsForARealUpgrade() {
        XCTAssertTrue(UpdateService.isUpgrade(from: "1.1.10", to: "1.1.11"))
        XCTAssertTrue(UpdateService.isUpgrade(from: "1.1.11-alpha.2", to: "1.1.11"))
        XCTAssertFalse(UpdateService.isUpgrade(from: "1.1.11", to: "1.1.11"))
        XCTAssertFalse(UpdateService.isUpgrade(from: nil, to: "1.1.11"))
        XCTAssertFalse(UpdateService.isUpgrade(from: "latest", to: "1.1.11"))
    }

    func testUpdateStateEquality() {
        let release = WhispRelease(
            version: "1.2.0",
            title: "Whisp 1.2.0",
            notes: "Test notes",
            pageURL: URL(string: "https://example.com")!,
            downloadURL: URL(string: "https://example.com/Whisp.dmg")!,
            isPrerelease: false,
            checksumURL: URL(string: "https://example.com/Whisp.dmg.sha256")!
        )
        XCTAssertEqual(UpdateState.idle, UpdateState.idle)
        XCTAssertEqual(UpdateState.checking, UpdateState.checking)
        XCTAssertEqual(UpdateState.installing(release), UpdateState.installing(release))
        XCTAssertNotEqual(UpdateState.downloading(release), UpdateState.installing(release))
    }

    func testQuizProgressTracksAnswersAndReveals() {
        var progress = QuizProgress()
        progress.markQuestion(2, correct: true)
        progress.markQuestion(4, correct: false)
        progress.setQuestionRevealed(2, revealed: true)
        progress.setFlashcardRevealed(1, revealed: true)

        XCTAssertEqual(progress.answeredQuestionCount, 2)
        XCTAssertEqual(progress.answeredCorrectly, [2])
        XCTAssertEqual(progress.needsReview, [4])
        XCTAssertEqual(progress.revealedQuestions, [2])
        XCTAssertEqual(progress.revealedFlashcards, [1])
    }

    func testUpdaterScriptContainsCriticalOperations() {
        let script = UpdateService.updaterScriptContent
        XCTAssertTrue(script.contains("kill -0 \"$PID\""))
        XCTAssertTrue(script.contains("ditto \"$STAGE_APP\" \"$TARGET_APP\""))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("open \"$TARGET_APP\""))
    }

    func testUpdateChannelsHaveStableAndBetaOptions() {
        XCTAssertEqual(UpdateChannel.allCases, [.stable, .beta])
        XCTAssertTrue(UpdateChannel.stable.description.contains("prerelease"))
        XCTAssertTrue(UpdateChannel.beta.description.contains("alpha"))
    }

    func testProviderPresetsIncludeRequestedServices() {
        let ids = Set(ProviderPreset.allCases.map(\.rawValue))
        XCTAssertTrue(ids.isSuperset(of: ["gemini", "openai", "anthropic", "xai", "openrouter", "custom-openai-compatible"]))
        XCTAssertEqual(ProviderPreset.openAI.transport, .openAICompatible)
        XCTAssertEqual(ProviderPreset.anthropic.transport, .anthropic)
        XCTAssertEqual(ProviderPreset.gemini.transport, .gemini)
    }
}
