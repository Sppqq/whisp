import SwiftUI

/// Content column: the lectures of the selected sidebar scope, searchable from the toolbar.
struct LibraryBrowser: View {
    @Bindable var model: AppModel
    @Binding var scope: LibraryScope?
    @State private var searchText = ""
    @State private var matchingIDs: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var sessionsToDelete: [UUID] = []
    /// Multiple selection (⌘-click, ⇧-click) for batch actions; a single
    /// selected lecture opens in the detail column.
    @State private var selection: Set<UUID> = []

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
            List(selection: $selection) {
                ForEach(sessions) { session in
                    LectureRow(
                        session: session,
                        query: searchText,
                        isSelected: selection.contains(session.id),
                        isQueuedForSync: model.isSyncQueued(for: session.id) && model.syncingSessionID != session.id,
                        isSyncing: model.syncingSessionID == session.id
                    )
                    .tag(session.id)
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first { model.selectSession(id) }
            }
            .onChange(of: selection) { _, ids in
                if ids.count == 1, let id = ids.first, !(model.showsLibrary && model.selectedSessionID == id) {
                    model.selectSession(id)
                }
            }
            .onChange(of: model.selectedSessionID, initial: true) { _, id in
                syncSelection(with: id)
            }
            .onChange(of: model.showsLibrary) { _, _ in
                syncSelection(with: model.selectedSessionID)
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
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Синхронизировать изменённые (\(model.unsyncedSessionIDs.count))") {
                        model.enqueueSync(model.unsyncedSessionIDs)
                    }
                    .disabled(model.unsyncedSessionIDs.isEmpty)
                    Button("Синхронизировать все лекции") {
                        model.enqueueSync(model.syncableSessionIDs)
                    }
                    .disabled(model.syncableSessionIDs.isEmpty)
                    if selection.count > 1 {
                        Divider()
                        Button("Синхронизировать выбранные (\(selection.count))") {
                            model.enqueueSync(orderedIDs(selection))
                        }
                    }
                } label: {
                    Label("Синхронизация", systemImage: "icloud.and.arrow.up")
                }
                .help("Добавить лекции в очередь синхронизации")
            }
        }
        .alert(sessionsToDelete.count > 1 ? "Удалить лекции (\(sessionsToDelete.count))?" : "Удалить лекцию?", isPresented: $showDeleteConfirmation) {
            Button("Отмена", role: .cancel) { sessionsToDelete = [] }
            Button("Удалить", role: .destructive) {
                sessionsToDelete.forEach(model.deleteSession)
                selection.subtract(sessionsToDelete)
                sessionsToDelete = []
            }
        } message: {
            Text(sessionsToDelete.count > 1
                 ? "Аудиозаписи и материалы выбранных лекций будут удалены с этого Mac."
                 : "Аудиозапись и материалы этой лекции будут удалены с этого Mac.")
        }
    }

    /// Selected IDs in the order they appear in the list.
    private func orderedIDs(_ ids: Set<UUID>) -> [UUID] {
        sessions.map(\.id).filter(ids.contains)
    }

    private func syncSelection(with id: UUID?) {
        guard model.showsLibrary, let id else {
            if selection.count <= 1 { selection = [] }
            return
        }
        if !selection.contains(id) || selection.count == 1 { selection = [id] }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        let ordered = orderedIDs(ids)
        if !ordered.isEmpty {
            let notQueued = ordered.filter { !model.isSyncQueued(for: $0) }
            Button(ordered.count > 1 ? "Синхронизировать (\(ordered.count))" : "Синхронизировать", systemImage: "icloud.and.arrow.up") {
                model.enqueueSync(ordered)
            }
            .disabled(notQueued.isEmpty)
            if ordered.contains(where: model.isSyncQueued(for:)) {
                Button("Убрать из очереди синхронизации", systemImage: "xmark.icloud") {
                    ordered.forEach(model.removeQueuedSync(for:))
                }
            }
            Button(ordered.count > 1 ? "Добавить конспекты в очередь (\(ordered.count))" : "Добавить конспект в очередь", systemImage: "sparkles") {
                ordered.forEach { model.enqueueAnalysis(for: $0) }
            }
            .disabled(ordered.allSatisfy(model.isAnalysisQueued(for:)))
            if ordered.count == 1, let session = model.sessions.first(where: { $0.id == ordered[0] }) {
                Divider()
                Button("Показать в Finder", systemImage: "folder") { model.revealInFinder(sessionID: session.id) }
                Button("Открыть в Obsidian", systemImage: "arrow.up.forward.app") { model.openInObsidian(session: session) }
            }
            Divider()
            Button(ordered.count > 1 ? "Удалить лекции (\(ordered.count))…" : "Удалить лекцию…", systemImage: "trash", role: .destructive) {
                sessionsToDelete = ordered
                showDeleteConfirmation = true
            }
        }
    }
}

private struct LectureRow: View {
    let session: LectureSession
    var query = ""
    var isSelected = false
    var isQueuedForSync = false
    var isSyncing = false

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
                Group {
                    if isSyncing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: isQueuedForSync ? "clock.arrow.circlepath" : session.cloudSyncIcon)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(secondaryColor)
                    }
                }
                .frame(width: 14)
                .accessibilityLabel(isSyncing ? "Синхронизируется" : isQueuedForSync ? "В очереди синхронизации" : session.cloudSyncTitle)
                .help(isSyncing ? "Синхронизируется" : isQueuedForSync ? "В очереди синхронизации" : cloudSyncDescription)
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
