import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct MobileRootView: View {
    @Environment(MobileAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showImporter = false
    @State private var showImportSetup = false
    @State private var importSetupAudioURLs: [URL] = []
    @State private var importSetupImageURLs: [URL] = []
    @State private var showSettings = false
    @State private var selectedTab = 0
    @State private var libraryPath: [UUID] = []
    @State private var subjectFilter = "Все"
    @State private var showFinishRecording = false
    @State private var pendingDelete: LectureSession?
    @State private var showDeleteConfirmation = false

    private var filteredSessions: [LectureSession] {
        model.visibleSessions.filter { subjectFilter == "Все" || $0.subject == subjectFilter }
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selectedTab) {
            NavigationStack {
                MobileTodayView { id in openLecture(id) }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Label("Настройки", systemImage: "gearshape") }
                    } }
            }
            .tabItem { Label("Сегодня", systemImage: "sun.max") }.tag(0)
            NavigationStack(path: $libraryPath) {
                List {
                    if filteredSessions.isEmpty {
                        ContentUnavailableView {
                            Label("Ничего не найдено", systemImage: "magnifyingglass")
                        } description: { Text("Измените запрос или выберите все предметы.") } actions: {
                            Button("Сбросить фильтры") { model.searchQuery = ""; subjectFilter = "Все" }
                        }.listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredSessions) { session in
                            NavigationLink(value: session.id) { LectureRow(session: session) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { pendingDelete = session; showDeleteConfirmation = true } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .overlay {
                    if model.sessions.isEmpty {
                        ContentUnavailableView {
                            Label("Ваша библиотека", systemImage: "books.vertical")
                        } description: { Text("Запишите первую лекцию или добавьте аудио и фотографии.") } actions: {
                            Button("Добавить лекцию") { selectedTab = 2 }.buttonStyle(.glassProminent)
                        }
                    }
                }
                .navigationTitle("Библиотека")
                .searchable(text: $model.searchQuery, prompt: "Предмет, название или текст")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Предмет", selection: $subjectFilter) {
                                Text("Все предметы").tag("Все")
                                ForEach(Array(Set(model.sessions.map(\.subject))).sorted(), id: \.self) { Text($0).tag($0) }
                            }
                        } label: { Label(subjectFilter == "Все" ? "Предметы" : subjectFilter, systemImage: "line.3.horizontal.decrease") }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { selectedTab = 2 } label: { Label("Новая лекция", systemImage: "plus") }
                        Button { showSettings = true } label: { Label("Настройки", systemImage: "gearshape") }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let session = model.sessions.first(where: { $0.id == id }) {
                        MobileLectureView(session: session)
                    } else { ContentUnavailableView("Лекция недоступна", systemImage: "doc.text") }
                }
            }
            .tabItem { Label("Библиотека", systemImage: "books.vertical") }.tag(1)
            NavigationStack {
                createLecture
                    .navigationTitle(model.isRecording ? "Запись" : "Новая лекция")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Label("Настройки", systemImage: "gearshape") }
                    } }
            }
            .tabItem { Label(model.isRecording ? "Запись идёт" : "Запись", systemImage: "mic") }.tag(2)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importSetupAudioURLs = urls.filter {
                    UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audio) == true
                }
                importSetupImageURLs = urls.filter {
                    UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
                }
                if importSetupAudioURLs.isEmpty && importSetupImageURLs.isEmpty {
                    model.errorMessage = "Выберите хотя бы одно аудио или фото."
                } else {
                    showImportSetup = true
                }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showImportSetup, onDismiss: {
            importSetupAudioURLs = []
            importSetupImageURLs = []
        }) {
            LectureImportSetupView(
                initialAudioURLs: importSetupAudioURLs,
                initialImageURLs: importSetupImageURLs
            ) { audioURLs, images, combineAudio in
                Task {
                    if audioURLs.isEmpty || combineAudio {
                        await model.importAudio(audioURLs, images: images)
                    } else {
                        for audioURL in audioURLs {
                            await model.importAudio([audioURL], images: images)
                        }
                    }
                    LectureImportStaging.cleanup(images)
                    if let id = model.selectedSessionID { openLecture(id) }
                }
            }
        }
        .sheet(isPresented: $showSettings) { MobileSettingsView() }
        .alert("Завершить запись?", isPresented: $showFinishRecording) {
            Button("Продолжить запись", role: .cancel) { }
            Button("Завершить") { Task { await model.finishRecording(); if let id = model.selectedSessionID { openLecture(id) } } }
        } message: { Text("Аудио сохранится, затем Whisp подготовит конспект.") }
        .alert("Удалить лекцию?", isPresented: $showDeleteConfirmation) {
            Button("Отмена", role: .cancel) { pendingDelete = nil }
            Button("Удалить", role: .destructive) {
                if let session = pendingDelete { Task { await model.delete(session) } }
                pendingDelete = nil
            }
        } message: { Text("Аудиозапись и материалы будут удалены с этого iPhone.") }
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: model.isProcessing)
    }

    private func openLecture(_ id: UUID) {
        model.selectedSessionID = id
        subjectFilter = "Все"
        selectedTab = 1
        libraryPath = [id]
    }

    private var createLecture: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.isRecording {
                    VStack(spacing: 20) {
                        Image(systemName: "waveform").font(.system(size: 56)).foregroundStyle(.red)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(WhispFormatting.timestamp(context.date.timeIntervalSince(model.selectedSession?.startedAt ?? context.date)))
                                .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                        }
                        Text("Идёт запись с микрофона").font(.headline)
                        Text("Можете открыть библиотеку — запись продолжится.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { showFinishRecording = true } label: {
                            Label("Завершить запись", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.glassProminent).tint(.red).controlSize(.large)
                    }
                    .frame(maxWidth: .infinity).padding(24)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                } else {
                    Text("Сохраните главное с лекции.")
                        .font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(.red)
                        Text("Записать сейчас").font(.title2.bold())
                        Text("Whisp сохранит аудио и подготовит конспект после записи.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button { Task { await model.startRecording() } } label: {
                            Label("Начать запись", systemImage: "record.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.glassProminent).tint(.red).controlSize(.large)
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "square.and.arrow.down").font(.largeTitle).foregroundStyle(.blue)
                        Text("Добавить файлы").font(.title2.bold())
                        Text("Аудиозаписи и до 10 фотографий. Можно добавить только фото.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button { showImporter = true } label: {
                            Label("Выбрать аудио и фото", systemImage: "folder").frame(maxWidth: .infinity)
                        }.buttonStyle(.glass).controlSize(.large)
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                }
            }
            .disabled(!model.isRecording && (model.isProcessing || model.isImporting))
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            Text(WhispFormatting.displayTitle(session.title))
                .font(.headline)
                .lineLimit(2)
            HStack {
                Label(session.subject, systemImage: "book.closed")
                Spacer()
                Text(WhispFormatting.lectureDate(session.startedAt ?? session.createdAt))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: LectureSection = .notebook
    @State private var showPhotoFileImporter = false
    @State private var selectedGalleryPhotos: [PhotosPickerItem] = []
    @State private var isLoadingGalleryPhotos = false
    @State private var showAttachments = false
    @State private var showEditor = false
    let session: LectureSession

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                    Text(WhispFormatting.displayTitle(session.title)).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Label(session.subject, systemImage: "book.closed.fill")
                        .foregroundStyle(.secondary)
                    Text(WhispFormatting.lectureDate(session.startedAt ?? session.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Label(WhispFormatting.durationDescription(session.duration), systemImage: "clock")
                    Spacer()
                    Text(session.status.title).font(.caption.weight(.medium))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))

                DisclosureGroup("Фото и материалы (\(session.attachedImagePaths.count))", isExpanded: $showAttachments) {
                    photoAttachments
                }
                .font(.callout)

                Picker("Представление", selection: Binding(
                    get: { section },
                    set: { value in withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { section = value } }
                )) {
                    ForEach(LectureSection.allCases) { item in
                        Text(item.title).tag(item)
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))

            }
            .padding()
            .padding(.bottom, 16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }

        .navigationTitle("Материалы")
        .sheet(isPresented: $showEditor) { MobileLectureEditor(session: session, section: section) }
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: section)
        .fileImporter(
            isPresented: $showPhotoFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task { await model.attachPhotos(urls, to: session.id) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: selectedGalleryPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await addGalleryPhotos(items) }
        }
        .safeAreaInset(edge: .bottom) {
            MobileLectureActionBar(session: session)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if section != .transcript {
                    Button("Редактировать", systemImage: "pencil") { showEditor = true }.disabled(model.isRecording || model.isProcessing)
                }
            }
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

    private var photoAttachments: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Фото лекции · \(session.attachedImagePaths.count)/10", systemImage: "photo.stack")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showPhotoFileImporter = true
                } label: {
                    Label("Файлы", systemImage: "folder")
                }
                .disabled(session.attachedImagePaths.count >= 10 || isLoadingGalleryPhotos || model.isProcessing || model.isImporting)

                PhotosPicker(
                    selection: $selectedGalleryPhotos,
                    maxSelectionCount: max(1, 10 - session.attachedImagePaths.count),
                    matching: .images
                ) {
                    Label("Галерея", systemImage: "photo.on.rectangle")
                }
                .disabled(session.attachedImagePaths.count >= 10 || isLoadingGalleryPhotos || model.isProcessing || model.isImporting)
            }
            ForEach(session.attachedImagePaths, id: \.self) { name in
                Label(name, systemImage: "photo")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            if isLoadingGalleryPhotos {
                ProgressView("Добавляем фото из галереи…")
                    .font(.caption)
            }
            if !session.attachedImagePaths.isEmpty {
                Text("Добавьте снимки, затем выберите «Обновить», чтобы создать конспект с их учётом.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
    }

    @MainActor
    private func addGalleryPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingGalleryPhotos = true
        defer {
            isLoadingGalleryPhotos = false
            selectedGalleryPhotos = []
        }
        var stagedURLs: [URL] = []
        do {
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                stagedURLs.append(try LectureImportStaging.writePhoto(data, filename: "Фото-\(UUID().uuidString).\(ext)"))
            }
            guard !stagedURLs.isEmpty else {
                model.errorMessage = "Не удалось прочитать фото из галереи."
                return
            }
            await model.attachPhotos(stagedURLs, to: session.id)
        } catch {
            model.errorMessage = error.localizedDescription
        }
        LectureImportStaging.cleanup(stagedURLs)
    }
}

