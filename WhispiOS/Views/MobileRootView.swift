import SwiftUI
import UniformTypeIdentifiers

struct MobileRootView: View {
    @Environment(MobileAppModel.self) private var model
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showToday = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedSessionID) {
                if model.visibleSessions.isEmpty {
                    ContentUnavailableView(
                        "Пока нет лекций",
                        systemImage: "waveform",
                        description: Text("Запишите лекцию или импортируйте аудиофайл.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(model.visibleSessions) { session in
                        NavigationLink(value: session.id) {
                            LectureRow(session: session)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.delete(session) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Whisp")
            .searchable(text: $model.searchQuery, prompt: "Лекции, предметы, текст")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showToday = true } label: {
                        Label("Сегодня", systemImage: "calendar.badge.clock")
                    }
                    Button { showImporter = true } label: {
                        Label("Импорт", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.isRecording || model.isProcessing)
                    recordButton
                }
            }
        } detail: {
            if let session = model.selectedSession {
                MobileLectureView(session: session)
            } else {
                ContentUnavailableView("Выберите лекцию", systemImage: "doc.text.magnifyingglass")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await model.importAudio(url) } }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showSettings) { MobileSettingsView() }
        .sheet(isPresented: $showToday) { MobileTodayView() }
        .alert("Whisp", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            if model.isProcessing || model.isImporting {
                MobileProcessingBanner(
                    message: model.processingProgress.isEmpty ? "Обрабатываем…" : model.processingProgress,
                    provider: model.activeProviderName
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: model.isProcessing)
    }

    private var recordButton: some View {
        Button {
            Task {
                if model.isRecording { await model.finishRecording() }
                else { await model.startRecording() }
            }
        } label: {
            Label(
                model.isRecording ? "Завершить" : "Записать",
                systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
            )
            .foregroundStyle(model.isRecording ? .red : .primary)
        }
        .disabled(model.isProcessing)
    }
}

private struct MobileProcessingBanner: View {
    let message: String
    let provider: String
    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isBreathing ? 1.08 : 0.92)
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, options: .repeating)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(message.isEmpty ? "Обрабатываем…" : message)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .contentTransition(.interpolate)
                Text("AI · \(provider)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .animation(.easeInOut(duration: 0.24), value: message)
    }
}

private struct LectureRow: View {
    let session: LectureSession

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.title)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Label(session.subject, systemImage: "book.closed")
                Spacer()
                Text(session.createdAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if session.status != .review && session.status != .synced {
                Label(session.status.title, systemImage: statusIcon)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch session.status {
        case .recording: "waveform"
        case .processing: "sparkles"
        case .failed: "exclamationmark.triangle"
        default: "clock"
        }
    }

    private var statusColor: Color { session.status == .failed ? .red : .orange }
}

struct MobileLectureView: View {
    @Environment(MobileAppModel.self) private var model
    @State private var section: LectureSection = .notebook
    let session: LectureSession

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                    Text(session.title).font(.title2.weight(.bold)).lineLimit(2)
                    Label(session.subject, systemImage: "book.closed.fill")
                        .foregroundStyle(.secondary)
                    Text(session.createdAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Label(WhispFormatting.durationDescription(session.duration), systemImage: "clock")
                    Label("\(session.finalTranscript.count) фрагм.", systemImage: "text.quote")
                    Spacer()
                    Text(session.status.title).font(.caption.weight(.medium))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))

                Picker("Представление", selection: Binding(
                    get: { section },
                    set: { value in withAnimation(.snappy(duration: 0.28)) { section = value } }
                )) {
                    ForEach(LectureSection.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if let error = session.lastError, session.status == .failed {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        if session.importedAudioPath != nil {
                            Button("Повторить обработку") {
                                Task { await model.retry(session) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isProcessing)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: .rect(cornerRadius: 14))
                }

                Group {
                    if section == .quiz, !session.quizMarkdown.isEmpty {
                        MobileQuizView(session: session)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if section == .quiz, session.quizMarkdown.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Подготовка к зачёту", systemImage: "sparkles")
                                        .font(.headline)
                                    Text("Составим вопросы по этой лекции через выбранный AI‑провайдер.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        Task { await model.generateQuiz(for: session.id) }
                                    } label: {
                                        Label("Создать вопросы", systemImage: "sparkles")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(model.isProcessing)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.thinMaterial, in: .rect(cornerRadius: 16))
                            }
                            MobileMarkdownView(markdown: content)
                                .textSelection(.enabled)
                        }
                    }
                }
                .id(section)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

            }
            .padding()
            .padding(.bottom, 120)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .safeAreaPadding(.bottom, 96)
        .navigationTitle("Лекция")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.28), value: section)
        .safeAreaInset(edge: .bottom) {
            MobileLectureActionBar(session: session)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: content, subject: Text(session.title)) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var content: String {
        switch section {
        case .notebook:
            session.studentNotesMarkdown.nonEmpty ?? session.analysis?.studentNotebook.nonEmpty ?? "Конспект ещё не создан."
        case .analysis:
            session.notesMarkdown.nonEmpty ?? session.analysis?.detailedNotes.nonEmpty ?? "Разбор ещё не создан."
        case .transcript:
            session.finalMarkdown.nonEmpty ?? session.finalTranscript.map(\.text).joined(separator: "\n\n").nonEmpty ?? "Стенограмма ещё не создана."
        case .quiz:
            session.quizMarkdown.nonEmpty ?? "Вопросы к зачёту ещё не созданы."
        }
    }
}

