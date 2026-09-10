import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model: AppModel
    @State private var isInspectorPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            ZStack {
                WhispPalette.canvas.ignoresSafeArea()
                detail
                updateProgressOverlay
            }
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .tint(WhispPalette.accent)
        .inspector(isPresented: $isInspectorPresented) {
            SessionInspectorView(model: model)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 340)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        model.showStartScreen()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
                    .help("Новая лекция или импорт")
                    .accessibilityLabel("Новая лекция или импорт")
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.isRecording)

                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isInspectorPresented ? WhispPalette.accent : .secondary)
                    .help(isInspectorPresented ? "Скрыть инспектор" : "Показать инспектор")
                    .accessibilityLabel(isInspectorPresented ? "Скрыть инспектор" : "Показать инспектор")
                    .disabled(model.displayedSession == nil)
                }
            }
        }
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
        .sheet(isPresented: $model.showPostUpdateScreen) {
            PostUpdateView(
                version: model.updateService.currentVersion,
                previousVersion: model.previousAppVersion,
                onDismiss: model.dismissPostUpdateScreen
            )
        }
        .sheet(isPresented: $model.showBackfillComparison) {
            BackfillComparisonView(model: model).frame(minWidth: 1_000, minHeight: 650)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
                .frame(minWidth: WhispMetrics.settingsMinWidth, minHeight: WhispMetrics.settingsMinHeight)
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model)
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
                .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.controlCornerRadius))
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
                .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.controlCornerRadius))
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
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                .padding(.horizontal, 16)
                .padding(.top, 8)
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
                Image(systemName: "exclamationmark.waveform")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.red)
            }
            .frame(width: 78, height: 78)
            .glassEffect(
                .regular.tint(Color.red.opacity(0.12)),
                in: .rect(cornerRadius: WhispMetrics.surfaceCornerRadius)
            )
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
                .buttonStyle(.glass)
                .font(.caption)
            }
            ViewThatFits(in: .horizontal) {
                WhispGlassGroup {
                    HStack(spacing: 10) { recoveryActions }
                }
                WhispGlassGroup {
                    VStack(alignment: .leading, spacing: 8) { recoveryActions }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    @ViewBuilder
    private var recoveryActions: some View {
        if model.needsScreenCapturePermission {
            Button("Открыть настройки macOS") { model.openScreenCaptureSettings() }
                .buttonStyle(.glass)
        }
        if model.needsMicrophonePermission {
            Button("Открыть настройки микрофона") { model.openMicrophoneSettings() }
                .buttonStyle(.glass)
        }
        Button(model.currentSession?.finalTranscript.isEmpty == false || model.currentSession?.rawTranscript.isEmpty == false ? "Повторить только конспект" : "Повторить обработку") {
            Task { await model.retryFailedStage() }
        }
        .buttonStyle(.glassProminent)
        Button("Новая запись / импорт") { model.showStartScreen() }
            .buttonStyle(.glass)
        Button(role: .destructive) {
            if let id = model.currentSession?.id {
                model.deleteSession(id)
            }
        } label: {
            Label("Удалить", systemImage: "trash")
        }
        .buttonStyle(.glass)
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
                .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
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
                .whispGlassControl(cornerRadius: WhispMetrics.controlCornerRadius)
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
                        .background(WhispPalette.quietFill, in: .capsule)
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
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isLogExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isLogExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

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
            .whispGlassControl(cornerRadius: WhispMetrics.controlCornerRadius)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    showCancelConfirmation = true
                } label: {
                    Label("Отменить обработку", systemImage: "xmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.glass)
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
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Whisp", systemImage: "waveform")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WhispPalette.accent)
                    Text("Новая лекция")
                        .font(.largeTitle.weight(.semibold))
                    Text("Запишите лекцию или импортируйте аудиофайл. Результат можно проверить, отредактировать и сохранить в Obsidian.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WhispGlassSurface(tint: WhispPalette.accent) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Источник записи")
                                    .font(.headline)
                                Text("Проверьте микрофон и системный звук перед стартом")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { model.refreshInputDevices() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Обновить список микрофонов")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Микрофон", systemImage: "mic")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
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
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .whispGlassControl()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Что записывать", systemImage: "waveform")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("Что записывать", selection: $captureMode) {
                                ForEach(CaptureMode.allCases) { mode in
                                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
                            Text(captureMode == .microphone
                                 ? "Записывается только микрофон."
                                 : "Микрофон и звук приложений сохранятся отдельными дорожками.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        WhispGlassDivider()

                        WhispGlassGroup {
                            Button {
                                Task { await model.startRecording(captureSystemAudio: captureMode == .microphoneAndSystem) }
                            } label: {
                                Label("Начать запись", systemImage: "record.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)

                            Button {
                                showAudioImporter = true
                            } label: {
                                Label("Импортировать аудиофайл", systemImage: "waveform.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                        }

                        Text("Можно также перетащить аудиофайлы прямо сюда")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(26)
                }
                .disabled(model.isBusy)
                .dropDestination(for: URL.self) { urls, _ in
                    model.enqueueAudioImports(urls)
                    return true
                }

                Label("Перед отправкой в Obsidian результат можно проверить и отредактировать.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 660)
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
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.subject)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhispPalette.accent)
                    Text(session.title)
                        .font(.title.weight(.bold))
                        .tracking(-0.5)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Label(
                    session.status.title,
                    systemImage: session.status == .synced ? "checkmark.icloud" : "clock"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.surfaceCornerRadius))
            .padding(.horizontal, 18)
            .padding(.top, 18)

            if session.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Конспект ещё не создан",
                    systemImage: "doc.text",
                    description: Text("Выберите лекцию после завершения обработки, чтобы открыть её материалы.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownPreview(markdown: session.notesMarkdown)
            }
        }
        .background(WhispPalette.canvas)
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
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WhispPalette.accent)
                }
                .frame(width: 40, height: 40)
                .glassEffect(
                    .regular.tint(WhispPalette.accent.opacity(0.12)),
                    in: .rect(cornerRadius: WhispMetrics.compactCornerRadius)
                )

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
                    .buttonStyle(.glass)
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
            .glassEffect(.regular.tint(Color.orange.opacity(0.12)), in: .rect(cornerRadius: WhispMetrics.compactCornerRadius))

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
            .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Для подтверждения введите слово **ПЕРЕГЕНЕРИРОВАТЬ**:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("ПЕРЕГЕНЕРИРОВАТЬ", text: $confirmationInput)
                        .whispGlassField()
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
                .buttonStyle(.glassProminent)
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
            .whispGlassControl(cornerRadius: WhispMetrics.controlCornerRadius)

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
                    .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
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
                .buttonStyle(.glass)
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
        .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
    }
}