private struct MobileLectureActionBar: View {
    @Environment(MobileAppModel.self) private var model
    let session: LectureSession

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button { Task { await model.regenerateAnalysis(for: session.id) } } label: {
                    Label("Обновить", systemImage: "sparkles")
                }
                .disabled(model.isProcessing || model.isImporting || (session.finalTranscript.isEmpty && session.attachedImagePaths.isEmpty))
                Button { Task { await model.sync(session) } } label: {
                    Label("Синхр.", systemImage: "icloud.and.arrow.up")
                }.disabled(model.isSyncingWebDAV || model.isProcessing || model.isImporting)
                Menu {
                    Button("Добавить задания в Напоминания", systemImage: "checklist") {
                        Task { await model.createReminders(for: session) }
                    }.disabled(model.isCreatingReminders || !session.createdReminderIDs.isEmpty || model.isProcessing || model.isImporting)
                } label: { Label("Ещё", systemImage: "ellipsis") }
            }
            .font(.callout).buttonStyle(.glass).controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .disabled(model.isRecording)
    }
}

private struct MobileLectureEditor: View {
    @Environment(MobileAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: LectureSession
    let section: LectureSection
    private let originalText: String
    @State private var text: String
    @State private var title: String
    @State private var subject: String
    @State private var saving = false

    init(session: LectureSession, section: LectureSection) {
        self.session = session; self.section = section
        _title = State(initialValue: session.title)
        _subject = State(initialValue: session.subject)
        let content: String
        switch section {
        case .notebook: content = session.studentNotesMarkdown
        case .analysis: content = session.notesMarkdown
        case .transcript: content = session.finalMarkdown.isEmpty ? session.rawMarkdown : session.finalMarkdown
        case .quiz: content = session.quizMarkdown
        }
        originalText = content
        _text = State(initialValue: content)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Сведения") {
                    TextField("Название", text: $title)
                    TextField("Предмет", text: $subject)
                }
                Section(section.title) {
                    TextEditor(text: $text).frame(minHeight: 340).font(.body)
                }
            }
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saving = true
                        Task {
                            if title != session.title || subject != session.subject {
                                await model.updateMetadata(sessionID: session.id, title: title, subject: subject)
                            }
                            if text != originalText {
                                await model.updateContent(sessionID: session.id, section: section, content: text)
                            }
                            saving = false
                            dismiss()
                        }
                    }.disabled(saving)
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }
}

