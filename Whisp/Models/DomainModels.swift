import Foundation

enum LectureStatus: String, Codable, CaseIterable, Sendable {
    case draft, recording, paused, processing, awaitingBackfill, review, uploading, synced, failed

    var title: String {
        switch self {
        case .draft: "Черновик"
        case .recording: "Запись"
        case .paused: "Пауза"
        case .processing: "Обработка"
        case .awaitingBackfill: "Ожидает дорасшифровки Gemini"
        case .review: "Проверка"
        case .uploading: "Загрузка"
        case .synced: "Синхронизировано"
        case .failed: "Ошибка"
        }
    }
}

enum TranscriptSource: String, Codable, Sendable {
    case geminiLive, whisperFallback, geminiBackfill
}

enum FallbackReason: String, Codable, Sendable {
    case quota, region, websocket, proxy, timeout, authentication, network, unknown

    var title: String {
        switch self {
        case .quota: "исчерпана квота"
        case .region: "регион недоступен"
        case .websocket: "оборван WebSocket"
        case .proxy: "прокси недоступен"
        case .timeout: "тайм-аут"
        case .authentication: "ошибка авторизации"
        case .network: "нет сети"
        case .unknown: "неизвестная ошибка"
        }
    }
}

enum BackfillStatus: String, Codable, Sendable {
    case pending, checking, available, processing, needsReview, accepted, deferred, declined, failed
}

enum AudioSource: String, Codable, Sendable {
    case microphone, system
}

enum ServiceConnectionState: Equatable, Sendable {
    case unchecked
    case checking
    case available
    case unavailable(String)
    case local
    case disabled

    var isAvailable: Bool { self == .available || self == .local }
}

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    var id: UInt32
    var name: String
    var isDefault: Bool
}

struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var source: TranscriptSource
    var model: String
    var confidence: Double?
    var speaker: String?
    var audioSegmentID: UUID?
    var manuallyEdited = false
}

struct FallbackInterval: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval?
    var reason: FallbackReason
    var status: BackfillStatus = .pending
    var retryAfter: Date?
    var attempts = 0
    var candidateSegments: [TranscriptSegment] = []

    var isOpen: Bool { end == nil }
}

struct AudioChunk: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var source: AudioSource
    var start: TimeInterval
    var end: TimeInterval
    var relativePath: String
    var checksum: String?
}

struct PauseInterval: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var start: Date
    var end: Date?
}

struct AnalysisResult: Codable, Hashable, Sendable {
    var title: String
    var subject: String
    var confidence: Double
    var alternatives: [String]
    var summary: String
    var detailedNotes: String
    var studentNotebook: String = ""
    var tags: [String] = []
    var keyConcepts: [String] = []

    init(
        title: String,
        subject: String,
        confidence: Double,
        alternatives: [String],
        summary: String,
        detailedNotes: String,
        studentNotebook: String = "",
        tags: [String] = [],
        keyConcepts: [String] = []
    ) {
        self.title = title
        self.subject = subject
        self.confidence = confidence
        self.alternatives = alternatives
        self.summary = summary
        self.detailedNotes = detailedNotes
        self.studentNotebook = studentNotebook
        self.tags = tags
        self.keyConcepts = keyConcepts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.0
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detailedNotes = try container.decodeIfPresent(String.self, forKey: .detailedNotes) ?? ""
        studentNotebook = try container.decodeIfPresent(String.self, forKey: .studentNotebook) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        keyConcepts = try container.decodeIfPresent([String].self, forKey: .keyConcepts) ?? []
    }
}

