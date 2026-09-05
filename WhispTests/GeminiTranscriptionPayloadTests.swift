import XCTest
@testable import Whisp

final class GeminiTranscriptionPayloadTests: XCTestCase {
    func testTimedRequestNeverContainsVocabulary() throws {
        let body = GeminiTranscriptionPayload.request(model: "gemini-3.5-transcribe", audio: ["type": "audio", "uri": "test"])
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("custom_vocabulary"))
        XCTAssertTrue(json.contains("timestamp_granularities"))
        XCTAssertTrue(json.contains("diarization_mode"))
        XCTAssertEqual(body["store"] as? Bool, false)
    }

    func testParsesRESTWordAnnotationsInsteadOfConvenienceText() throws {
        let json = #"{"status":"completed","output_text":"Не использовать вместо таймкодов","steps":[{"type":"model_output","content":[{"type":"text","text":"Да да","annotations":[{"type":"word_info","text":"Да","speaker":"spk_1","start_offset":"0.100s","end_offset":"0.450s"},{"type":"word_info","text":"да","speaker":"spk_1","start_offset":"0.500s","end_offset":"0.850s"}]}]}]}"#
        let segments = try GeminiTranscriptionPayload.parse(Data(json.utf8), model: "test")
        XCTAssertEqual(segments.map(\.text), ["Да", "да"])
        XCTAssertEqual(segments.first?.start, 0.1)
        XCTAssertEqual(segments.last?.end, 0.85)
        XCTAssertEqual(segments.first?.speaker, "spk_1")
    }

    func testLegacyOutputAndTextFallback() throws {
        let legacy = #"{"outputs":[{"text":"Речь","start_time":1.5,"end_time":2.0}]}"#
        XCTAssertEqual(try GeminiTranscriptionPayload.parse(Data(legacy.utf8), model: "test").first?.start, 1.5)
        let text = #"{"output_text":"Речь без таймкодов"}"#
        XCTAssertEqual(try GeminiTranscriptionPayload.parse(Data(text.utf8), model: "test").count, 1)
    }

    func testMalformedAndFailedResponsesAreNotSuccessfulEmptyTranscripts() {
        for json in ["{}", "[]", "not json", #"{"status":"failed","output_text":"partial"}"#] {
            XCTAssertThrowsError(try GeminiTranscriptionPayload.parse(Data(json.utf8), model: "test"))
        }
    }

    func testSilentChunkIsAllowed() throws {
        let json = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":""}]}]}"#
        XCTAssertTrue(try GeminiTranscriptionPayload.parse(Data(json.utf8), model: "test").isEmpty)
    }

    func testTimestampValidation() {
        XCTAssertEqual(GeminiTranscriptionPayload.seconds("1.250s"), 1.25)
        XCTAssertEqual(GeminiTranscriptionPayload.seconds(0.0), 0)
        for invalid in ["nan", "inf", "-1s", "hello"] {
            XCTAssertNil(GeminiTranscriptionPayload.seconds(invalid))
        }
    }
}
