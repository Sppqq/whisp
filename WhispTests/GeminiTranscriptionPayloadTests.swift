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


final class LectureInputRegressionTests: XCTestCase {
    func testSparseLongLectureIsNotSplitBySilentTime() {
        let segments = (0..<176).map { index in
            TranscriptSegment(start: Double(index * 28), end: Double(index * 28 + 1),
                text: "Короткая реплика урока", source: .geminiLive, model: "test")
        }
        let parts = LectureAnalysisService.partitionSegments(segments)
        XCTAssertEqual(parts.count, 1)
        XCTAssertTrue(parts[0].text.contains("[00:00]"))
        XCTAssertTrue(parts[0].text.contains(WhispFormatting.timestamp(segments.last!.start)))
    }

    func testTextRequestsAreNotAcceptedAsNotes() {
        XCTAssertTrue(LectureAnalysisService.isRetrievalPlaceholder("Кидай текст."))
        XCTAssertTrue(LectureAnalysisService.isRetrievalPlaceholder("Пришли текст лекции"))
        XCTAssertFalse(LectureAnalysisService.isRetrievalPlaceholder("## Лексика\nОбсуждали образ персонажа."))
    }
}


final class NoteGenerationQueueTests: XCTestCase {
    @MainActor
    func testQueuePreservesOrderDeduplicatesAndRemovesPendingJobs() {
        let model = AppModel()
        let segment = TranscriptSegment(start: 0, end: 1, text: "Учебный материал", source: .geminiLive, model: "test")
        let first = LectureSession(rawTranscript: [segment])
        let second = LectureSession(finalTranscript: [segment])
        let empty = LectureSession()
        model.sessions = [first, second, empty]
        model.enqueueAnalysis(for: first.id)
        model.enqueueAnalysis(for: second.id)
        model.enqueueAnalysis(for: first.id)
        model.enqueueAnalysis(for: empty.id)
        XCTAssertEqual(model.queuedAnalysisSessionIDs, [first.id, second.id])
        XCTAssertTrue(model.isAnalysisQueued(for: first.id))
        model.removeQueuedAnalysis(for: first.id)
        XCTAssertEqual(model.queuedAnalysisSessionIDs, [second.id])
        model.removeQueuedAnalysis(for: second.id)
        XCTAssertTrue(model.queuedAnalysisSessionIDs.isEmpty)
    }
}