struct LectureSession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var startedAt: Date?
    var endedAt: Date?
    var status: LectureStatus = .draft
    var title = "Новая лекция"
    var subject = "Не определено"
    var isPinned = false
    var captureSystemAudio = true
    var importedAudioPath: String?
    var rawTranscript: [TranscriptSegment] = []
    var finalTranscript: [TranscriptSegment] = []
    var fallbackIntervals: [FallbackInterval] = []
    var audioChunks: [AudioChunk] = []
    var pauses: [PauseInterval] = []
    var analysis: AnalysisResult?
    var rawMarkdown = ""
    var finalMarkdown = ""
    var notesMarkdown = ""
    var studentNotesMarkdown = ""
    var quizMarkdown = ""
    var lastError: String?
    var syncedAt: Date?
    var remotePath: String?
    var userEditedFinal = false
    var userEditedNotes = false
    var userEditedStudentNotes = false

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        status: LectureStatus = .draft,
        title: String = "Новая лекция",
        subject: String = "Не определено",
        isPinned: Bool = false,
        captureSystemAudio: Bool = true,
        importedAudioPath: String? = nil,
        rawTranscript: [TranscriptSegment] = [],
        finalTranscript: [TranscriptSegment] = [],
        fallbackIntervals: [FallbackInterval] = [],
        audioChunks: [AudioChunk] = [],
        pauses: [PauseInterval] = [],
        analysis: AnalysisResult? = nil,
        rawMarkdown: String = "",
        finalMarkdown: String = "",
        notesMarkdown: String = "",
        studentNotesMarkdown: String = "",
        quizMarkdown: String = "",
        lastError: String? = nil,
        syncedAt: Date? = nil,
        remotePath: String? = nil,
        userEditedFinal: Bool = false,
        userEditedNotes: Bool = false,
        userEditedStudentNotes: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.title = title
        self.subject = subject
        self.isPinned = isPinned
        self.captureSystemAudio = captureSystemAudio
        self.importedAudioPath = importedAudioPath
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.fallbackIntervals = fallbackIntervals
        self.audioChunks = audioChunks
        self.pauses = pauses
        self.analysis = analysis
        self.rawMarkdown = rawMarkdown
        self.finalMarkdown = finalMarkdown
        self.notesMarkdown = notesMarkdown
        self.studentNotesMarkdown = studentNotesMarkdown
        self.quizMarkdown = quizMarkdown
        self.lastError = lastError
        self.syncedAt = syncedAt
        self.remotePath = remotePath
        self.userEditedFinal = userEditedFinal
        self.userEditedNotes = userEditedNotes
        self.userEditedStudentNotes = userEditedStudentNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        status = try container.decodeIfPresent(LectureStatus.self, forKey: .status) ?? .draft
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Новая лекция"
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? "Не определено"
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        captureSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .captureSystemAudio) ?? true
        importedAudioPath = try container.decodeIfPresent(String.self, forKey: .importedAudioPath)
        rawTranscript = try container.decodeIfPresent([TranscriptSegment].self, forKey: .rawTranscript) ?? []
        finalTranscript = try container.decodeIfPresent([TranscriptSegment].self, forKey: .finalTranscript) ?? []
        fallbackIntervals = try container.decodeIfPresent([FallbackInterval].self, forKey: .fallbackIntervals) ?? []
        audioChunks = try container.decodeIfPresent([AudioChunk].self, forKey: .audioChunks) ?? []
        pauses = try container.decodeIfPresent([PauseInterval].self, forKey: .pauses) ?? []
        analysis = try container.decodeIfPresent(AnalysisResult.self, forKey: .analysis)
        rawMarkdown = try container.decodeIfPresent(String.self, forKey: .rawMarkdown) ?? ""
        finalMarkdown = try container.decodeIfPresent(String.self, forKey: .finalMarkdown) ?? ""
        notesMarkdown = try container.decodeIfPresent(String.self, forKey: .notesMarkdown) ?? ""
        studentNotesMarkdown = try container.decodeIfPresent(String.self, forKey: .studentNotesMarkdown) ?? ""
        quizMarkdown = try container.decodeIfPresent(String.self, forKey: .quizMarkdown) ?? ""
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        syncedAt = try container.decodeIfPresent(Date.self, forKey: .syncedAt)
        remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath)
        userEditedFinal = try container.decodeIfPresent(Bool.self, forKey: .userEditedFinal) ?? false
        userEditedNotes = try container.decodeIfPresent(Bool.self, forKey: .userEditedNotes) ?? false
        userEditedStudentNotes = try container.decodeIfPresent(Bool.self, forKey: .userEditedStudentNotes) ?? false
    }

    var duration: TimeInterval {
        guard let start = startedAt else { return 0 }
        let finish = endedAt ?? Date()
        let paused = pauses.reduce(0.0) { total, pause in
            total + (pause.end ?? finish).timeIntervalSince(pause.start)
        }
        return max(0, finish.timeIntervalSince(start) - paused)
    }

    var hasPendingBackfill: Bool {
        fallbackIntervals.contains { ![.accepted, .declined].contains($0.status) }
    }
}