private struct MobileLectureActionBar: View {
    @Environment(MobileAppModel.self) private var model
    let session: LectureSession

    var body: some View {
        HStack(spacing: 0) {
            iconButton("arrow.triangle.2.circlepath", accessibilityLabel: "Синхронизировать с WebDAV") {
                Task { await model.sync(session) }
            }
            Divider()
                .frame(height: 24)
                .opacity(0.45)
            iconButton("checklist", accessibilityLabel: "Добавить задания в Reminders") {
                Task { await model.createReminders(for: session) }
            }
        }
        .padding(6)
        .background(.black.opacity(0.58), in: .capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(width: 108, height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.25), value: session.id)
    }

    private func iconButton(_ icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .accessibilityLabel(accessibilityLabel)
        .contentTransition(.symbolEffect(.replace))
    }
}

enum LectureSection: String, CaseIterable, Identifiable {
    case notebook, analysis, transcript
    case quiz
    var id: Self { self }
    var title: String {
        switch self {
        case .notebook: "Тетрадь"
        case .analysis: "Разбор"
        case .transcript: "Текст"
        case .quiz: "К зачёту"
        }
    }
    var icon: String {
        switch self {
        case .notebook: "pencil.and.scribble"
        case .analysis: "sparkles"
        case .transcript: "text.quote"
        case .quiz: "questionmark.bubble"
        }
    }
}

