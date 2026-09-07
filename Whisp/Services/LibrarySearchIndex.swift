import Foundation

/// An in-memory full-text index for the lecture library.
///
/// The index is deliberately small and local: it keeps one normalized document
/// per session, so SwiftUI does not have to scan every transcript and Markdown
/// field while the user is typing in the library search field.
struct LibrarySearchIndex: Sendable {
    private var documents: [UUID: String] = [:]

    mutating func rebuild(sessions: [LectureSession]) {
        documents = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, Self.document(for: $0)) })
    }

    func matchingIDs(for query: String) -> Set<UUID> {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return Set(documents.keys) }

        return Set(documents.compactMap { id, document in
            document.contains(normalizedQuery) ? id : nil
        })
    }

    private static func document(for session: LectureSession) -> String {
        let transcript = (session.finalTranscript + session.rawTranscript).map { segment in
            [segment.speaker, segment.text].compactMap { $0 }.joined(separator: " ")
        }

        let analysis = session.analysis.map { result in
            [result.summary, result.detailedNotes, result.studentNotebook]
                + result.tags
                + result.keyConcepts
        } ?? []

        return normalize([
            session.title,
            session.subject,
            transcript.joined(separator: " "),
            analysis.joined(separator: " "),
            session.rawMarkdown,
            session.finalMarkdown,
            session.notesMarkdown,
            session.studentNotesMarkdown,
            session.quizMarkdown
        ].joined(separator: "\n"))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
