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

    func testCompletedEmptyInteractionIsAllowedAsSilentChunk() throws {
        let json = #"{"status":"completed","output_text":"","steps":[]}"#
        XCTAssertTrue(try GeminiTranscriptionPayload.parse(Data(json.utf8), model: "test").isEmpty)
    }

    func testTranscriptionResponseErrorsAreRetryable() {
        XCTAssertTrue(GeminiAPIError(
            code: -1,
            status: "TRANSCRIPTION",
            message: "empty",
            retryAfter: nil
        ).isRetryableTranscriptionResponse)
        XCTAssertFalse(GeminiAPIError(
            code: 401,
            status: "API_KEY",
            message: "invalid key",
            retryAfter: nil
        ).isRetryableTranscriptionResponse)
    }

    func testTimestampValidation() {
        XCTAssertEqual(GeminiTranscriptionPayload.seconds("1.250s"), 1.25)
        XCTAssertEqual(GeminiTranscriptionPayload.seconds(0.0), 0)
        for invalid in ["nan", "inf", "-1s", "hello"] {
            XCTAssertNil(GeminiTranscriptionPayload.seconds(invalid))
        }
    }
}


final class GeminiLectureTextPayloadTests: XCTestCase {
    func testLectureTextSurvivesSerializationWithAndWithoutPhotos() throws {
        let transcript = "[00:01] Преподаватель: Митоз — деление клетки.\n[00:12] Дочерние клетки сохраняют набор хромосом."
        for images in [[], [GeminiAPIClient.InputImage(mimeType: "image/jpeg", data: Data([1, 2, 3]))]] {
            let body = GeminiAPIClient.textInteractionRequest(prompt: transcript, model: "test", images: images)
            let data = try JSONSerialization.data(withJSONObject: body)
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let input = try XCTUnwrap(decoded["input"] as? [[String: Any]])
            XCTAssertEqual(input.count, 1)
            XCTAssertEqual(input[0]["type"] as? String, "user_input")
            let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
            XCTAssertEqual(content[0]["text"] as? String, transcript)
            XCTAssertEqual(content.count, 1 + images.count)
            XCTAssertEqual(decoded["store"] as? Bool, false)
        }
    }

    func testKeepsEveryTextBlockOfFinalModelOutput() throws {
        let json = ###"{"steps":[{"type":"model_output","content":[{"type":"text","text":"Промежуточный ответ"}]},{"type":"thought","content":[]},{"type":"model_output","content":[{"type":"text","text":"## Митоз"},{"type":"text","text":"Деление клетки."}]}]}"###
        let text = try GeminiAPIClient.extractText(Data(json.utf8), transport: .gemini)
        XCTAssertEqual(text, "## Митоз\nДеление клетки.")
    }
}