struct MobileSettingsView: View {
    @Environment(MobileAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newGeminiKey = ""
    @State private var geminiKeys: [String] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Провайдер AI") {
                    Picker("Провайдер", selection: Binding(
                        get: { model.settingsStore.settings.activeProviderID },
                        set: {
                            var settings = model.settingsStore.settings
                            settings.activeProviderID = $0
                            model.settingsStore.settings = settings
                        }
                    )) {
                        ForEach(ProviderPreset.allCases) { provider in
                            Label(provider.title, systemImage: provider.icon).tag(provider.rawValue)
                        }
                    }
                    if !model.settingsStore.usesGemini {
                        SecureField("API key", text: Binding(
                        get: { model.settingsStore.activeProviderAPIKeys.first ?? "" },
                        set: {
                            if model.settingsStore.usesGemini {
                                model.settingsStore.geminiAPIKey = $0
                            } else {
                                try? model.settingsStore.saveProviderAPIKeys([model.settingsStore.settings.activeProviderID: $0])
                            }
                        }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    Text(model.settingsStore.activeProviderRequiresAPIKey
                         ? "Ключ хранится в системной Связке ключей этого устройства."
                         : "Этот провайдер может работать без ключа (например, локальный Ollama).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.settingsStore.activeProviderPreset != .gemini {
                        let configuration = model.settingsStore.activeProviderPreset.map { model.settingsStore.configuration(for: $0) }
                        TextField("Адрес endpoint", text: Binding(
                            get: { configuration?.baseURL ?? "" },
                            set: { value in
                                guard let preset = model.settingsStore.activeProviderPreset else { return }
                                var updated = model.settingsStore.configuration(for: preset)
                                updated.baseURL = value
                                model.settingsStore.setConfiguration(updated, for: preset)
                            }
                        ))
                        .keyboardType(.URL)
                        TextField("Модель конспекта", text: Binding(
                            get: { configuration?.analysisModel ?? "" },
                            set: { value in
                                guard let preset = model.settingsStore.activeProviderPreset else { return }
                                var updated = model.settingsStore.configuration(for: preset)
                                updated.analysisModel = value
                                model.settingsStore.setConfiguration(updated, for: preset)
                            }
                        ))
                    }
                    Button {
                        Task { await model.checkProvider() }
                    } label: {
                        if model.isCheckingProvider {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Проверяем…")
                            }
                        } else {
                            Label("Проверить подключение", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(model.isCheckingProvider)
                    .animation(.snappy(duration: 0.2), value: model.isCheckingProvider)
                    if !model.providerStatus.isEmpty {
                        Label(model.providerStatus,
                              systemImage: model.providerStatus.hasPrefix("Ошибка") ? "xmark.circle" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(model.providerStatus.hasPrefix("Ошибка") ? .red : .secondary)
                    }
                }
                if model.settingsStore.usesGemini {
                    Section("Ключи Gemini") {
                        if geminiKeys.isEmpty {
                            Text("Добавьте первый ключ через поле ниже.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(geminiKeys.indices), id: \.self) { index in
                                HStack(spacing: 8) {
                                    SecureField("Ключ #\(index + 1)", text: Binding(
                                        get: { geminiKeys.indices.contains(index) ? geminiKeys[index] : "" },
                                        set: {
                                            guard geminiKeys.indices.contains(index) else { return }
                                            geminiKeys[index] = $0
                                            model.saveGeminiKeys(geminiKeys)
                                        }
                                    ))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    Button(role: .destructive) {
                                        guard geminiKeys.indices.contains(index) else { return }
                                        geminiKeys.remove(at: index)
                                        model.saveGeminiKeys(geminiKeys)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .accessibilityLabel("Удалить ключ")
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            SecureField("Новый ключ", text: $newGeminiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                let value = newGeminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !value.isEmpty else { return }
                                geminiKeys.append(value)
                                model.saveGeminiKeys(geminiKeys)
                                newGeminiKey = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .accessibilityLabel("Добавить ключ")
                        }
                    }
                }
                Section("Оформление") {
                    Picker("Тема", selection: $model.appearance) {
                        ForEach(WhispAppearance.allCases) { appearance in
                            Label(appearance.title, systemImage: appearance.icon).tag(appearance)
                        }
                    }
                    Picker("Расшифровка", selection: $model.transcriptionMode) {
                        ForEach(MobileTranscriptionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("Режим «Авто» использует WhisperKit только при сбое облака. Режим «Только локальный» не обращается к сети и может скачать модель при первом запуске.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("WebDAV / Obsidian") {
                    TextField("https://cloud.example/dav", text: $model.settingsStore.webDAV.baseURL)
                        .keyboardType(.URL)
                    TextField("Папка", text: $model.settingsStore.webDAV.rootFolder)
                    TextField("Пользователь", text: $model.settingsStore.webDAV.username)
                    SecureField("Пароль", text: $model.settingsStore.webDAV.password)
                    Button("Проверить подключение") { Task { await model.checkWebDAV() } }
                        .disabled(model.isCheckingWebDAV)
                    if !model.webDAVStatus.isEmpty {
                        Text(model.webDAVStatus)
                            .font(.caption)
                            .foregroundStyle(model.webDAVStatus.hasPrefix("Ошибка") ? .red : .secondary)
                    }
                    Button {
                        Task { await model.restoreFromWebDAV() }
                    } label: {
                        if model.isRestoringWebDAV {
                            Label("Загрузка…", systemImage: "arrow.down.circle")
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Загрузить библиотеку", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(model.isRestoringWebDAV)
                    .animation(.snappy(duration: 0.2), value: model.isRestoringWebDAV)
                }
                Section("Напоминания") {
                    Toggle("Создавать напоминания из заданий", isOn: Binding(
                        get: { model.settingsStore.settings.remindersEnabled },
                        set: {
                            var settings = model.settingsStore.settings
                            settings.remindersEnabled = $0
                            model.settingsStore.settings = settings
                        }
                    ))
                    Text("Сроки планируются накануне занятия в 19:00 по расписанию ниже.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.reminderAccessGranted {
                        Label("Доступ к Reminders разрешён", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Запросить доступ к Reminders") { Task { await model.requestReminderAccess() } }
                        if !model.reminderAccessStatus.isEmpty {
                            Text(model.reminderAccessStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(model.settingsStore.settings.lessonSchedule) { entry in
                        HStack {
                            TextField("Предмет", text: Binding(
                                get: { entry.subject },
                                set: { value in
                                    var settings = model.settingsStore.settings
                                    guard let index = settings.lessonSchedule.firstIndex(where: { $0.id == entry.id }) else { return }
                                    settings.lessonSchedule[index].subject = value
                                    model.settingsStore.settings = settings
                                }
                            ))
                            Text(entry.timeLabel)
                                .font(.caption.monospacedDigit())
                            Button(role: .destructive) { model.removeScheduleEntry(entry.id) } label: {
                                Image(systemName: "minus.circle")
                            }
                        }
                    }
                    Button { model.addScheduleEntry() } label: {
                        Label("Добавить занятие", systemImage: "plus")
                    }
                }
                Section {
                    Text("Системный звук, глобальные сочетания клавиш, меню-бар и DMG-обновления доступны только на Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .onAppear {
                geminiKeys = model.settingsStore.geminiAPIKeys
                model.refreshReminderAccess()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

struct MobileTodayView: View {
    @Environment(MobileAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Ближайшие занятия") {
                    let lessons = StudyDashboardPlanner.upcomingLessons(from: model.settingsStore.settings.lessonSchedule)
                    if lessons.isEmpty {
                        Text("Расписание пока не задано.").foregroundStyle(.secondary)
                    } else {
                        ForEach(lessons) { lesson in
                            VStack(alignment: .leading) {
                                Text(lesson.entry.subject).font(.headline)
                                Text(lesson.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(lesson.date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Повторение") {
                    let due = StudyDashboardPlanner.reviewSessions(from: model.sessions)
                    if due.isEmpty {
                        Label("Сегодня всё повторено", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(due) { session in
                            Label(session.title, systemImage: "rectangle.and.pencil.and.ellipsis")
                        }
                    }
                }
            }
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

private struct MobileQuizView: View {
    @Environment(MobileAppModel.self) private var model
    let session: LectureSession
    @State private var progress: QuizProgress
    @State private var revealed = Set<Int>()

    init(session: LectureSession) {
        self.session = session
        _progress = State(initialValue: session.quizProgress)
    }

    var body: some View {
        let items = Self.parseQuestions(session.quizMarkdown)
        VStack(alignment: .leading, spacing: 14) {
            Text("Отвечено: \(progress.answeredQuestionCount) из \(items.count)")
                .font(.headline)
            ForEach(items, id: \.id) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(item.id + 1). \(item.question)").font(.body.weight(.medium))
                    if revealed.contains(item.id) {
                        Text(item.answer.isEmpty ? "Ответ смотри в конспекте." : item.answer)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Знаю") { mark(item.id, correct: true) }
                                .buttonStyle(.borderedProminent)
                            Button("Повторить") { mark(item.id, correct: false) }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Button("Показать ответ") {
                            revealed.insert(item.id)
                            progress.setQuestionRevealed(item.id, revealed: true)
                            persist()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
            }
            if items.isEmpty {
                Text(session.quizMarkdown).textSelection(.enabled)
            }
        }
    }

    private func mark(_ id: Int, correct: Bool) {
        progress.markQuestion(id, correct: correct)
        persist()
    }

    private func persist() {
        Task { await model.updateQuizProgress(sessionID: session.id, progress: progress) }
    }

    private struct Item { let id: Int; let question: String; let answer: String }

    private static func parseQuestions(_ markdown: String) -> [Item] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [Item] = []
        var question = ""
        var answer: [String] = []
        func flush() {
            let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            result.append(Item(id: result.count, question: q, answer: answer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            question = ""; answer = []
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: "[!question]") {
                flush()
                question = String(trimmed[range.upperBound...])
                    .replacingOccurrences(of: "Вопрос:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if !question.isEmpty, trimmed.contains("[!success]") {
                continue
            } else if !question.isEmpty, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                answer.append(trimmed.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        return result
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
