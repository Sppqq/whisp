import SwiftUI

struct LibrarySidebar: View {
    @Bindable var model: AppModel

    @State private var searchText = ""
    @State private var selectedSubject = "Все"
    @State private var matchingSessionIDs: Set<UUID> = []

    private var filteredSessions: [LectureSession] {
        let subjectFiltered = model.sessions.filter { session in
            selectedSubject == "Все" || session.subject == selectedSubject
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return subjectFiltered }
        return subjectFiltered.filter { matchingSessionIDs.contains($0.id) }
    }

    private var searchTaskID: String {
        "\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))|\(selectedSubject)|\(model.librarySearchVersion)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            subjectFilters

            if model.isRestoringFromWebDAV {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WhispPalette.accent.opacity(0.12))
            }

            List(selection: $model.selectedSessionID) {
                Section("Недавние (\(filteredSessions.count))") {
                    if filteredSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredSessions) { session in
                            LectureRow(session: session, query: searchText)
                                .tag(session.id)
                                .contextMenu {
                                    Button {
                                        Task { await model.regenerateAnalysis(for: session.id, forceOverwriteNotes: true) }
                                    } label: {
                                        Label("Перегенерировать конспект", systemImage: "sparkles")
                                    }
                                    Button {
                                        model.revealInFinder(sessionID: session.id)
                                    } label: {
                                        Label("Показать в Finder", systemImage: "folder")
                                    }
                                    Button {
                                        model.openInObsidian(session: session)
                                    } label: {
                                        Label("Открыть в Obsidian", systemImage: "arrow.up.forward.app")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        model.deleteSession(session.id)
                                    } label: {
                                        Label("Удалить запись", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .disabled(model.isRecording)
            .onChange(of: model.selectedSessionID) { _, id in model.selectSession(id) }

            Divider().opacity(0.55)
            HStack {
                SettingsLink {
                    Label("Настройки", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("⌘,").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
        }
        .background(WhispPalette.sidebar)
        .task(id: searchTaskID) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                matchingSessionIDs = Set(model.sessions.map(\.id))
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            matchingSessionIDs = model.matchingSessionIDs(for: query)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(WhispPalette.accent)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Whisp")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("лекции и конспекты")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Button {
                    Task { await model.restoreFromWebDAV() }
                } label: {
                    Label("Загрузить лекции из WebDAV...", systemImage: "icloud.and.arrow.down")
                }
                .disabled(model.isBusy)

                Button {
                    model.showBatchRegenerateSheet = true
                } label: {
                    Label("Перегенерировать все конспекты...", systemImage: "sparkles.rectangle.stack")
                }
                .disabled(model.isBusy)

                Divider()

                Button {
                    model.revealInFinder()
                } label: {
                    Label("Показать папки в Finder", systemImage: "folder")
                }

                Button {
                    model.openInObsidian()
                } label: {
                    Label("Открыть в Obsidian", systemImage: "arrow.up.forward.app")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(WhispPalette.quietFill, in: RoundedRectangle(cornerRadius: 7))
            .help("Действия с лекциями")

            Button { model.showStartScreen() } label: {
                Image(systemName: "plus").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(WhispPalette.quietFill, in: RoundedRectangle(cornerRadius: 7))
            .help("Новая лекция или импорт")
            .accessibilityLabel("Новая лекция или импорт")
            .disabled(model.isRecording)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Название, предмет, тег или текст", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
                .accessibilityLabel("Поиск по библиотеке")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(WhispPalette.quietFill, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WhispPalette.hairline, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var subjectFilters: some View {
        let subjects = ["Все"] + Array(Set(model.sessions.map(\.subject).filter { $0 != "Не определено" && !$0.isEmpty })).sorted()
        if subjects.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(subjects, id: \.self) { subject in
                        Button { selectedSubject = subject } label: {
                            Text(subject)
                                .font(.caption2.weight(selectedSubject == subject ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(selectedSubject == subject ? WhispPalette.accent.opacity(0.15) : WhispPalette.quietFill, in: Capsule())
                                .foregroundStyle(selectedSubject == subject ? WhispPalette.accent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.sessions.isEmpty ? "Нет сохранённых лекций" : "Нет подходящих лекций")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !model.sessions.isEmpty {
                Button("Сбросить фильтры") {
                    searchText = ""
                    selectedSubject = "Все"
                }
                .buttonStyle(.bordered)
            }

            if model.sessions.isEmpty {
                Button {
                    Task { await model.restoreFromWebDAV() }
                } label: {
                    Label(model.isRestoringFromWebDAV ? "Загрузка..." : "Загрузить из WebDAV", systemImage: "icloud.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isBusy)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct LectureRow: View {
    let session: LectureSession
    var query = ""

    private var statusColor: Color {
        switch session.status {
        case .synced: .green
        case .failed: .red
        case .awaitingBackfill: .orange
        default: WhispPalette.accent
        }
    }

    private var hasManualEdits: Bool {
        session.userEditedFinal || session.userEditedNotes || session.userEditedStudentNotes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(session.title).font(.callout.weight(.semibold)).lineLimit(2)
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(session.subject).foregroundStyle(.secondary).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(session.status.title).foregroundStyle(.secondary).lineLimit(1)
                if !session.fallbackIntervals.isEmpty {
                    Image(systemName: "cpu")
                        .foregroundStyle(session.hasPendingBackfill ? .orange : .secondary)
                        .help(session.hasPendingBackfill ? "Нужна проверка локальной части" : "Локальная часть расшифровки")
                }
                if hasManualEdits {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(WhispPalette.accent)
                        .help("Есть ручные правки")
                }
                Spacer(minLength: 4)
                Text(session.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            if let snippet = matchingSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
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
