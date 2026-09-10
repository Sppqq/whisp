import XCTest
@testable import Whisp

final class GeminiModelFallbackTests: XCTestCase {
    func testDefaultAnalysisModelChain() {
        XCTAssertEqual(GeminiAPIClient.defaultAnalysisModel, "gemini-3.8-flash")
        XCTAssertEqual(
            GeminiAPIClient.defaultAnalysisFallbackModels,
            ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite"]
        )
        XCTAssertEqual(GeminiAPIClient.modelFallbackFailureThreshold, 3)
    }

    func testWhispSettingsDefaultToGemini38ForNotes() {
        XCTAssertEqual(WhispSettings().analysisModel, GeminiAPIClient.defaultAnalysisModel)
    }
}