enum LectureSection: String, CaseIterable, Identifiable {
    case notebook, analysis, transcript
    case quiz
    var id: Self { self }
    var title: String {
        switch self {
        case .notebook: "Конспект"
        case .analysis: "Подробно"
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
    var onOpenSession: (UUID) -> Void = { _ in }

    private var taskSessions: [LectureSession] {
        model.sessions.filter { !upcomingTasks(in: $0).isEmpty }
    }

    private func upcomingTasks(in session: LectureSession) -> [ReminderDraft] {
        (session.analysis?.reminders ?? []).filter { draft in
            guard !draft.isInClassAssessmentInstruction, !session.completedReminderIDs.contains(draft.id) else { return false }
            return ReminderService().resolvedDueDate(for: draft, subject: session.subject,
                after: session.startedAt ?? session.createdAt, schedule: model.settingsStore.settings.lessonSchedule)
                .map { $0 >= Calendar.current.startOfDay(for: Date()) } ?? false
        }
    }

    var body: some View {
        List {
            Section {
                Text(Date().formatted(Date.FormatStyle().weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                    .font(.callout).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if !model.sessions.isEmpty {
                Section("Продолжить изучение") {
                    ForEach(model.sessions.prefix(2)) { session in
                        Button { onOpenSession(session.id) } label: { LectureRow(session: session) }
                            .tint(.primary)
                    }
                }
            }
            Section("Задания из лекций") {
                if taskSessions.isEmpty {
                    Label("Нет невыполненных заданий", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    ForEach(taskSessions) { session in
                        ForEach(upcomingTasks(in: session)) { task in
                            Button { onOpenSession(session.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).font(.headline).foregroundStyle(.primary)
                                    Text(session.subject).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section("Ближайшие занятия") {
                let lessons = StudyDashboardPlanner.upcomingLessons(from: model.settingsStore.settings.lessonSchedule)
                if lessons.isEmpty {
                    Text("Добавьте расписание в настройках.").foregroundStyle(.secondary)
                } else {
                    ForEach(lessons.prefix(5)) { lesson in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lesson.entry.subject).font(.headline)
                                Text(lesson.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(lesson.date, style: .time).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("Пора повторить") {
                let due = StudyDashboardPlanner.reviewSessions(from: model.sessions)
                if due.isEmpty {
                    Label("На сегодня всё", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    ForEach(due) { session in
                        Button { onOpenSession(session.id) } label: {
                            Label(WhispFormatting.displayTitle(session.title), systemImage: "rectangle.stack")
                        }.tint(.primary)
                    }
                }
            }
        }
        .navigationTitle("Сегодня")
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
