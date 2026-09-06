import SwiftUI
import UniformTypeIdentifiers

enum WhispPalette {
    static let accent = Color(red: 0.92, green: 0.32, blue: 0.24)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let hairline = Color.primary.opacity(0.13)
    static let quietFill = Color.primary.opacity(0.055)
}

struct MainView: View {
    @Bindable var model: AppModel
    @State private var searchText = ""
    @State private var selectedSubject = "Все"

    private var filteredSessions: [LectureSession] {
        model.sessions.filter { session in
            let matchesSubject = (selectedSubject == "Все") || (session.subject == selectedSubject)
            if !matchesSubject { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.isEmpty { return true }
            let titleMatch = session.title.lowercased().contains(query)
            let subjectMatch = session.subject.lowercased().contains(query)
            let tagsMatch = session.analysis?.tags.contains { $0.lowercased().contains(query) } ?? false
            let conceptsMatch = session.analysis?.keyConcepts.contains { $0.lowercased().contains(query) } ?? false
            let transcriptMatch = session.finalTranscript.contains { $0.text.localizedCaseInsensitiveContains(query) }
                || session.rawTranscript.contains { $0.text.localizedCaseInsensitiveContains(query) }
            let notesMatch = session.notesMarkdown.localizedCaseInsensitiveContains(query)
                || session.studentNotesMarkdown.localizedCaseInsensitiveContains(query)
            let markdownMatch = session.finalMarkdown.localizedCaseInsensitiveContains(query)
                || session.rawMarkdown.localizedCaseInsensitiveContains(query)
                || session.quizMarkdown.localizedCaseInsensitiveContains(query)
            return titleMatch || subjectMatch || tagsMatch || conceptsMatch || transcriptMatch || notesMatch || markdownMatch
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            ZStack {
                WhispPalette.canvas.ignoresSafeArea()
                detail
                updateProgressOverlay
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(WhispPalette.accent)
        .alert("Завершить лекцию?", isPresented: $model.showStopConfirmation) {
            Button("Отмена", role: .cancel) { model.discardStopRequest() }
            Button("Завершить", role: .destructive) { Task { await model.confirmStop() } }
        } message: {
            Text("Запись остановится, затем Whisp подготовит расшифровку и конспект.")
        }
        .alert("Найдена незавершённая запись", isPresented: $model.showRecoveryPrompt) {
            Button("Восстановить") { Task { await model.recoverSession() } }
            Button("Позже", role: .cancel) { model.dismissRecovery() }
        } message: { Text("Уже записанные аудиосегменты сохранены.") }
        .alert("Удалённая версия изменилась", isPresented: $model.showSyncConflict) {
            Button("Перезаписать удалённую", role: .destructive) {
                Task { await model.overwriteRemoteAfterConflict() }
            }
            Button("Позже", role: .cancel) { model.showSyncConflict = false }
        } message: {
            Text("В папке WebDAV «\(model.syncConflictPath)» появились изменения после последней синхронизации. Проверьте удалённую заметку перед перезаписью.")
        }
        .alert("\(model.settingsStore.activeProviderName) снова доступен", isPresented: $model.showBackfillPrompt) {
            Button("Дорасшифровать сейчас") { Task { await model.backfillNow() } }
            Button("Напомнить позже") { model.deferBackfill() }
            Button("Оставить локальную версию", role: .destructive) { model.declineBackfill() }
        } message: { Text("Можно улучшить только участки, распознанные локальной моделью.") }
        .alert("Ошибка", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("Закрыть") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
        .alert("Нужен доступ к системному звуку", isPresented: $model.needsScreenCapturePermission) {
            Button("Открыть настройки macOS") { model.openScreenCaptureSettings() }
            Button("Позже", role: .cancel) { }
        } message: {
            Text("Включите Whisp в «Конфиденциальность и безопасность → Запись экрана и системного звука», затем полностью перезапустите приложение.")
        }
        .alert("Нет доступа к микрофону", isPresented: $model.needsMicrophonePermission) {
            Button("Открыть настройки macOS") { model.openMicrophoneSettings() }
            Button("Позже", role: .cancel) { }
        } message: {
            Text("Включите Whisp в «Конфиденциальность и безопасность → Микрофон», затем полностью перезапустите приложение. После отказа macOS больше не показывает запрос.")
        }
        .alert("Доступно обновление Whisp", isPresented: Binding(
            get: { model.updateService.availableRelease != nil },
            set: { if !$0 { model.updateService.dismissAvailableUpdate() } }
        )) {
            if let release = model.updateService.availableRelease {
                Button("Обновить до \(release.version)") {
                    Task { await model.updateService.installUpdate(release) }
                }
                .disabled(model.isRecording)
                Button("Страница релиза") { model.updateService.openReleasePage(release) }
            }
            Button("Позже", role: .cancel) { model.updateService.dismissAvailableUpdate() }
        } message: {
            if let release = model.updateService.availableRelease {
                Text(release.isPrerelease
                     ? "Доступна предварительная версия \(release.version). Whisp скачает обновление, заменит приложение в /Applications и перезапустится."
                     : "Доступна версия \(release.version). Whisp скачает обновление, заменит приложение в /Applications и перезапустится.")
            }
        }
        .sheet(isPresented: $model.showBackfillComparison) {
            BackfillComparisonView(model: model).frame(minWidth: 1_000, minHeight: 650)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model).frame(width: 720, height: 680)
        }
        .sheet(isPresented: $model.showBatchRegenerateSheet) {
            BatchRegenerateSheet(model: model)
        }
    }

    @ViewBuilder private var updateProgressOverlay: some View {
        switch model.updateService.state {
        case .downloading(let release):
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Скачиваем Whisp \(release.version)…")
                            .font(.callout.weight(.medium))
                        Spacer()
                        if let total = model.updateService.downloadTotalBytes, total > 0 {
                            Text("\(formattedBytes(model.updateService.downloadedBytes)) / \(formattedBytes(total))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let total = model.updateService.downloadTotalBytes, total > 0 {
                        ProgressView(value: model.updateService.downloadProgress)
                    } else {
                        ProgressView()
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WhispPalette.hairline))
                .padding(18)
            }
            .allowsHitTesting(false)
        case .installing(let release):
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Установка и перезапуск Whisp \(release.version)…")
                        .font(.callout.weight(.medium))
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WhispPalette.hairline))
                .padding(18)
            }
            .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(WhispPalette.accent)
                    Image(systemName: "waveform").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                }.frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Whisp").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("лекции и конспекты").font(.caption2).foregroundStyle(.secondary)
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
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Название, предмет, тег или текст", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(WhispPalette.quietFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(WhispPalette.hairline, lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // Subject Filter Chips
            let subjects = ["Все"] + Array(Set(model.sessions.map(\.subject).filter { $0 != "Не определено" && !$0.isEmpty })).sorted()
            if subjects.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(subjects, id: \.self) { subj in
                            Button {
                                selectedSubject = subj
                            } label: {
                                Text(subj)
                                    .font(.caption2.weight(selectedSubject == subj ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(selectedSubject == subj ? WhispPalette.accent.opacity(0.15) : WhispPalette.quietFill, in: Capsule())
                                    .foregroundStyle(selectedSubject == subj ? WhispPalette.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 6)
            }

            if model.isRestoringFromWebDAV {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
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
            .padding(.horizontal, 17).padding(.vertical, 14)
        }
        .background(WhispPalette.sidebar)
    }

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            if let activeID = model.activeProcessingSessionID, model.currentSession?.id != activeID {
                HStack(spacing: 12) {
                    ProgressView(value: model.processingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 140)
                        .tint(WhispPalette.accent)
                    Text("\(Int(model.processingProgress * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(WhispPalette.accent)
                    Text(model.statusMessage)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.selectSession(activeID)
                    } label: {
                        Label("Показать процесс", systemImage: "waveform.badge.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(WhispPalette.panel)
                Divider()
            }

            if model.isRecording {
                RecordingView(model: model)
            } else if model.currentSession?.status == .processing {
                ProcessingView(model: model)
            } else if model.currentSession?.status == .failed {
                FailedSessionView(model: model)
            } else if model.currentSession != nil {
                ReviewView(model: model)
            } else if let session = model.displayedSession {
                SessionSummaryView(session: session)
            } else {
                StartView(model: model)
            }
        }
    }
}

private struct FailedSessionView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.red.opacity(0.09))
                Image(systemName: "exclamationmark.waveform")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.red)
            }.frame(width: 78, height: 78)
            Text("Не удалось обработать запись").font(.title2.weight(.semibold))
            Text(model.currentSession?.lastError ?? "Не удалось получить аудио")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            VStack(spacing: 6) {
                Label(model.geminiDiagnostics, systemImage: "key.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Проверить подключение Gemini") {
                    Task { _ = await model.testAllGeminiKeys() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            HStack(spacing: 10) {
                if model.needsScreenCapturePermission {
                    Button("Открыть настройки macOS") { model.openScreenCaptureSettings() }
                }
                if model.needsMicrophonePermission {
                    Button("Открыть настройки микрофона") { model.openMicrophoneSettings() }
                }
                Button(model.currentSession?.finalTranscript.isEmpty == false || model.currentSession?.rawTranscript.isEmpty == false ? "Повторить только конспект" : "Повторить обработку") { Task { await model.retryFailedStage() } }
                    .buttonStyle(.borderedProminent).tint(WhispPalette.accent)
                Button("Новая запись / импорт") { model.showStartScreen() }
                Button(role: .destructive) {
                    if let id = model.currentSession?.id {
                        model.deleteSession(id)
                    }
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

private struct ProcessingView: View {
    @Bindable var model: AppModel
    @State private var isLogExpanded = false
    @State private var showCancelConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(WhispPalette.accent.opacity(0.1)).frame(width: 74, height: 74)
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(WhispPalette.accent)
            }

            Text("Собираем лекцию").font(.title2.weight(.semibold))

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                ProgressView(value: model.processingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 520)
                    .tint(WhispPalette.accent)

                HStack {
                    Text("\(Int(model.processingProgress * 100))%")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(WhispPalette.accent)

                    if model.processingTotalChunks > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Фрагмент \(model.processingCurrentChunk) из \(model.processingTotalChunks)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !model.processingChunkRange.isEmpty {
                            Text("(\(model.processingChunkRange))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if let remaining = model.processingRemainingFormatted {
                        Text(remaining)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if model.processingStartTime != nil {
                        Text("Прошло: \(model.processingElapsedFormatted)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 520)
            }

            if let fileName = model.importedFileName {
                Label(fileName, systemImage: "waveform.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.pendingImportFileNames.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Далее в очереди: " + String(model.pendingImportFileNames.count), systemImage: "list.number")
                        .font(.caption.weight(.semibold))
                    Text(model.pendingImportFileNames.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(width: 520, alignment: .leading)
                .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 10))
            }

            if !recentSegments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recentSegments) { segment in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(WhispFormatting.timestamp(segment.start))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            Text(segment.text).font(.callout).lineLimit(2)
                        }
                    }
                }
                .padding(14).frame(width: 520, alignment: .leading)
                .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(WhispPalette.hairline))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Журнал обработки")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(model.processingLogs.count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(WhispPalette.hairline, in: Capsule())
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        let logText = model.processingLogs.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logText, forType: .string)
                    } label: {
                        Label("Копировать", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isLogExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isLogExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WhispPalette.panel)

                if isLogExpanded {
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if model.processingLogs.isEmpty {
                                    Text("Ожидание событий...")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .padding(.vertical, 4)
                                } else {
                                    ForEach(model.processingLogs) { log in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("[\(log.formattedTime)]")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                            Text(log.message)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.primary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                                Color.clear.frame(height: 1).id("logBottom")
                            }
                            .padding(10)
                        }
                        .frame(height: 120)
                        .onChange(of: model.processingLogs.count) {
                            withAnimation { proxy.scrollTo("logBottom", anchor: .bottom) }
                        }
                    }
                }
            }
            .frame(width: 520)
            .background(WhispPalette.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WhispPalette.hairline))

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    showCancelConfirmation = true
                } label: {
                    Label("Отменить обработку", systemImage: "xmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 2)
            .confirmationDialog(
                "Отменить обработку записи?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Отменить обработку", role: .destructive) {
                    Task { await model.cancelProcessing() }
                }
                Button("Продолжить", role: .cancel) { }
            } message: {
                Text("Текущий процесс будет прерван. Ранее расшифрованные фрагменты останутся в кэше и не пропадут.")
            }

            Text("Не закрывайте Whisp до завершения. Прогресс сохраняется по фрагментам.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private var recentSegments: [TranscriptSegment] {
        Array((model.currentSession?.rawTranscript ?? []).suffix(3))
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
                if session.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(session.subject)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(session.status.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

private struct StartView: View {
    private enum CaptureMode: String, CaseIterable, Identifiable {
        case microphone = "Только микрофон"
        case microphoneAndSystem = "Микрофон + система"
        var id: Self { self }
        var icon: String { self == .microphone ? "mic.fill" : "macbook.and.iphone" }
    }

    @Bindable var model: AppModel
    @State private var captureMode: CaptureMode = .microphoneAndSystem
    @State private var showAudioImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ВАШЕ ПРОСТРАНСТВО ДЛЯ ЛЕКЦИЙ")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(WhispPalette.accent)
                    Text("Слушайте.\nК важному вернётесь.")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Запишите лекцию или добавьте аудиофайл. Whisp подготовит расшифровку и конспект, которые можно проверить и отредактировать.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Новая лекция").font(.title2.weight(.semibold))
                            Text("Проверьте источник перед стартом").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.refreshInputDevices() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Обновить список микрофонов")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Микрофон").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Picker("Микрофон", selection: Binding(
                            get: { model.selectedMicrophoneID },
                            set: { model.selectedMicrophoneID = $0 }
                        )) {
                            Text("Системный по умолчанию").tag(UInt32?.none)
                            ForEach(model.inputDevices) { device in
                                Text(device.name + (device.isDefault ? " · по умолчанию" : ""))
                                    .tag(Optional(device.id))
                            }
                        }
                        .labelsHidden().frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Что записывать").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Picker("Что записывать", selection: $captureMode) {
                            ForEach(CaptureMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text(captureMode == .microphone
                             ? "Для очной лекции: записывается ваш микрофон."
                             : "Микрофон и звук приложений сохранятся отдельными дорожками.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Divider()

                    Button {
                        Task { await model.startRecording(captureSystemAudio: captureMode == .microphoneAndSystem) }
                    } label: {
                        HStack {
                            Image(systemName: "record.circle.fill")
                            Text("Начать запись").fontWeight(.semibold)
                            Spacer()
                            Text(model.settingsStore.settings.hotkeyRecord).font(.caption.monospaced()).opacity(0.78)
                        }
                        .padding(.horizontal, 4).frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(WhispPalette.accent)

                    Button {
                        showAudioImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "waveform.badge.plus")
                            Text("Импортировать аудиофайл").fontWeight(.medium)
                            Spacer()

                        }
                        .padding(.horizontal, 4).frame(height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(24)
                .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(WhispPalette.hairline))
                .disabled(model.isBusy)
                .dropDestination(for: URL.self) { urls, _ in
                    model.enqueueAudioImports(urls)
                    return true
                }

                Label("Перед отправкой в Obsidian вы сможете проверить результат.", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 600)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.enqueueAudioImports(urls)
            case .failure(let error):
                model.lastError = error.localizedDescription
            }
        }
    }
}

private struct SessionSummaryView: View {
    let session: LectureSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(session.subject).font(.caption.weight(.semibold)).foregroundStyle(WhispPalette.accent)
                Text(session.title).font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-0.8)
                Label(session.status.title, systemImage: session.status == .synced ? "checkmark.icloud" : "clock")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                Text(session.notesMarkdown).textSelection(.enabled).frame(maxWidth: 760, alignment: .leading)
            }.padding(48).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BatchRegenerateSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationInput = ""
    @State private var showConfirmAlert = false

    private var eligibleSessions: [LectureSession] {
        model.sessions.filter { !$0.finalTranscript.isEmpty || !$0.rawTranscript.isEmpty }
    }

    private var isConfirmed: Bool {
        confirmationInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ПЕРЕГЕНЕРИРОВАТЬ"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WhispPalette.accent)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Массовая перегенерация конспектов")
                        .font(.headline)
                    Text(model.isBatchRegenerating ? "Идёт обработка лекций..." : "Повторный анализ всех лекций по обновлённым правилам")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !model.isBatchRegenerating {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            if model.isBatchRegenerating {
                progressContent
            } else {
                setupContent
            }
        }
        .frame(width: 580, height: 520)
        .background(WhispPalette.canvas)
        .alert("Запустить перегенерацию всех \(eligibleSessions.count) лекций?", isPresented: $showConfirmAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Да, перегенерировать всё", role: .destructive) {
                model.startBatchRegeneration(forceOverwrite: model.batchForceOverwrite)
            }
        } message: {
            Text("Старые конспекты будут полностью заменены новыми текстами от \(model.settingsStore.activeProviderName), модель \(model.settingsStore.activeAnalysisModel).\n\nВы сможете остановить процесс в любой момент.")
        }
    }

    private var setupContent: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Внимание: перезапись конспектов")
                        .font(.subheadline.bold())
                    Text("Конспекты (тетрадь и подробный разбор) для всех лекций будут заново созданы через \(model.settingsStore.activeProviderName) API. Аудиозаписи и расшифровки не пострадают.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))

            HStack(spacing: 12) {
                metricCard(title: "Найдено лекций", value: "\(eligibleSessions.count)", icon: "books.vertical")
                metricCard(title: "Модель AI", value: model.settingsStore.activeAnalysisModel, icon: "cpu")
                metricCard(title: "Оценка времени", value: "~ \(eligibleSessions.count * 6) сек", icon: "clock")
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Перезаписать даже вручную отредактированные конспекты", isOn: $model.batchForceOverwrite)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WhispPalette.panel, in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Для подтверждения введите слово **ПЕРЕГЕНЕРИРОВАТЬ**:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("ПЕРЕГЕНЕРИРОВАТЬ", text: $confirmationInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if isConfirmed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                    }
                }
            }

            Divider()

            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    showConfirmAlert = true
                } label: {
                    Label("Начать перегенерацию...", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red)
                .disabled(!isConfirmed || eligibleSessions.isEmpty)
            }
        }
        .padding(24)
    }

    private var progressContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                HStack {
                    Text("Обработка: \(model.batchCurrentIndex) из \(model.batchTotalCount)")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(Double(model.batchCurrentIndex) / Double(max(1, model.batchTotalCount)) * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WhispPalette.accent)
                }

                ProgressView(value: Double(model.batchCurrentIndex), total: Double(max(1, model.batchTotalCount)))
                    .progressViewStyle(.linear)
                    .tint(WhispPalette.accent)

                if !model.batchCurrentTitle.isEmpty {
                    Text(model.batchCurrentTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(WhispPalette.panel, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Успешно: \(model.batchSuccessCount)").font(.caption.bold())
                }
                if model.batchFailureCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("Ошибок: \(model.batchFailureCount)").font(.caption.bold())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Журнал операций:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.batchLogs) { log in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(log.formattedTime)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                    Text(log.message)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.primary)
                                }
                                .id(log.id)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WhispPalette.hairline, lineWidth: 1))
                    .onChange(of: model.batchLogs.count) {
                        if let last = model.batchLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(role: .destructive) {
                    model.cancelBatchRegeneration()
                } label: {
                    Label("Остановить", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(WhispPalette.accent)
            Text(value)
                .font(.callout.bold())
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WhispPalette.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}
