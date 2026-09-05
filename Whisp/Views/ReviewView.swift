import SwiftUI

struct ReviewView: View {
    @Bindable var model: AppModel
    @State private var tab = "student"
    @State private var audioSource = AudioSource.microphone
    @State private var isPreviewMode = true
    @State private var copied = false
    @State private var quizViewMode = "interactive"
    @State private var transcriptFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                TextField("Название пары", text: Binding(
                    get: { model.currentSession?.title ?? "" },
                    set: { model.updateReview(title: $0) }
                )).font(.title2.bold()).textFieldStyle(.plain)
                Picker("Предмет", selection: Binding(
                    get: { model.currentSession?.subject ?? "Не определено" },
                    set: { model.updateReview(subject: $0) }
                )) {
                    Text("Не определено").tag("Не определено")
                    ForEach(model.activeSubjects, id: \.self) { Text($0).tag($0) }
                }.frame(width: 260)
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)

            // Tags & Key Concepts Bar
            if let analysis = model.currentSession?.analysis {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !analysis.tags.isEmpty {
                        ForEach(analysis.tags.prefix(4), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(WhispPalette.accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(WhispPalette.accent)
                        }
                    }
                    if !analysis.keyConcepts.isEmpty {
                        ForEach(analysis.keyConcepts.prefix(3), id: \.self) { concept in
                            Text("[[\(concept)]]")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
                }
            }

            if model.currentSession?.subject == "Не определено",
               let alternatives = model.currentSession?.analysis?.alternatives,
               !alternatives.isEmpty {
                HStack(spacing: 8) {
                    Text("Возможные предметы:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(alternatives.prefix(3), id: \.self) { subject in
                        Button(subject) { model.updateReview(subject: subject) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }

            if model.currentSession?.hasPendingBackfill == true {
                HStack {
                    Label("Часть лекции распознана локально", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    Spacer()
                    Button("Проверить Gemini") { Task { await model.backfillNow() } }
                }.padding(12).background(Color.orange.opacity(0.12))
            }

            VStack(alignment: .leading, spacing: 12) {
                Picker("Документ", selection: $tab) {
                    Text("Тетрадь").tag("student")
                    Text("Разбор").tag("notes")
                    Text("К зачёту").tag("quiz")
                    Text("Стенограмма").tag("final")
                    Text("Исходный текст").tag("raw")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 10) {
                    if tab != "quiz" || quizViewMode == "markdown" {
                        Picker("Режим", selection: $isPreviewMode) {
                            Label("Правка", systemImage: "pencil").tag(false)
                            Label("Просмотр", systemImage: "eye").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    Button {
                        let textToCopy = currentContent
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(textToCopy, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Скопировать Markdown в буфер обмена")

                    if tab != "quiz",
                       !(model.currentSession?.finalTranscript.isEmpty ?? true),
                       model.currentSession?.status != .processing {
                        Button {
                            Task { await model.regenerateAnalysis(forceOverwriteNotes: true) }
                        } label: {
                            Label(model.currentSession?.analysis == nil ? "Создать" : "Перегенерировать", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Перегенерировать конспекты через Gemini")
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(WhispPalette.panel.opacity(0.5))

            playerBar

            Group {
                switch tab {
                case "student":
                    VStack(spacing: 0) {
                        if model.currentSession?.analysis == nil || (model.currentSession?.lastError != nil) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(WhispPalette.accent)
                                Text(model.currentSession?.analysis == nil ? "Конспект ещё не создан или возникла ошибка." : "Можно перегенерировать конспект через новую модель.")
                                    .font(.caption)
                                Spacer()
                                Button("Сгенерировать конспекты") {
                                    Task { await model.regenerateAnalysis(forceOverwriteNotes: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(WhispPalette.canvas.opacity(0.7))
                        }
                        editor(binding: Binding(get: { model.currentSession?.studentNotesMarkdown ?? "" }, set: { model.updateReview(studentNotes: $0) }))
                    }
                case "notes":
                    VStack(spacing: 0) {
                        if model.currentSession?.analysis == nil || (model.currentSession?.lastError != nil) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(WhispPalette.accent)
                                Text(model.currentSession?.analysis == nil ? "Конспект ещё не создан или возникла ошибка." : "Можно перегенерировать конспект через новую модель.")
                                    .font(.caption)
                                Spacer()
                                Button("Сгенерировать конспекты") {
                                    Task { await model.regenerateAnalysis(forceOverwriteNotes: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(WhispPalette.canvas.opacity(0.7))
                        }
                        editor(binding: Binding(get: { model.currentSession?.notesMarkdown ?? "" }, set: { model.updateReview(notes: $0) }))
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
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .padding(.top, 10)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor))
                        } else {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Label("Материалы к зачёту готовы", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Picker("Вид", selection: $quizViewMode) {
                                        Text("Тренажёр").tag("interactive")
                                        Text("Markdown").tag("markdown")
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    .frame(width: 200)

                                    Button {
                                        Task { await model.generateQuiz() }
                                    } label: {
                                        Label("Перегенерировать", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(model.isGeneratingQuiz)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(WhispPalette.canvas.opacity(0.7))

                                if quizViewMode == "interactive" {
                                    InteractiveQuizView(markdown: model.currentSession?.quizMarkdown ?? "")
                                } else {
                                    editor(binding: Binding(
                                        get: { model.currentSession?.quizMarkdown ?? "" },
                                        set: { model.updateReview(quiz: $0) }
                                    ))
                                }
                            }
                        }
                    }
                case "raw": transcriptEditor(
                    segments: model.currentSession?.rawTranscript ?? [],
                    binding: Binding(get: { model.currentSession?.rawMarkdown ?? "" }, set: { model.updateReview(raw: $0) })
                )
                default: transcriptEditor(
                    segments: model.currentSession?.finalTranscript ?? [],
                    binding: Binding(get: { model.currentSession?.finalMarkdown ?? "" }, set: { model.updateReview(final: $0) })
                )
                }
            }

            HStack {
                if model.currentSession?.status == .processing {
                    ProgressView(value: model.processingProgress).frame(width: 200)
                    Button {
                        Task { await model.cancelProcessing() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Отменить обработку")
                }
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)

                if !readingTimeText.isEmpty {
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    Text(readingTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

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
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Экспорт конспекта, аудиозаписи или печать")

                Button { Task { await model.syncCurrent() } } label: { Label("Сохранить в Obsidian", systemImage: "icloud.and.arrow.up") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.currentSession?.status == .processing)
            }.padding(18)
        }
        .task { await model.loadPlayback(source: audioSource) }
        .onChange(of: audioSource) { Task { await model.loadPlayback(source: audioSource) } }
    }

    private var currentContent: String {
        switch tab {
        case "student": return model.currentSession?.studentNotesMarkdown ?? ""
        case "notes": return model.currentSession?.notesMarkdown ?? ""
        case "quiz": return model.currentSession?.quizMarkdown ?? ""
        case "raw": return model.currentSession?.rawMarkdown ?? ""
        default: return model.currentSession?.finalMarkdown ?? ""
        }
    }

    private var readingTimeText: String {
        let words = currentContent.split { $0.isWhitespace || $0.isNewline }.count
        if words == 0 { return "" }
        let minutes = max(1, Int(ceil(Double(words) / 180.0)))
        return "~ \(minutes) мин чтения (\(words) сл.)"
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button {
                model.player.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .help("Назад на 15 секунд")

            Button { model.player.toggle() } label: {
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                model.player.skip(by: 15)
            } label: {
                Image(systemName: "goforward.15")
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .help("Вперёд на 15 секунд")

            Text(WhispFormatting.timestamp(model.player.currentTime)).monospacedDigit().font(.caption)
            Slider(value: Binding(get: { model.player.currentTime }, set: { model.player.seek(to: $0) }), in: 0...max(1, model.player.duration))
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
                    .frame(width: 46)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Скорость воспроизведения")

            Picker("Дорожка", selection: $audioSource) {
                Text("Микрофон").tag(AudioSource.microphone)
                if model.currentSession?.captureSystemAudio == true { Text("Система").tag(AudioSource.system) }
            }.labelsHidden().frame(width: 120)
        }.padding(.horizontal, 22).padding(.bottom, 12)
    }

    private func transcriptEditor(segments: [TranscriptSegment], binding: Binding<String>) -> some View {
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
                                .textFieldStyle(.plain)
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
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(Divider(), alignment: .bottom)

                        let filtered = transcriptFilter.trimmingCharacters(in: .whitespaces).isEmpty
                            ? segments
                            : segments.filter { $0.text.localizedCaseInsensitiveContains(transcriptFilter) }

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
                                    .buttonStyle(.link)
                                    .font(.caption.weight(isCurrent ? .bold : .regular))

                                    Text(segment.text)
                                        .lineLimit(4)
                                        .font(.caption)
                                        .foregroundStyle(isCurrent ? .primary : .secondary)
                                        .fontWeight(isCurrent ? .medium : .regular)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(
                                    isCurrent ? WhispPalette.accent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .id(segment.id)
                            }
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
                MarkdownPreview(markdown: binding.wrappedValue)
            } else {
                TextEditor(text: binding)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
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
    @State private var revealedQuestions: Set<Int> = []
    @State private var revealedFlashcards: Set<Int> = []

    var body: some View {
        let quiz = QuizParser.parse(markdown)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !quiz.title.isEmpty {
                    Text(quiz.title)
                        .font(.title2.bold())
                }

                // Questions Section
                if !quiz.questions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("❓ Контрольные вопросы с самопроверкой")
                                .font(.headline)
                            Spacer()
                            Button(revealedQuestions.count == quiz.questions.count ? "Скрыть ответы" : "Показать все ответы") {
                                withAnimation {
                                    if revealedQuestions.count == quiz.questions.count {
                                        revealedQuestions.removeAll()
                                    } else {
                                        revealedQuestions = Set(quiz.questions.map(\.id))
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
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
                                            if isRevealed {
                                                revealedQuestions.remove(item.id)
                                            } else {
                                                revealedQuestions.insert(item.id)
                                            }
                                        }
                                    } label: {
                                        Label(isRevealed ? "Скрыть ответ" : "Показать ответ", systemImage: isRevealed ? "eye.slash" : "eye")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
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
                                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(14)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Flashcards Section
                if !quiz.flashcards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("📇 Карточки для запоминания (Flashcards)")
                                .font(.headline)
                            Spacer()
                            Button(revealedFlashcards.count == quiz.flashcards.count ? "Скрыть все" : "Открыть все") {
                                withAnimation {
                                    if revealedFlashcards.count == quiz.flashcards.count {
                                        revealedFlashcards.removeAll()
                                    } else {
                                        revealedFlashcards = Set(quiz.flashcards.map(\.id))
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
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
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isRevealed {
                                            revealedFlashcards.remove(card.id)
                                        } else {
                                            revealedFlashcards.insert(card.id)
                                        }
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
                            .background(WhispPalette.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: markdown) { _, _ in
            revealedQuestions.removeAll()
            revealedFlashcards.removeAll()
        }
    }
}

// MARK: - Backfill Comparison View

struct BackfillComparisonView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Text("Сравнение дорасшифровки").font(.title.bold())
            HSplitView {
                VStack(alignment: .leading) { Text("До — Whisper").font(.headline); TextEditor(text: .constant(model.backfillBefore)).font(.system(.caption, design: .monospaced)) }
                VStack(alignment: .leading) { Text("После — Gemini").font(.headline); TextEditor(text: .constant(model.backfillAfter)).font(.system(.caption, design: .monospaced)) }
            }
            HStack {
                Button("Отмена") { model.showBackfillComparison = false }
                Spacer()
                Button("Принять Gemini") { Task { await model.acceptBackfill() } }.buttonStyle(.borderedProminent)
            }
        }.padding(22)
    }
}
