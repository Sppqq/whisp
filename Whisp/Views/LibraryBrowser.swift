import SwiftUI

/// Content column: the lectures of the selected sidebar scope, searchable from the toolbar.
struct LibraryBrowser: View {
    @Bindable var model: AppModel
    @Binding var scope: LibraryScope?
    @State private var searchText = ""
    @State private var matchingIDs: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: LectureSession?

    private var sessions: [LectureSession] {
        model.sessions.filter {
            (selectedSubject == nil || $0.subject == selectedSubject)
            && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || matchingIDs.contains($0.id))
        }
    }

    private var selectedSubject: String? {
        if case .subject(let subject) = scope { return subject }
        return nil
    }

    private var title: String {
        if case .today = scope { return "Недавние" }
        return selectedSubject ?? "Все лекции"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { model.showsLibrary ? model.selectedSessionID : nil }, set: { model.selectSession($0) })) {
                ForEach(sessions) { session in
                    LectureRow(session: session, query: searchText, isSelected: model.showsLibrary && model.selectedSessionID == session.id)
                        .tag(session.id)
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .contextMenu {
                            Button("Добавить конспект в очередь", systemImage: "sparkles") { model.enqueueAnalysis(for: session.id) }
                                .disabled(model.isAnalysisQueued(for: session.id))
                            Button("Показать в Finder", systemImage: "folder") { model.revealInFinder(sessionID: session.id) }
                            Button("Открыть в Obsidian", systemImage: "arrow.up.forward.app") { model.openInObsidian(session: session) }
                            Divider()
                            Button("Удалить лекцию…", systemImage: "trash", role: .destructive) {
                                sessionToDelete = session
                                showDeleteConfirmation = true
                            }
                        }
                }
            }
            .listStyle(.inset)
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "Пока нет лекций" : "Ничего не найдено", systemImage: "books.vertical")
                    } description: {
                        Text(searchText.isEmpty ? "Запишите лекцию или импортируйте аудио и фото." : "Попробуйте другое слово или выберите все предметы.")
                    } actions: {
                        Button(searchText.isEmpty ? "Новая лекция" : "Сбросить поиск") {
                            if searchText.isEmpty { model.showStartScreen() }
                            else { searchText = ""; scope = .all }
                        }.buttonStyle(WhispActionStyle())
                        if model.sessions.isEmpty {
                            Button("Загрузить из WebDAV") { Task { await model.restoreFromWebDAV() } }
                                .buttonStyle(WhispActionStyle()).disabled(model.isBusy)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("Лекций: \(sessions.count)")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Поиск по лекциям")
        .disabled(model.isRecording)
        .task(id: "\(searchText)|\(model.librarySearchVersion)") {
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard !Task.isCancelled else { return }
            matchingIDs = model.matchingSessionIDs(for: searchText)
        }
        .alert("Удалить лекцию?", isPresented: $showDeleteConfirmation) {
            Button("Отмена", role: .cancel) { sessionToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let session = sessionToDelete { model.deleteSession(session.id) }
                sessionToDelete = nil
            }
        } message: { Text("Аудиозапись и материалы этой лекции будут удалены с этого Mac.") }
    }
}

private struct LectureRow: View {
    let session: LectureSession
    var query = ""
    var isSelected = false

    private var secondaryColor: Color { isSelected ? .white.opacity(0.85) : .secondary }

    private var hasManualEdits: Bool {
        session.userEditedFinal || session.userEditedNotes || session.userEditedStudentNotes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(WhispFormatting.displayTitle(session.title)).font(.callout.weight(.medium)).lineLimit(2)
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                }
            }
            HStack(spacing: 5) {
                Text(session.subject).foregroundStyle(secondaryColor).lineLimit(1)
                if [.failed, .processing, .awaitingBackfill, .recording, .paused].contains(session.status) {
                    Text("·").foregroundStyle(secondaryColor)
                    Text(session.status.title).foregroundStyle(secondaryColor).lineLimit(1)
                }
                if !session.fallbackIntervals.isEmpty {
                    Image(systemName: "cpu")
                        .foregroundStyle(isSelected ? secondaryColor : (session.hasPendingBackfill ? .orange : .secondary))
                        .help(session.hasPendingBackfill ? "Нужна проверка локальной части" : "Локальная часть расшифровки")
                }
                if hasManualEdits {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(isSelected ? secondaryColor : WhispPalette.accent)
                        .help("Есть ручные правки")
                }
                Spacer(minLength: 4)
                Image(systemName: session.cloudSyncIcon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(secondaryColor)
                    .frame(width: 14)
                    .accessibilityLabel(session.cloudSyncTitle)
                    .help(cloudSyncDescription)
                Text(WhispFormatting.lectureDate(session.startedAt ?? session.createdAt))
                    .foregroundStyle(secondaryColor)
                    .fixedSize()
            }
            .font(.caption2)
            if let snippet = matchingSnippet, !snippet.isEmpty {
                Text(MarkdownDisplayFormatting.attributed(snippet.replacingOccurrences(of: #"^(?:#{1,6}|[-*])\s+"#, with: "", options: .regularExpression)))
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 2)
    }

    private var cloudSyncDescription: String {
        guard let date = session.syncedAt else { return session.cloudSyncTitle }
        return "\(session.cloudSyncTitle). Последняя успешная загрузка: \(date.formatted(date: .numeric, time: .shortened))"
    }

    private var matchingSnippet: String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }
        let transcript = session.finalTranscript + session.rawTranscript
        if let segment = transcript.first(where: { $0.text.localizedCaseInsensitiveContains(trimmedQuery) }) {
            return segment.text
        }
        let notes = [session.studentNotesMarkdown, session.notesMarkdown]
            .flatMap { $0.components(separatedBy: .newlines) }
            .first { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        if let notes { return notes }
        return [session.finalMarkdown, session.rawMarkdown, session.quizMarkdown]
            .flatMap { $0.components(separatedBy: .newlines) }
            .first { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }
}