struct SubjectItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var isEnabled = true
    var order: Int
}

struct ProxyConfiguration: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case socks5, http }
    var kind: Kind = .socks5
    var host = ""
    var port = 0
    var username = ""
    var password = ""
    var isEnabled = false
}

enum GeminiKeyStatus: Codable, Equatable, Sendable {
    case unchecked
    case checking
    case valid
    case quotaExceeded(message: String)
    case invalid(message: String)

    var label: String {
        switch self {
        case .unchecked: "Не проверен"
        case .checking: "Проверка..."
        case .valid: "Работает"
        case .quotaExceeded: "Лимит квоты"
        case .invalid: "Недействителен"
        }
    }
}

struct WebDAVConfiguration: Codable, Hashable, Sendable {
    var baseURL = ""
    var rootFolder = ""
    var username = ""
    var password = ""
}

/// A Gemini-compatible endpoint. The API key is deliberately kept in `KeychainStore`,
/// not in this public, UserDefaults-backed configuration.
struct CustomProvider: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var baseURL: String
    var transcriptionModel: String
    var analysisModel: String

    init(
        id: UUID = UUID(),
        name: String = "Свой провайдер",
        baseURL: String = "",
        transcriptionModel: String = "gemini-3.5-transcribe",
        analysisModel: String = "gemini-3.8-flash"
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.transcriptionModel = transcriptionModel
        self.analysisModel = analysisModel
    }

    var endpoint: URL? {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }
}

struct WhispSettings: Codable, Sendable {
    var subjects = WhispSettings.defaultSubjects
    var customVocabulary: [String] = ["10.02.05", "информационная безопасность"]
    var localRetentionDays = 30
    var geminiModel = "gemini-3.5-transcribe"
    var geminiLiveModel = "gemini-3.5-transcribe-live"
    var analysisModel = "gemini-3.8-flash"
    /// `gemini` is the built-in provider and intentionally remains the default.
    var activeProviderID = "gemini"
    var hotkeyRecord = "⌥⌘R"
    var hotkeyFinish = "⌥⌘."
    var preferredMicrophoneID: UInt32?

    private enum CodingKeys: String, CodingKey {
        case subjects, customVocabulary, localRetentionDays, geminiModel, geminiLiveModel, analysisModel
        case activeProviderID, hotkeyRecord, hotkeyFinish, preferredMicrophoneID
    }

    init() {}

    /// Older installations do not contain `activeProviderID`; decode every setting
    /// defensively so adding a provider never resets existing user preferences.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        subjects = try values.decodeIfPresent([SubjectItem].self, forKey: .subjects) ?? Self.defaultSubjects
        customVocabulary = try values.decodeIfPresent([String].self, forKey: .customVocabulary) ?? ["10.02.05", "информационная безопасность"]
        localRetentionDays = try values.decodeIfPresent(Int.self, forKey: .localRetentionDays) ?? 30
        geminiModel = try values.decodeIfPresent(String.self, forKey: .geminiModel) ?? "gemini-3.5-transcribe"
        geminiLiveModel = try values.decodeIfPresent(String.self, forKey: .geminiLiveModel) ?? "gemini-3.5-transcribe-live"
        analysisModel = try values.decodeIfPresent(String.self, forKey: .analysisModel) ?? "gemini-3.8-flash"
        activeProviderID = try values.decodeIfPresent(String.self, forKey: .activeProviderID) ?? "gemini"
        hotkeyRecord = try values.decodeIfPresent(String.self, forKey: .hotkeyRecord) ?? "⌥⌘R"
        hotkeyFinish = try values.decodeIfPresent(String.self, forKey: .hotkeyFinish) ?? "⌥⌘."
        preferredMicrophoneID = try values.decodeIfPresent(UInt32.self, forKey: .preferredMicrophoneID)
    }

    static let defaultSubjects = [
        "Биология", "Иностранный язык", "Информатика", "История", "Литература",
        "Математика", "Обществознание", "Основы безопасности и защиты Родины",
        "Русский язык", "Физика", "Физическая культура", "Химия"
    ].enumerated().map { SubjectItem(name: $0.element, order: $0.offset) }
}
