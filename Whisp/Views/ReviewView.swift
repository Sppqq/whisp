import SwiftUI
import UniformTypeIdentifiers

struct ReviewView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = "student"
    @State private var audioSource = AudioSource.microphone
    @State private var isPreviewMode = true
    @State private var quizViewMode = "interactive"
    @State private var transcriptFilter = ""
    @State private var editingSegment: TranscriptSegment?
    @State private var editingSegmentIsRaw = false
    @State private var showPhotoImporter = false
    @State private var showLectureDetails = false
    @State private var showStudyDetails = false
    var body: some View {
        VStack(spacing: 0) {
            if !isPreviewMode || !["student", "notes"].contains(tab) {
                readingChrome
            }

            Group {
                switch tab {
                case "student":
                    VStack(spacing: 0) {
                        if !model.isGeneratingNotes && (model.currentSession?.analysis == nil || (model.currentSession?.lastError != nil)) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(WhispPalette.accent)
                                Text(model.currentSession?.analysis == nil ? "Расшифровка сохранена. Можно создать только конспект." : "Можно перегенерировать конспект через новую модель.")
                                    .font(.caption)
                                Spacer()
                                Button("Создать только конспект") {
                                    Task { await model.regenerateAnalysis(forceOverwriteNotes: true) }
                                }
                                .buttonStyle(WhispActionStyle(prominent: true))
                                .controlSize(.small)
                            }
                            .padding(10)
                            .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                        }
                        if isPreviewMode {
                            MarkdownPreview(
                                markdown: currentContent,
                                showsDocumentTitle: false,
                                header: AnyView(readingChrome)
                            )
                        } else {
                            editor(binding: Binding(get: { model.currentSession?.studentNotesMarkdown ?? "" }, set: { model.updateReview(studentNotes: $0) }))
                        }
                    }
                case "notes":
                    VStack(spacing: 0) {
                        if !model.isGeneratingNotes && (model.currentSession?.analysis == nil || (model.currentSession?.lastError != nil)) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(WhispPalette.accent)
                                Text(model.currentSession?.analysis == nil ? "Расшифровка сохранена. Можно создать только конспект." : "Можно перегенерировать конспект через новую модель.")
                                    .font(.caption)
                                Spacer()
                                Button("Создать только конспект") {
                                    Task { await model.regenerateAnalysis(forceOverwriteNotes: true) }
                                }
                                .buttonStyle(WhispActionStyle(prominent: true))
                                .controlSize(.small)
                            }
                            .padding(10)
                            .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                        }
                        if isPreviewMode {
                            MarkdownPreview(
                                markdown: currentContent,
                                showsDocumentTitle: false,
                                header: AnyView(readingChrome)
                            )
                        } else {
                            editor(binding: Binding(get: { model.currentSession?.notesMarkdown ?? "" }, set: { model.updateReview(notes: $0) }))
                        }
                    }
                case "quiz":
                    VStack(spacing: 0) {
                        if (model.currentSession?.quizMarkdown ?? "").isEmpty {
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "graduationcap.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(WhispPalette.accent)
                                Text("Материалы к зачёту и экзамену")
                                    .font(.title2.bold())
                                Text("Нейросеть проанализирует лекцию и подготовит:\n• 5-7 контрольных вопросов со скрытыми ответами\n• 5 карточек-определений (флэшкарты)\n• Типичные ошибки и опасные места на экзамене")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                    .frame(maxWidth: 480)

                                if model.isGeneratingQuiz {
                                    ProgressView("Составляем вопросы к зачёту через Gemini...")
                                        .padding(.top, 10)
                                } else {
                                    Button {
                                        Task { await model.generateQuiz() }
                                    } label: {
                                        Label("Сгенерировать вопросы к зачёту", systemImage: "sparkles")
                                            .font(.headline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(WhispActionStyle(prominent: true))
                                    .controlSize(.large)
                                    .padding(.top, 10)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(WhispPalette.content)
                        } else {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Label("Материалы к зачёту готовы", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    WhispGlassSegment(
                                        selection: $quizViewMode,
                                        options: [
                                            ("interactive", "Тренажёр", "rectangle.stack"),
                                            ("markdown", "Markdown", "chevron.left.forwardslash.chevron.right")
                                        ],
                                        minHeight: 28
                                    )
                                    .frame(width: 260)

                                    Button {
                                        Task { await model.generateQuiz() }
                                    } label: {
                                        Label("Перегенерировать", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(WhispActionStyle())
                                    .controlSize(.small)
                                    .disabled(model.isGeneratingQuiz)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                                .frame(maxWidth: 860)
                                .padding(.horizontal, 32)
                                .frame(maxWidth: .infinity, alignment: .center)

                                if quizViewMode == "interactive" {
                                    InteractiveQuizView(
                                        markdown: model.currentSession?.quizMarkdown ?? "",
                                        progress: Binding(
                                            get: { model.currentSession?.quizProgress ?? QuizProgress() },
                                            set: { model.updateQuizProgress($0) }
                                        )
                                    )
                                } else {
                                    editor(binding: Binding(
                                        get: { model.currentSession?.quizMarkdown ?? "" },
                                        set: { model.updateReview(quiz: $0) }
                                    ))
                                }
                            }
                        }
                    }
                default: transcriptEditor(
                    segments: model.currentSession?.finalTranscript ?? [],
                    binding: Binding(get: { model.currentSession?.finalMarkdown ?? "" }, set: { model.updateReview(final: $0) }),
                    inRawTranscript: false
                )
                }
            }
            .id(reviewContentAnimationID)
            .transition(reduceMotion ? .opacity : WhispMotion.contentTransition)
            .animation(reduceMotion ? nil : WhispMotion.content, value: reviewContentAnimationID)

            reviewFooter
        }
        .task(id: model.currentSession?.id) { await model.loadPlayback(source: audioSource) }
        .onChange(of: audioSource) { Task { await model.loadPlayback(source: audioSource) } }
        .background(WhispPalette.canvas)
        .fileImporter(
            isPresented: $showPhotoImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task { await model.attachPhotosToCurrentSession(urls) }
            case .failure(let error):
                model.lastError = error.localizedDescription
            }
        }
        .sheet(item: $editingSegment) { segment in
            TranscriptSegmentEditor(
                segment: segment,
                canMerge: model.canMergeTranscriptSegment(id: segment.id, inRawTranscript: editingSegmentIsRaw),
                onSave: { text, speaker in
                    model.updateTranscriptSegment(
                        id: segment.id,
                        text: text,
                        speaker: speaker,
                        inRawTranscript: editingSegmentIsRaw
                    )
                    editingSegment = nil
                },
                onMerge: {
                    model.mergeTranscriptSegment(id: segment.id, inRawTranscript: editingSegmentIsRaw)
                    editingSegment = nil
                }
            )
        }
    }

    private var reviewFooter: some View {
        VStack(spacing: 12) {
            Divider()
            HStack {
                Label(model.currentSession?.cloudSyncTitle ?? "Только на Mac", systemImage: model.currentSession?.cloudSyncIcon ?? "internaldrive")
                Spacer()
                if !readingTimeText.isEmpty { Text(readingTimeText) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: WhispMetrics.contentWidth)
        .padding(.horizontal, 32).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var footerActions: some View {
                WhispGlassGroup {
                    HStack(spacing: 8) {
                        Menu {
                            Button {
                                model.exportMarkdownFile(tabName: tab, customContent: currentContent)
                            } label: {
                                Label("Сохранить эту заметку в файл (.md)...", systemImage: "doc.text")
                            }

                            Button {
                                model.exportAudioFile(source: audioSource)
                            } label: {
                                Label("Экспорт аудиозаписи (.m4a)...", systemImage: "waveform")
                            }

                            Button {
                                model.printLecture(content: currentContent)
                            } label: {
                                Label("Печать / Экспорт в PDF...", systemImage: "printer")
                            }

                            Divider()

                            Button {
                                model.revealInFinder()
                            } label: {
                                Label("Показать файлы в Finder", systemImage: "folder")
                            }

                            Button {
                                model.openInObsidian()
                            } label: {
                                Label("Открыть заметку в Obsidian", systemImage: "arrow.up.forward.app")
                            }
                        } label: {
                            Label("Экспорт", systemImage: "square.and.arrow.up")
                        }
                        .menuStyle(.button).buttonStyle(WhispActionStyle()).fixedSize()
                        .controlSize(.regular)
                        .help("Экспорт конспекта, аудиозаписи или печать")

                        Button { Task { await model.syncCurrent() } } label: { WhispGlassActionLabel(title: "Синхронизировать", systemImage: "icloud.and.arrow.up") }
                            .buttonStyle(.plain)

                    }
                }
    }

    private var animatedTabSelection: Binding<String> {
        Binding(
            get: { tab },
            set: { newValue in
                withAnimation(reduceMotion ? nil : WhispMotion.navigation) {
                    tab = newValue
                }
            }
        )
    }

    private var readingChrome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(WhispFormatting.displayTitle(model.currentSession?.title ?? "Лекция"))
                        .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text("\(model.currentSession?.subject ?? "") · \(selectedLectureDateText)")
                        .font(.callout).foregroundStyle(.secondary)
                    if let session = model.currentSession {
                        Label(session.cloudSyncTitle, systemImage: session.cloudSyncIcon)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Button { showLectureDetails = true } label: {
                    WhispGlassIconActionLabel(systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .help("Свойства лекции")
                .accessibilityLabel("Свойства лекции")
                .popover(isPresented: $showLectureDetails) { lectureDetails }
            }
            WhispGlassSegment(selection: animatedTabSelection, options: [
                ("student", "Конспект", "book.closed"),
                ("notes", "Подробно", "doc.text"),
                ("quiz", "К зачёту", "graduationcap"),
                ("final", "Расшифровка", "text.quote")
            ])
            HStack(spacing: 10) {
                if tab != "quiz" || quizViewMode == "markdown" {
                    Button {
                        animatedPreviewSelection.wrappedValue.toggle()
                    } label: {
                        WhispGlassActionLabel(title: isPreviewMode ? "Редактировать" : "Готово", systemImage: isPreviewMode ? "pencil" : "checkmark")
                    }
                    .buttonStyle(.plain)
                }
                footerActions
                Menu {
                    Button("Сведения о лекции…", systemImage: "info.circle") { showLectureDetails = true }
                    Divider()
                    Button("Копировать текст", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(currentContent, forType: .string)
                    }
                    Button("Добавить фото…", systemImage: "photo.badge.plus") { showPhotoImporter = true }
                        .disabled(model.isBusy || (model.currentSession?.attachedImagePaths.count ?? 0) >= 10)
                    Divider()
                    Button("Создать конспект заново", systemImage: "sparkles") {
                        Task { await model.regenerateAnalysis(forceOverwriteNotes: true) }
                    }
                    .disabled(model.currentSession.map { model.isAnalysisQueued(for: $0.id) } ?? true)
                } label: { Label("Ещё", systemImage: "ellipsis") }
                .menuStyle(.button).buttonStyle(WhispActionStyle()).fixedSize()
                Spacer(minLength: 0)
            }
            if let session = model.currentSession,
               session.analysis != nil || !session.attachedImagePaths.isEmpty {
                DisclosureGroup(isExpanded: $showStudyDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        metadataStrip
                        remindersSection
                        if !session.attachedImagePaths.isEmpty {
                            Label("Фото лекции: \(session.attachedImagePaths.count). Учитываются при создании конспекта.", systemImage: "photo")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 8)
                } label: {
                    Label("Задания и материалы", systemImage: "checklist")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if model.currentSession?.hasPendingBackfill == true {
                Button("Улучшить локальную часть расшифровки") { Task { await model.backfillNow() } }
                    .buttonStyle(WhispActionStyle()).tint(.primary).tint(.orange)
            }
            if model.isGeneratingNotes {
                ProgressView(model.statusMessage, value: model.processingProgress).font(.caption)
            }
            if model.player.duration > 0 { playerBar }
            if tab == "final" { transcriptModeBanner }
        }
        .frame(maxWidth: WhispMetrics.contentWidth, alignment: .leading)
        .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var lectureDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Свойства лекции").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("Название").foregroundStyle(.secondary)
                    TextField("Название", text: Binding(
                        get: { model.currentSession?.title ?? "" },
                        set: { model.updateReview(title: $0) }
                    ))
                    .whispGlassField()
                    .accessibilityLabel("Название лекции")
                }
                GridRow {
                    Text("Предмет").foregroundStyle(.secondary)
                    Picker("Предмет", selection: Binding(get: { model.currentSession?.subject ?? "Не определено" }, set: { model.updateReview(subject: $0) })) {
                        ForEach(Array(Set(model.activeSubjects + [model.currentSession?.subject ?? "Не определено"])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Дата").foregroundStyle(.secondary)
                    DatePicker("Дата лекции", selection: Binding(get: { model.currentSession?.startedAt ?? model.currentSession?.createdAt ?? Date() }, set: { model.updateReview(date: $0) }), displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .fixedSize()
                }
            }
            HStack {
                Spacer()
                Button("Готово") { showLectureDetails = false }
                    .buttonStyle(WhispActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var animatedPreviewSelection: Binding<Bool> {
        Binding(
            get: { isPreviewMode },
            set: { newValue in
                withAnimation(reduceMotion ? nil : WhispMotion.content) {
                    isPreviewMode = newValue
                }
            }
        )
    }

    private var reviewContentAnimationID: String {
        "\(tab)-\(isPreviewMode)-\(quizViewMode)"
    }

    private var currentContent: String {
        switch tab {
        case "student":
            guard let session = model.currentSession else { return "" }
            return MarkdownExporter.reviewStudentNotebook(session: session)
        case "notes": return model.currentSession?.notesMarkdown ?? ""
        case "quiz": return model.currentSession?.quizMarkdown ?? ""
        default: return model.currentSession?.finalMarkdown ?? ""
        }
    }

    private var selectedLectureDateText: String {
        let date = model.currentSession?.startedAt ?? model.currentSession?.createdAt ?? Date()
        return WhispFormatting.lectureDate(date)
    }



    private var metadataStrip: some View {
        Group {
            if let analysis = model.currentSession?.analysis,
               !(analysis.tags.isEmpty && analysis.keyConcepts.isEmpty) {
                HStack(spacing: 10) {
                    Label("МЕТАДАННЫЕ", systemImage: "tag")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Color.primary.opacity(0.72))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(analysis.tags.prefix(4), id: \.self) { tag in
                                metadataChip("#\(tag)", accent: true)
                            }
                            ForEach(analysis.keyConcepts.prefix(3), id: \.self) { concept in
                                metadataChip(concept)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .whispContentCard(cornerRadius: WhispMetrics.compactCornerRadius)
            }
        }
    }

    @ViewBuilder private var remindersSection: some View {
        if let session = model.currentSession,
           let reminders = session.analysis?.reminders,
           !reminders.isEmpty {
            let nextLesson = ReminderService().nextLessonDate(
                subject: session.subject,
                after: session.startedAt ?? session.createdAt,
                schedule: model.settingsStore.settings.lessonSchedule
            )
            let reminderDate = ReminderService().preparationDate(before: nextLesson)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Задания к следующему уроку", systemImage: "checklist")
                        .font(.headline)
                    Spacer()
                    if session.createdReminderIDs.isEmpty {
                        Button {
                            Task { await model.createRemindersForCurrentSession() }
                        } label: {
                            Label("Добавить в Reminders", systemImage: "plus")
                        }
                        .buttonStyle(WhispActionStyle(prominent: true))
                        .controlSize(.small)
                    } else {
                        Label("Добавлено", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WhispPalette.success)
                    }
                }

                Text("Напомнить: \(reminderDate.formatted(date: .abbreviated, time: .shortened)) — вечером накануне")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(reminders) { reminder in
                    let isCompleted = session.completedReminderIDs.contains(reminder.id)
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            withAnimation(WhispMotion.control) {
                                model.toggleReminderCompletion(
                                    sessionID: session.id,
                                    reminderID: reminder.id
                                )
                            }
                        } label: {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(isCompleted ? WhispPalette.success : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(reminder.title)
                                .font(.callout.weight(.medium))
                                .strikethrough(isCompleted)
                            Text(reminder.notes).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(role: .destructive) {
                            withAnimation(WhispMotion.content) {
                                model.deleteReminder(
                                    sessionID: session.id,
                                    reminderID: reminder.id
                                )
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Удалить задание")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isCompleted ? 0.72 : 1)
                }
            }
            .padding(12)
            .whispContentCard(cornerRadius: WhispMetrics.compactCornerRadius)
        }
    }

    private func metadataChip(_ text: String, accent: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(accent ? .medium : .regular))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .whispQuietSurface(cornerRadius: 6)
            .foregroundStyle(accent ? Color.primary.opacity(0.92) : .secondary)
    }

    private var readingTimeText: String {
        let words = currentContent.split { $0.isWhitespace || $0.isNewline }.count
        if words == 0 { return "" }
        let minutes = max(1, Int(ceil(Double(words) / 180.0)))
        return "\(minutes) мин чтения"
    }

    private var hasManualEdits: Bool {
        guard let session = model.currentSession else { return false }
        return session.userEditedFinal || session.userEditedNotes || session.userEditedStudentNotes
    }

    private var playerBar: some View {
        HStack(spacing: 8) {
            Button {
                model.player.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Назад на 15 секунд")
            .accessibilityLabel("Назад на 15 секунд")

            Button { model.player.toggle() } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.player.isPlaying ? "Пауза" : "Воспроизвести")

            Button {
                model.player.skip(by: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Вперёд на 15 секунд")
            .accessibilityLabel("Вперёд на 15 секунд")

            Text(WhispFormatting.timestamp(model.player.currentTime)).monospacedDigit().font(.caption)
            Slider(value: Binding(get: { model.player.currentTime }, set: { model.player.seek(to: $0) }), in: 0...max(1, model.player.duration))
                .tint(.secondary)
            Text(WhispFormatting.timestamp(model.player.duration)).monospacedDigit().font(.caption).foregroundStyle(.secondary)

            Menu {
                ForEach(AudioPlayerController.availableRates, id: \.self) { rate in
                    Button {
                        model.player.setRate(rate)
                    } label: {
                        HStack {
                            Text(String(format: "%.2fx", rate).replacingOccurrences(of: ".00", with: ".0"))
                            if model.player.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2fx", model.player.playbackRate).replacingOccurrences(of: ".00x", with: "x").replacingOccurrences(of: "0x", with: "x"))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)

            }
            .menuStyle(.button).buttonStyle(WhispActionStyle())
            .help("Скорость воспроизведения")

            Menu {
                Button {
                    audioSource = .microphone
                } label: {
                    Label("Микрофон", systemImage: audioSource == .microphone ? "checkmark" : "mic.fill")
                }
                if model.currentSession?.captureSystemAudio == true {
                    Button {
                        audioSource = .system
                    } label: {
                        Label("Системный звук", systemImage: audioSource == .system ? "checkmark" : "waveform")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: audioSource == .microphone ? "mic.fill" : "waveform")

                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            }
            .menuStyle(.button).buttonStyle(WhispActionStyle())
            .accessibilityLabel("Источник аудио")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .whispQuietSurface()
    }

    private var transcriptModeBanner: some View {
        let tint = WhispPalette.accent
        let title = "Стенограмма"
        let detail = "Очищенный текст лекции для чтения и правок"
        let icon = "text.quote"

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.10), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Text("ГОТОВЫЙ ТЕКСТ")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .whispQuietSurface(cornerRadius: WhispMetrics.controlCornerRadius)
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private func transcriptEditor(segments: [TranscriptSegment], binding: Binding<String>, inRawTranscript: Bool) -> some View {
        Group {
            if segments.isEmpty && binding.wrappedValue.isEmpty {
                ContentUnavailableView(
                    "Здесь пока нет текста",
                    systemImage: "text.quote",
                    description: Text("Расшифровка появится после успешной записи или импорта аудиофайла.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            TextField("Поиск по стенограмме...", text: $transcriptFilter)
                                .whispGlassField()
                                .font(.caption)
                            if !transcriptFilter.isEmpty {
                                Button {
                                    transcriptFilter = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)

                        let filtered = transcriptFilter.trimmingCharacters(in: .whitespaces).isEmpty
                            ? segments
                            : segments.filter { $0.text.localizedCaseInsensitiveContains(transcriptFilter) }

                        if !transcriptFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(filtered.isEmpty ? "Совпадений нет" : "Найдено: \(filtered.count)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(filtered.isEmpty ? .secondary : WhispPalette.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ScrollViewReader { proxy in
                            List(filtered) { segment in
                                let isCurrent = model.player.currentTime >= segment.start && model.player.currentTime <= segment.end
                                HStack(alignment: .top, spacing: 8) {
                                    Button {
                                        model.player.seek(to: segment.start)
                                        if !model.player.isPlaying {
                                            model.player.play()
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            if isCurrent {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(WhispPalette.accent)
                                            }
                                             Text(WhispFormatting.timestamp(segment.start))
                                                 .monospacedDigit()
                                         }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption.weight(isCurrent ? .bold : .regular))
                                    .foregroundStyle(isCurrent ? WhispPalette.accent : .secondary)
                                    .help("Перейти к \(WhispFormatting.timestamp(segment.start)) в аудиозаписи")
                                    .accessibilityLabel("Перейти к \(WhispFormatting.timestamp(segment.start)) в аудиозаписи")

                                    VStack(alignment: .leading, spacing: 3) {
                                        if let speaker = segment.speaker, !speaker.isEmpty {
                                            Text(speaker)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(WhispPalette.accent)
                                        }
                                        Text(segment.text)
                                            .lineLimit(4)
                                            .font(.caption)
                                            .foregroundStyle(isCurrent ? .primary : .secondary)
                                            .fontWeight(isCurrent ? .medium : .regular)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(
                                    isCurrent ? WhispPalette.accent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .contextMenu {
                                    Button {
                                        editingSegment = segment
                                        editingSegmentIsRaw = inRawTranscript
                                    } label: {
                                        Label("Изменить реплику", systemImage: "pencil")
                                    }

                                    Button {
                                        model.mergeTranscriptSegment(id: segment.id, inRawTranscript: inRawTranscript)
                                    } label: {
                                        Label("Объединить со следующей", systemImage: "arrow.merge")
                                    }
                                    .disabled(segment.id == segments.last?.id)
                                }
                                .id(segment.id)
                            }
                            .listStyle(.inset)
                            .scrollContentBackground(.hidden)
                            .background(WhispPalette.content)
                            .onChange(of: model.player.currentTime) { _, newTime in
                                guard model.player.isPlaying else { return }
                                if let current = filtered.first(where: { newTime >= $0.start && newTime <= $0.end }) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(current.id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 400)

                    editor(binding: binding)
                }
            }
        }
    }

    private func editor(binding: Binding<String>) -> some View {
        Group {
            if isPreviewMode {
                MarkdownPreview(
                    markdown: binding.wrappedValue,
                    showsDocumentTitle: false
                )
            } else {
                TextEditor(text: binding)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(WhispPalette.content)

            }
        }
    }
}

private struct TranscriptSegmentEditor: View {
    let segment: TranscriptSegment
    let onSave: (String, String) -> Void
    let onMerge: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var speaker: String

    let canMerge: Bool

    init(segment: TranscriptSegment, canMerge: Bool, onSave: @escaping (String, String) -> Void, onMerge: @escaping () -> Void) {
        self.segment = segment
        self.canMerge = canMerge
        self.onSave = onSave
        self.onMerge = onMerge
        _text = State(initialValue: segment.text)
        _speaker = State(initialValue: segment.speaker ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Редактировать реплику").font(.title3.weight(.semibold))
                    Text(WhispFormatting.timestamp(segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }

            TextField("Спикер (необязательно)", text: $speaker)
                .whispGlassField()

            TextEditor(text: $text)
                .font(.body)
                .whispGlassEditor()

            HStack {
                Button("Объединить со следующей", action: onMerge)
                    .buttonStyle(WhispActionStyle())
                    .foregroundStyle(WhispPalette.accent)
                    .disabled(!canMerge)
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    onSave(text, speaker)
                }
                .buttonStyle(WhispActionStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560, height: 360)
        .tint(WhispPalette.accent)
    }
}

// MARK: - Interactive Quiz Models & Parser

struct QuizQuestionItem: Identifiable {
    let id: Int
    let question: String
    let answer: String
}

struct QuizFlashcardItem: Identifiable {
    let id: Int
    let term: String
    let definition: String
}

struct QuizContentData {
    var title: String = ""
    var questions: [QuizQuestionItem] = []
    var flashcards: [QuizFlashcardItem] = []
    var pitfalls: [String] = []
}

enum QuizParser {
    static func parse(_ markdown: String) -> QuizContentData {
        var result = QuizContentData()
        let lines = markdown.components(separatedBy: .newlines)

        enum Section {
            case none
            case questions
            case flashcards
            case pitfalls
        }

        var currentSection = Section.none
        var currentQuestion = ""
        var currentAnswerLines: [String] = []
        var currentTerm = ""
        var currentDefLines: [String] = []
        var currentPitfalls: [String] = []
        var currentPitfallLines: [String] = []

        func cleanedMarkdownLine(_ line: String) -> String {
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            while value.hasPrefix(">") {
                value.removeFirst()
                value = value.trimmingCharacters(in: .whitespaces)
            }
            value = value.replacingOccurrences(
                of: "^[0-9]+[.)]\\s*|^[-•]\\s*",
                with: "",
                options: .regularExpression
            )
            value = value
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "^[•-]\\s*", with: "", options: .regularExpression)
            value = MarkdownDisplayFormatting.readableFormula(value)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func startsNewPitfall(_ line: String) -> Bool {
            let value = line.trimmingCharacters(in: .whitespaces)
            let isNumbered = value.range(
                of: "^[0-9]+[.)]\\s+",
                options: .regularExpression
            ) != nil
            let isBoldTitle = value.hasPrefix("**")
                && !value.localizedCaseInsensitiveContains("ошибка")
                && !value.localizedCaseInsensitiveContains("как правильно")
            return isNumbered || isBoldTitle
        }

        func finishPitfall() {
            let value = currentPitfallLines
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                currentPitfalls.append(value)
            }
            currentPitfallLines = []
        }

        func finishQuestion() {
            let q = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let a = currentAnswerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty {
                let id = result.questions.count
                result.questions.append(QuizQuestionItem(id: id, question: q, answer: a))
            }
            currentQuestion = ""
            currentAnswerLines = []
        }

        func finishFlashcard() {
            let t = currentTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = currentDefLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                let id = result.flashcards.count
                result.flashcards.append(QuizFlashcardItem(id: id, term: t, definition: d))
            }
            currentTerm = ""
            currentDefLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                result.title = trimmed.replacingOccurrences(of: "# ", with: "").replacingOccurrences(of: "🎯 Подготовка к зачёту:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.contains("Контрольные вопросы") {
                finishQuestion()
                finishFlashcard()
                currentSection = .questions
                continue
            } else if trimmed.contains("Карточки для запоминания") || trimmed.contains("Flashcards") {
                finishQuestion()
                finishFlashcard()
                currentSection = .flashcards
                continue
            } else if trimmed.contains("Опасные места") || trimmed.contains("типичные ошибки") {
                finishQuestion()
                finishFlashcard()
                currentSection = .pitfalls
                continue
            }

            switch currentSection {
            case .questions:
                if trimmed.contains("[!question]") {
                    finishQuestion()
                    var q = trimmed
                    if let range = q.range(of: "[!question]") {
                        q = String(q[range.upperBound...])
                    }
                    q = q.replacingOccurrences(of: "Вопрос:", with: "").trimmingCharacters(in: .whitespaces)
                    currentQuestion = q
                } else if trimmed.contains("[!success]") {
                    // spoiler header line
                } else if trimmed.hasPrefix(">>") || trimmed.hasPrefix("> >") {
                    var a = trimmed
                    while a.hasPrefix(">") || a.hasPrefix(" ") { a.removeFirst() }
                    currentAnswerLines.append(a)
                } else if !currentQuestion.isEmpty && !trimmed.isEmpty && !trimmed.hasPrefix(">") {
                    currentAnswerLines.append(trimmed)
                }

            case .flashcards:
                if trimmed.contains("[!example]") {
                    finishFlashcard()
                    var t = trimmed
                    if let range = t.range(of: "[!example]") {
                        t = String(t[range.upperBound...])
                    }
                    t = t.replacingOccurrences(of: "Термин:", with: "")
                        .replacingOccurrences(of: "[[", with: "")
                        .replacingOccurrences(of: "]]", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    currentTerm = t
                } else if trimmed.contains("[!tip]") {
                    // tip header line
                } else if trimmed.hasPrefix(">>") || trimmed.hasPrefix("> >") {
                    var d = trimmed
                    while d.hasPrefix(">") || d.hasPrefix(" ") { d.removeFirst() }
                    currentDefLines.append(d)
                } else if !currentTerm.isEmpty && !trimmed.isEmpty && !trimmed.hasPrefix(">") {
                    currentDefLines.append(trimmed)
                }

            case .pitfalls:
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    if startsNewPitfall(trimmed), !currentPitfallLines.isEmpty {
                        finishPitfall()
                    }
                    let cleaned = cleanedMarkdownLine(trimmed)
                    if !cleaned.isEmpty {
                        currentPitfallLines.append(cleaned)
                    }
                }
            case .none:
                break
            }
        }

        finishQuestion()
        finishFlashcard()
        finishPitfall()
        result.pitfalls = currentPitfalls
        return result
    }
}

// MARK: - Interactive Quiz View

struct InteractiveQuizView: View {
    let markdown: String
    var onScrollOffsetChange: ((CGFloat) -> Void)? = nil
    @Binding var progress: QuizProgress

    var body: some View {
        let quiz = QuizParser.parse(markdown)
        let revealedQuestions = Set(progress.revealedQuestions)
        let revealedFlashcards = Set(progress.revealedFlashcards)
        let answeredQuestions = progress.answeredQuestionIDs

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !quiz.title.isEmpty {
                    Text(quiz.title)
                        .font(.title2.bold())
                }

                if !quiz.questions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Прогресс подготовки", systemImage: "chart.bar.fill")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(progress.answeredQuestionCount) из \(quiz.questions.count) вопросов")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(1, Double(progress.answeredQuestionCount) / Double(quiz.questions.count)))
                            .tint(WhispPalette.accent)
                    }
                    .padding(12)
                    .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                }

                // Questions Section
                if !quiz.questions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Контрольные вопросы")
                                .font(.headline)
                            Spacer()
                            Button(revealedQuestions.count == quiz.questions.count ? "Скрыть ответы" : "Показать все ответы") {
                                withAnimation {
                                    var updated = progress
                                    if revealedQuestions.count == quiz.questions.count {
                                        updated.revealedQuestions.removeAll()
                                    } else {
                                        updated.revealedQuestions = quiz.questions.map(\.id)
                                    }
                                    progress = updated
                                }
                             }
                             .buttonStyle(.plain)
                             .font(.caption)
                             .foregroundStyle(WhispPalette.accent)
                        }

                        ForEach(quiz.questions) { item in
                            let isRevealed = revealedQuestions.contains(item.id)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    Text("\(item.id + 1).")
                                        .font(.headline)
                                        .foregroundStyle(WhispPalette.accent)
                                    Text(item.question)
                                        .font(.body.weight(.medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            var updated = progress
                                            if isRevealed {
                                                updated.setQuestionRevealed(item.id, revealed: false)
                                            } else {
                                                updated.setQuestionRevealed(item.id, revealed: true)
                                            }
                                            progress = updated
                                        }
                                    } label: {
                                        Label(isRevealed ? "Скрыть ответ" : "Показать ответ", systemImage: isRevealed ? "eye.slash" : "eye")
                                            .font(.caption)
                                     }
                                     .buttonStyle(.plain)
                                     .controlSize(.small)
                                     .foregroundStyle(WhispPalette.accent)
                                }

                                if isRevealed {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                            Text("Правильный ответ:")
                                                .font(.caption.bold())
                                                .foregroundStyle(.green)
                                        }
                                        Text(LocalizedStringKey(item.answer))
                                            .font(.body)
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                    }
                                     .padding(12)
                                     .frame(maxWidth: .infinity, alignment: .leading)
                                     .background(Color.green.opacity(0.08), in: .rect(cornerRadius: WhispMetrics.compactCornerRadius))
                                     .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                HStack(spacing: 8) {
                                    Text("Как прошло?")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        var updated = progress
                                        updated.markQuestion(item.id, correct: true)
                                        progress = updated
                                     } label: {
                                         Label("Знаю", systemImage: "checkmark")
                                     }
                                     .buttonStyle(.plain)
                                     .controlSize(.small)
                                     .tint(.green)
                                     .foregroundStyle(.green)

                                    Button {
                                        var updated = progress
                                        updated.markQuestion(item.id, correct: false)
                                        progress = updated
                                     } label: {
                                         Label("Повторить", systemImage: "arrow.counterclockwise")
                                     }
                                     .buttonStyle(.plain)
                                     .controlSize(.small)
                                     .tint(.orange)
                                     .foregroundStyle(.orange)

                                    if answeredQuestions.contains(item.id) {
                                        Text(progress.answeredCorrectly.contains(item.id) ? "Отмечено: знаю" : "Отмечено: повторить")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(progress.answeredCorrectly.contains(item.id) ? .green : .orange)
                                    }
                                }
                             }
                             .padding(14)
                             .whispQuietSurface(cornerRadius: WhispMetrics.controlCornerRadius)
                        }
                    }
                }

                // Flashcards Section
                if !quiz.flashcards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Карточки для запоминания")
                                .font(.headline)
                            Spacer()
                            Button(revealedFlashcards.count == quiz.flashcards.count ? "Скрыть все" : "Открыть все") {
                                withAnimation {
                                    var updated = progress
                                    if revealedFlashcards.count == quiz.flashcards.count {
                                        updated.revealedFlashcards.removeAll()
                                    } else {
                                        updated.revealedFlashcards = quiz.flashcards.map(\.id)
                                    }
                                    progress = updated
                                }
                             }
                             .buttonStyle(.plain)
                             .font(.caption)
                             .foregroundStyle(WhispPalette.accent)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(quiz.flashcards) { card in
                                let isRevealed = revealedFlashcards.contains(card.id)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(card.term)
                                            .font(.headline)
                                            .foregroundStyle(WhispPalette.accent)
                                        Spacer()
                                        Image(systemName: isRevealed ? "chevron.up.circle.fill" : "questionmark.circle")
                                            .foregroundStyle(isRevealed ? WhispPalette.accent : .secondary)
                                    }

                                    if isRevealed {
                                        Text(card.definition)
                                            .font(.caption)
                                            .lineSpacing(3)
                                            .foregroundStyle(.primary)
                                            .transition(.opacity)
                                    } else {
                                        Text("Нажмите, чтобы увидеть определение...")
                                            .font(.caption)
                                            .italic()
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        var updated = progress
                                        if isRevealed {
                                            updated.setFlashcardRevealed(card.id, revealed: false)
                                        } else {
                                            updated.setFlashcardRevealed(card.id, revealed: true)
                                        }
                                        progress = updated
                                    }
                                }
                            }
                        }
                    }
                }

                // Pitfalls Section
                if !quiz.pitfalls.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Опасные места", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(Array(quiz.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                            let parts = pitfall.components(separatedBy: .newlines)
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.orange.opacity(0.75))
                                    .frame(width: 3)

                                VStack(alignment: .leading, spacing: 8) {
                                    if let title = parts.first {
                                        Text(title)
                                            .font(.subheadline.weight(.semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if parts.count > 1 {
                                        VStack(alignment: .leading, spacing: 5) {
                                            ForEach(Array(parts.dropFirst().enumerated()), id: \.offset) { _, line in
                                                if line == "Ошибка:" {
                                                    Text("Ошибка")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.orange)
                                                } else if line == "Как правильно:" {
                                                    Text("Как правильно")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.green)
                                                        .padding(.top, 3)
                                                } else {
                                                    Text(line)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                        .lineSpacing(3)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                        .textSelection(.enabled)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .whispQuietSurface(cornerRadius: WhispMetrics.controlCornerRadius)
                        }
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            onScrollOffsetChange?(offset)
        }
        .background(WhispPalette.content)
    }
}

// MARK: - Backfill Comparison View

struct BackfillComparisonView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WhispPalette.accent)
                    .frame(width: 38, height: 38)
                    .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Сравнение дорасшифровки")
                        .font(.title3.weight(.semibold))
                    Text("Проверьте фрагменты Whisper перед заменой на результат Gemini.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            WhispGlassDivider()

            HSplitView {
                comparisonPane(title: "До: локальный Whisper", text: model.backfillBefore)
                comparisonPane(title: "После: Gemini", text: model.backfillAfter)
            }
            .padding(18)

            WhispGlassDivider()

            HStack {
                Button("Отмена") { model.showBackfillComparison = false }
                    .buttonStyle(WhispActionStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Принять Gemini") { Task { await model.acceptBackfill() } }
                    .buttonStyle(WhispActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WhispPalette.canvas)
        .tint(WhispPalette.accent)
    }

    private func comparisonPane(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            TextEditor(text: .constant(text))
                .font(.system(.caption, design: .monospaced))
                .whispGlassEditor(cornerRadius: WhispMetrics.controlCornerRadius)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
