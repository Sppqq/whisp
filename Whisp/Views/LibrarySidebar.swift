import SwiftUI

struct LibrarySidebar: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            todayButton
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
                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
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
            .onChange(of: model.selectedSessionID) { _, id in
                guard !(model.showsToday && id == nil) else { return }
                withAnimation(reduceMotion ? nil : WhispMotion.navigation) {
                    model.selectSession(id)
                }
            }
            .animation(reduceMotion ? nil : WhispMotion.content, value: filteredSessions.map(\.id))

            Divider().opacity(0.55)
            HStack {
                SettingsLink {
                    Label("Настройки", systemImage: "gearshape")
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(
                            .regular.interactive(),
                            in: .rect(cornerRadius: WhispMetrics.compactCornerRadius)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
                Text("⌘,").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
        }
        .background(.clear)
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: "Поиск лекций"
        )
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Label("Whisp", systemImage: "waveform")
                    .font(.headline.weight(.semibold))
                Text("Лекции и конспекты")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button { model.showStartScreen() } label: {
                WhispGlassIconActionLabel(systemImage: "plus", size: 30)
            }
            .buttonStyle(.plain)
            .help("Новая лекция или импорт")
            .accessibilityLabel("Новая лекция или импорт")
            .disabled(model.isRecording)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var todayButton: some View {
        Group {
            if model.showsToday {
                todayButtonLabel
                    .foregroundStyle(.primary)
                    .glassEffect(
                        .regular.tint(Color.primary.opacity(0.08)).interactive(),
                        in: .rect(cornerRadius: WhispMetrics.compactCornerRadius)
                    )
            } else {
                todayButtonLabel
                    .foregroundStyle(.primary)
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: WhispMetrics.compactCornerRadius)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var todayButtonLabel: some View {
        Button {
            withAnimation(reduceMotion ? nil : WhispMotion.navigation) {
                model.showTodayDashboard()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.primary)
                Text("Сегодня")
                    .font(.callout.weight(.semibold))
                Spacer()
                if todayBadgeCount > 0 {
                    Text("\(todayBadgeCount)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Color.primary.opacity(model.showsToday ? 0.12 : 0.07),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(.rect(cornerRadius: WhispMetrics.compactCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(model.isRecording)
        .accessibilityLabel(todayBadgeCount > 0 ? "Сегодня, \(todayBadgeCount) дел" : "Сегодня")
    }

    private var todayBadgeCount: Int {
        let reviewCount = StudyDashboardPlanner.reviewSessions(from: model.sessions).count
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let taskCount = model.sessions.reduce(0) { total, session in
            let active = (session.analysis?.reminders ?? []).filter { draft in
                guard !draft.isInClassAssessmentInstruction else { return false }
                guard !session.completedReminderIDs.contains(draft.id) else { return false }
                return model.reminderService.resolvedDueDate(
                    for: draft,
                    subject: session.subject,
                    after: session.startedAt ?? session.createdAt,
                    schedule: model.settingsStore.settings.lessonSchedule
                ).map { $0 >= startOfToday } ?? false
            }
            return total + active.count
        }
        return reviewCount + taskCount
    }

    @ViewBuilder
    private var subjectFilters: some View {
        let subjects = ["Все"] + Array(Set(model.sessions.map(\.subject).filter { $0 != "Не определено" && !$0.isEmpty })).sorted()
        if subjects.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                WhispGlassGroup {
                    HStack(spacing: 8) {
                        ForEach(subjects, id: \.self) { subject in
                            subjectFilterButton(subject)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                model.sessions.isEmpty ? "Нет сохранённых лекций" : "Нет подходящих лекций",
                systemImage: model.sessions.isEmpty ? "rectangle.stack" : "magnifyingglass"
            )
            .font(.callout.weight(.semibold))

            Text(model.sessions.isEmpty
                 ? "Начните новую запись или загрузите лекции из WebDAV."
                 : "Измените запрос или сбросьте фильтры, чтобы увидеть другие лекции.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.sessions.isEmpty {
                Button("Сбросить фильтры") {
                    searchText = ""
                    selectedSubject = "Все"
                }
                .buttonStyle(.plain)
                .foregroundStyle(WhispPalette.accent)
            }

            if model.sessions.isEmpty {
                Button {
                    Task { await model.restoreFromWebDAV() }
                } label: {
                    Label(model.isRestoringFromWebDAV ? "Загрузка..." : "Загрузить из WebDAV", systemImage: "icloud.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(model.isBusy)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .whispQuietSurface(cornerRadius: WhispMetrics.controlCornerRadius)
    }

    @ViewBuilder
    private func subjectFilterButton(_ subject: String) -> some View {
        if selectedSubject == subject {
            Button { selectSubject(subject) } label: {
                Text(subject)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassEffect(
                .regular.tint(Color.primary.opacity(0.08)).interactive(),
                in: .capsule
            )
        } else {
            Button { selectSubject(subject) } label: {
                Text(subject)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func selectSubject(_ subject: String) {
        withAnimation(reduceMotion ? nil : WhispMotion.control) {
            selectedSubject = subject
        }
    }
}

private struct LectureRow: View {
    let session: LectureSession
    var query = ""

    private var statusColor: Color {
        switch session.status {
        case .synced: WhispPalette.success
        case .failed: .red
        case .awaitingBackfill: WhispPalette.warning
        case .recording, .paused: WhispPalette.recording
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
                if session.status != .review {
                    Text("·").foregroundStyle(.tertiary)
                    Text(session.status.title).foregroundStyle(.secondary).lineLimit(1)
                }
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
