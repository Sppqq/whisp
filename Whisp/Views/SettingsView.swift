import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case provider = "AI и конспекты"
    case audio = "Запись"
    case schedule = "Расписание"
    case storage = "Синхронизация"
    case appearance = "Оформление"
    case subjects = "Предметы"
    case hotkeys = "Быстрые команды"
    case updates = "Обновления"
    var id: Self { self }
    var icon: String {
        switch self {
        case .provider: "point.3.connected.trianglepath.dotted"
        case .audio: "waveform.badge.mic"
        case .schedule: "calendar"
        case .storage: "externaldrive"
        case .appearance: "circle.lefthalf.filled"
        case .subjects: "books.vertical"
        case .hotkeys: "keyboard"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

private enum ProviderQuickMode: String, CaseIterable, Identifiable {
    case cloud
    case hybrid
    case local

    var id: Self { self }

    var title: String {
        switch self {
        case .cloud: "Облако"
        case .hybrid: "Гибрид"
        case .local: "Локально"
        }
    }

    var subtitle: String {
        switch self {
        case .cloud: "Gemini для всего"
        case .hybrid: "Whisper + облачный AI"
        case .local: "Whisper + Ollama"
        }
    }

    var icon: String {
        switch self {
        case .cloud: "cloud"
        case .hybrid: "arrow.triangle.branch"
        case .local: "lock.shield"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: SettingsPage? = .provider
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var geminiKey = ""
    @State private var geminiKeys: [String] = []
    @State private var jevAPIKey = ""
    @State private var newKey = ""
    @State private var showBatchPaste = false
    @State private var batchKeysText = ""
    @State private var customProviders: [CustomProvider] = []
    @State private var customProviderKeys: [String: String] = [:]
    @State private var providerConfigurations: [String: ProviderConfiguration] = [:]
    @State private var providerAPIKeys: [String: String] = [:]
    @State private var proxyPassword = ""
    @State private var webDAVPassword = ""
    @State private var testResult = ""
    @State private var isTestingAll = false
    @State private var showProviderDetails = false
    @State private var showGeminiDetails = false
    @State private var showJevDetails = false
    @State private var showCustomProviderDetails = false
    @State private var remindersAccessStatus = ""
    @State private var selectedScheduleDay = Calendar.current.component(.weekday, from: Date())
    @State private var reminderLists: [ReminderService.ReminderListOption] = []

    init(model: AppModel) {
        self._model = Bindable(wrappedValue: model)
        self._store = Bindable(wrappedValue: model.settingsStore)
    }

    private var selectedPage: SettingsPage { page ?? .provider }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $page) {
                Section("Whisp") {
                    ForEach([SettingsPage.provider, .audio, .storage, .appearance]) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                Section("Учёба") {
                    ForEach([SettingsPage.schedule, .subjects]) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                Section("Приложение") {
                    ForEach([SettingsPage.hotkeys, .updates]) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selectedPage.rawValue)
                                .font(.largeTitle.weight(.semibold))
                            Text(pageSubtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(appVersionLabel)
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.secondary)
                                if !testResult.isEmpty {
                                    Text(testResult)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(isSuccessfulTestResult ? WhispPalette.success : .red)
                                        .lineLimit(1)
                                }
                            }

                            Button {
                                dismiss()
                            } label: {
                                Label("Закрыть", systemImage: "xmark")
                            }
                            .buttonStyle(WhispActionStyle())
                            .controlSize(.small)
                            .help("Закрыть настройки")
                            .accessibilityLabel("Закрыть настройки")
                        }
                    }

                    pageContent
                }
                .padding(30)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(WhispPalette.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .background(WhispPalette.canvas)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            columnVisibility = .all
            geminiKeys = store.geminiAPIKeys
            geminiKey = store.geminiAPIKey
            jevAPIKey = store.jevAPIKey
            customProviders = store.customProviders
            customProviderKeys = Dictionary(uniqueKeysWithValues: store.customProviders.map { ($0.id.uuidString, store.customProviderAPIKey(for: $0)) })
            providerConfigurations = Dictionary(uniqueKeysWithValues: ProviderPreset.allCases
                .filter { $0 != .gemini }
                .map { ($0.rawValue, store.configuration(for: $0)) })
            providerAPIKeys = Dictionary(uniqueKeysWithValues: ProviderPreset.allCases
                .filter { $0 != .gemini }
                .map { ($0.rawValue, store.providerAPIKey(for: $0.rawValue)) })
            proxyPassword = store.proxy.password
            webDAVPassword = store.webDAV.password
            model.refreshInputDevices()
        }
        .onChange(of: geminiKeys) { invalidateGeminiStatus() }
        .onChange(of: page) { testResult = "" }
        .onChange(of: store.settings.activeProviderID) {
            invalidateGeminiStatus()
            guard let provider = store.activeProviderPreset, provider != .gemini else { return }
            providerConfigurations[provider.rawValue] = store.configuration(for: provider)
        }
        .onChange(of: proxyPassword) { invalidateGeminiStatus() }
        .onChange(of: store.proxy) { invalidateGeminiStatus() }
        .onChange(of: store.webDAV) { model.webDAVState = .unchecked }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build, !build.isEmpty, build != version else { return "Версия \(version)" }
        return "Версия \(version) (\(build))"
    }

    private var isSuccessfulTestResult: Bool {
        let result = testResult.lowercased()
        return result.contains("доступен")
            || result.contains("сохран")
            || result.contains("перенес")
            || result.contains("работ")
            || result.contains("готов")
    }

    @ViewBuilder private var pageContent: some View {
        switch selectedPage {
        case .provider: providerPage
        case .audio: audioPage
        case .schedule: schedulePage
        case .storage: storagePage
        case .appearance: appearancePage
        case .subjects: subjectsPage
        case .hotkeys: hotkeysPage
        case .updates: updatesPage
        }
    }

    private var providerPage: some View {
        VStack(spacing: 16) {
            SettingsCard(
                title: "Маршрут обработки",
                caption: "Голос и текст могут идти через разные сервисы. Выбор сохраняется сразу и виден в строке статуса ниже.",
                icon: "point.3.connected.trianglepath.dotted"
            ) {
                WhispGlassSegment(
                    selection: Binding<ProviderQuickMode?>(
                        get: { ProviderQuickMode.allCases.first(where: isQuickModeActive) },
                        set: { mode in
                            if let mode { applyQuickMode(mode) }
                        }
                    ),
                    options: ProviderQuickMode.allCases.map { (Optional($0), $0.title, nil) }
                )
                .accessibilityLabel("Маршрут обработки")

                HStack(spacing: 12) {
                    ForEach(ProviderQuickMode.allCases) { mode in
                        Text(mode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    routePicker(
                        title: "Голос → текст",
                        selection: Binding(
                            get: { store.transcriptionProviderID },
                            set: { store.transcriptionProviderID = $0 }
                        ),
                        includeLocalWhisper: true
                    )
                    routePicker(
                        title: "Текст → конспект",
                        selection: Binding(
                            get: { store.analysisProviderID },
                            set: { store.analysisProviderID = $0 }
                        ),
                        includeLocalWhisper: false
                    )
                }

                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Будет использовано")
                            .font(.caption.weight(.semibold))
                        Text("Голос: \(store.transcriptionProviderName) · \(store.transcriptionProviderModel)")
                        Text("Конспект: \(store.analysisProviderName) · \(store.analysisProviderModel)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .whispQuietSurface()

                Label(
                    "Live-режим доступен через Gemini. Если для голоса выбран другой сервис или локальный режим, во время записи используется локальный Whisper.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .whispQuietSurface()

                if store.transcriptionUsesLocalWhisper {
                    Label(
                        "Аудио расшифровывается на этом Mac. Если для конспекта выбран облачный сервис, текст будет отправлен ему.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else if !store.transcriptionProviderID.elementsEqual("gemini") {
                    Label(
                        "Live-расшифровка доступна только через Gemini; до финальной расшифровки будет работать локальный Whisper.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            activeProviderSettings

            DisclosureGroup(isExpanded: $showGeminiDetails) {
                geminiSettingsContent
            } label: {
                Label("Ключи Gemini", systemImage: "key.horizontal")
                    .font(.headline)
                Text(store.geminiAPIKeys.isEmpty ? "Не настроены" : "\(store.geminiAPIKeys.count) ключей сохранено")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(19)
            .whispContentCard()

            DisclosureGroup(isExpanded: $showJevDetails) {
                jevSettingsContent
            } label: {
                Label("Jev-классификация", systemImage: "checklist")
                    .font(.headline)
                Text(store.isJevClassificationConfigured ? "Включена · отдельный ключ OpenRouter" : "Не настроена")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(19)
            .whispContentCard()

            DisclosureGroup(isExpanded: $showCustomProviderDetails) {
                customProvidersContent
            } label: {
                Label("Дополнительные подключения", systemImage: "server.rack")
                    .font(.headline)
                Text(customProviders.isEmpty ? "Добавьте свой API при необходимости" : "\(customProviders.count) подключений")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(19)
            .whispContentCard()

            SettingsCard(title: "Прокси", caption: "Используется для удалённых провайдеров. WebDAV идёт напрямую.", icon: "network") {
                proxySettingsContent
            }
        }
    }

    @ViewBuilder private var jevSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jev работает отдельно от модели конспекта: она делает быстрые структурированные решения, а текст и конспект по-прежнему создаёт выбранная базовая модель.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Отдельный OpenRouter API key для Jev", text: $jevAPIKey)
                .whispGlassField()

            Toggle("Использовать Jev для определения предмета", isOn: $store.settings.jev.classifySubject)
            Toggle("Проверять, есть ли учебное содержание", isOn: $store.settings.jev.checkEducationalContent)
            Toggle("Включить Jev", isOn: $store.settings.jev.isEnabled)

            HStack {
                Text("Уверенность для замены предмета")
                    .font(.caption)
                Slider(value: $store.settings.jev.confidenceThreshold, in: 0.5...0.95, step: 0.05)
                Text("\(Int((store.settings.jev.confidenceThreshold * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 10) {
                TextField("Модель Jev", text: $store.settings.jev.model)
                    .whispGlassField()
                Text("~typesafe/jev-latest")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text("Запросы идут через OpenRouter Decisions API. Ключ хранится отдельно от ключей Gemini и других провайдеров.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Сохранить ключ Jev") { saveJevAPIKey() }
                    .buttonStyle(WhispActionStyle(prominent: true))
                Button {
                    saveJevAPIKey()
                    Task {
                        isTestingAll = true
                        testResult = await model.testJevClassification()
                        isTestingAll = false
                    }
                } label: {
                    Label(isTestingAll ? "Проверяем…" : "Проверить Jev", systemImage: "checkmark.shield")
                }
                .buttonStyle(WhispActionStyle())
                .disabled(isTestingAll || jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder private var geminiSettingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ключи хранятся локально. При исчерпании квоты Whisp переключится на следующий ключ.")
                .font(.caption)
                .foregroundStyle(.secondary)

            geminiModelSettingsContent

            Divider()
            ForEach(Array(geminiKeys.enumerated()), id: \.offset) { index, key in
                let status = store.status(for: key)
                HStack(spacing: 8) {
                    Text("#\(index + 1)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)

                    Text(maskKey(key))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)

                    KeyStatusBadge(status: status)

                    WhispGlassGroup {
                        HStack(spacing: 5) {
                            Button {
                                Task { _ = await model.testSingleGeminiKey(key) }
                            } label: {
                                WhispGlassIconActionLabel(systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .help("Проверить этот ключ")

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(key, forType: .string)
                            } label: {
                                WhispGlassIconActionLabel(systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Скопировать ключ")

                            Button(role: .destructive) {
                                if geminiKeys.indices.contains(index) {
                                    geminiKeys.remove(at: index)
                                    saveSecrets()
                                }
                            } label: {
                                WhispGlassIconActionLabel(systemImage: "trash", foregroundStyle: .red)
                            }
                            .buttonStyle(.plain)
                            .disabled(geminiKeys.count <= 1)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                SecureField("Добавить Gemini API key", text: $newKey)
                    .whispGlassField()
                Button {
                    let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !geminiKeys.contains(trimmed) else { return }
                    geminiKeys.append(trimmed)
                    newKey = ""
                    saveSecrets()
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(WhispActionStyle())
                .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if showBatchPaste {
                VStack(alignment: .leading, spacing: 6) {
                    Text("По одному на строку или через запятую")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextEditor(text: $batchKeysText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 80)
                        .padding(4)
                        .scrollContentBackground(.hidden)
                        .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                    HStack {
                        Button("Применить") {
                            let parsed = batchKeysText.components(separatedBy: CharacterSet.newlines)
                                .flatMap { $0.components(separatedBy: ",") }
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            if !parsed.isEmpty { geminiKeys = parsed; saveSecrets() }
                            showBatchPaste = false
                        }
                        .buttonStyle(WhispActionStyle(prominent: true))
                        Button("Отмена") { showBatchPaste = false }.buttonStyle(WhispActionStyle())
                    }
                }
                .padding(10)
                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
            } else {
                Button("Вставить списком") {
                    batchKeysText = geminiKeys.joined(separator: "\n")
                    showBatchPaste = true
                }
                .buttonStyle(WhispActionStyle())
                .font(.caption)
            }

            Divider()
            HStack {
                Button("Сохранить ключи") { saveSecrets() }.buttonStyle(WhispActionStyle(prominent: true))
                Button {
                    saveSecrets()
                    Task {
                        isTestingAll = true
                        testResult = (store.transcriptionProviderID == "gemini" || store.analysisProviderID == "gemini")
                            ? await model.testAllGeminiKeys()
                            : await model.testActiveProvider()
                        isTestingAll = false
                    }
                } label: {
                    Label(isTestingAll ? "Проверяем…" : "Проверить", systemImage: "checkmark.shield")
                }
                .buttonStyle(WhispActionStyle())
                .disabled(isTestingAll)
                Spacer()
                ConnectionMark(state: model.geminiState)
            }
        }
    }

    private var primaryGeminiModelSelection: Binding<String> {
        Binding(
            get: { store.settings.analysisModel },
            set: { newModel in
                store.selectGeminiAnalysisModel(newModel)
                testResult = "Основная модель: \(newModel)"
            }
        )
    }

    @ViewBuilder private var geminiModelSettingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Модели официального Gemini")
                        .font(.subheadline.weight(.semibold))
                    Text("Выберите основную модель. После трёх неудачных попыток Whisp перейдёт к включённой модели ниже.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Сохраняется сразу")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Основная модель").font(.caption.weight(.semibold))
                if store.settings.geminiAnalysisModels.count <= 4,
                   store.settings.geminiAnalysisModels.allSatisfy({ $0.model.replacingOccurrences(of: "gemini-", with: "").count <= 18 }) {
                    WhispGlassSegment(selection: primaryGeminiModelSelection, options: store.settings.geminiAnalysisModels.map { option in
                        (option.model, option.model.replacingOccurrences(of: "gemini-", with: "").replacingOccurrences(of: "-", with: " "), nil)
                    })
                    .accessibilityLabel("Основная модель Gemini")
                } else {
                    Picker("Основная модель Gemini", selection: primaryGeminiModelSelection) {
                        ForEach(store.settings.geminiAnalysisModels) { option in
                            Text(option.model).tag(option.model)
                        }
                    }
                    .labelsHidden()
                }
            }

            ForEach(Array(store.settings.geminiAnalysisModels.enumerated()), id: \.element.id) { index, option in
                let isPrimary = store.settings.analysisModel == option.model
                HStack(spacing: 8) {
                    Image(systemName: isPrimary ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPrimary ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)

                    Toggle("", isOn: Binding(
                        get: {
                            store.settings.geminiAnalysisModels.first(where: { $0.model == option.model })?.isEnabled ?? false
                        },
                        set: { enabled in
                            store.setGeminiAnalysisModelEnabled(option.model, enabled: enabled)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Использовать модель в цепочке")

                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.model)
                            .font(.system(.body, design: .monospaced))
                        Text(isPrimary ? "Основная" : (option.isEnabled ? "Резервная модель" : "Выключена"))
                            .font(.caption2)
                            .foregroundStyle(isPrimary ? Color.accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.moveGeminiAnalysisModel(option.model, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    .help("Поднять приоритет")

                    Button {
                        store.moveGeminiAnalysisModel(option.model, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == store.settings.geminiAnalysisModels.count - 1)
                    .help("Опустить приоритет")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background {
                    if isPrimary {
                        Color.accentColor.opacity(0.10)
                    } else {
                        Color.clear
                    }
                }
                .clipShape(.rect(cornerRadius: WhispMetrics.compactCornerRadius))
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text("Основная модель запускается первой. Если она успешно ответила, остальные модели не вызываются и платные запросы не расходуются.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Модель расшифровки")
                    .font(.caption.weight(.semibold))
                TextField("Например, gemini-3.5-transcribe", text: $store.settings.geminiModel)
                    .whispGlassField()
                Text("Эта модель используется для финальной расшифровки. Live-модель настраивается отдельно внутри приложения.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
    }

    @ViewBuilder private var customProvidersContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Добавьте OpenAI- или Gemini-совместимый endpoint. URL, модель и ключ сохраняются отдельно для каждого подключения.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach($customProviders) { $provider in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TextField("Название подключения", text: $provider.name).whispGlassField()
                        Button(role: .destructive) {
                            let id = provider.id.uuidString
                            customProviders.removeAll { $0.id == provider.id }
                            customProviderKeys[id] = nil
                            saveCustomProviders()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Базовый URL API", text: $provider.baseURL).whispGlassField()
                    HStack {
                        TextField("Модель расшифровки", text: $provider.transcriptionModel).whispGlassField()
                        TextField("Модель конспекта", text: $provider.analysisModel).whispGlassField()
                    }
                    SecureField("API key", text: Binding(
                        get: { customProviderKeys[provider.id.uuidString] ?? "" },
                        set: { customProviderKeys[provider.id.uuidString] = $0 }
                    ))
                    .whispGlassField()
                }
                .padding(12)
                .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
            }
            HStack {
                Button { customProviders.append(CustomProvider()) } label: {
                    Label("Добавить подключение", systemImage: "plus")
                }
                .buttonStyle(WhispActionStyle())
                Button("Сохранить подключения") { saveCustomProviders() }
                    .buttonStyle(WhispActionStyle(prominent: true))
            }
        }
    }

    @ViewBuilder private var proxySettingsContent: some View {
        Toggle("Использовать прокси", isOn: $store.proxy.isEnabled)
            .toggleStyle(.switch)
            .onChange(of: store.proxy.isEnabled) { _, _ in
                UserDefaults.standard.set(true, forKey: "proxy_explicitly_configured")
            }
        VStack(alignment: .leading, spacing: 6) {
            Text("Тип прокси").font(.caption.weight(.semibold))
            WhispGlassSegment(selection: $store.proxy.kind, options: [
                (ProxyConfiguration.Kind.socks5, "SOCKS5", nil),
                (ProxyConfiguration.Kind.http, "HTTP", nil)
            ])
            .accessibilityLabel("Тип прокси")
        }
        HStack {
            TextField("Хост", text: $store.proxy.host).whispGlassField()
            TextField("Порт", value: $store.proxy.port, format: .number.grouping(.never))
                .frame(width: 92)
                .whispGlassField()
        }
        HStack {
            TextField("Логин", text: $store.proxy.username).whispGlassField()
            SecureField("Пароль", text: $proxyPassword).whispGlassField()
        }
    }

    private func applyQuickMode(_ mode: ProviderQuickMode) {
        switch mode {
        case .cloud:
            store.transcriptionProviderID = ProviderPreset.gemini.rawValue
            store.analysisProviderID = ProviderPreset.gemini.rawValue
        case .hybrid:
            store.transcriptionProviderID = ProviderSelection.localWhisperID
            store.analysisProviderID = ProviderPreset.gemini.rawValue
        case .local:
            store.transcriptionProviderID = ProviderSelection.localWhisperID
            store.analysisProviderID = ProviderPreset.ollama.rawValue
        }
        testResult = "Маршрут сохранён"
        invalidateGeminiStatus()
    }

    private func isQuickModeActive(_ mode: ProviderQuickMode) -> Bool {
        switch mode {
        case .cloud:
            store.transcriptionProviderID == ProviderPreset.gemini.rawValue && store.analysisProviderID == ProviderPreset.gemini.rawValue
        case .hybrid:
            store.transcriptionUsesLocalWhisper && store.analysisProviderID == ProviderPreset.gemini.rawValue
        case .local:
            store.transcriptionUsesLocalWhisper && store.analysisProviderID == ProviderPreset.ollama.rawValue
        }
    }
    @ViewBuilder
    private func routePicker(title: String, selection: Binding<String>, includeLocalWhisper: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            Picker(title, selection: selection) {
                if includeLocalWhisper {
                    Label("Локальный Whisper", systemImage: "cpu").tag(ProviderSelection.localWhisperID)
                }
                ForEach(ProviderPreset.allCases) { provider in
                    Label(provider.title, systemImage: provider.icon).tag(provider.rawValue)
                }
                ForEach(customProviders) { provider in
                    Label(provider.name.isEmpty ? "Свой провайдер" : provider.name, systemImage: "server.rack")
                        .tag(provider.id.uuidString)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var activeProviderSettings: some View {
        DisclosureGroup(isExpanded: $showProviderDetails) {
            VStack(spacing: 12) {
                if let provider = store.analysisProviderPreset, provider != .gemini {
                    providerSettingsCard(provider, roleTitle: "конспекта")
                }
                if let provider = store.transcriptionProviderPreset,
                   provider != .gemini,
                   provider.rawValue != store.analysisProviderID {
                    providerSettingsCard(provider, roleTitle: "расшифровки")
                }
                if store.analysisProviderPreset == .gemini && store.transcriptionProviderPreset == .gemini {
                    Text("Для Gemini дополнительные URL и модели не требуются. Откройте «Ключи Gemini» ниже.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            Label("Параметры выбранных сервисов", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text("URL, модели и ключи")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(19)
        .whispContentCard()
    }

    @ViewBuilder
    private func providerSettingsCard(_ provider: ProviderPreset, roleTitle: String) -> some View {
            SettingsCard(
                title: provider.title,
                caption: provider.requiresAPIKey
                    ? "Провайдер для \(roleTitle). API key хранится отдельно; URL и модели можно заменить под свой аккаунт."
                    : "Локальный сервис для \(roleTitle). URL и модели можно настроить под запущенный инстанс.",
                icon: provider.icon
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Базовый URL API", text: providerConfigurationBinding(provider, keyPath: \.baseURL))
                        .whispGlassField()
                    HStack {
                        if provider.supportsRemoteTranscription {
                            TextField("Модель расшифровки", text: providerConfigurationBinding(provider, keyPath: \.transcriptionModel))
                                .whispGlassField()
                        }
                        TextField("Модель для конспекта", text: providerConfigurationBinding(provider, keyPath: \.analysisModel))
                            .whispGlassField()
                    }

                    SecureField(provider.requiresAPIKey ? "API key" : "API key (необязательно)", text: providerAPIKeyBinding(provider))
                    .whispGlassField()

                    if provider == .anthropic {
                        Label("Anthropic используется для конспектов; для расшифровки аудио выберите Gemini или OpenAI-совместимый API.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if provider == .ollama {
                        Label("Ollama работает локально (по умолчанию http://localhost:11434/v1). API key не требуется. Whisp расшифровывает аудио локальным Whisper, а Ollama строит конспект.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if provider == .lmStudio {
                        Label("LM Studio работает локально (Local Server на http://localhost:1234/v1). API key не требуется. Расшифровка выполняется локальным Whisper, а конспект строит активная модель LM Studio.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if provider == .unsloth {
                        Label("Unsloth работает через OpenAI-совместимый сервер (обычно http://localhost:8000/v1). При локальном запуске API key не требуется.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !provider.supportsLiveTranscription {
                        Label("Во время записи Live-режим доступен только через Gemini; до финальной обработки работает локальный Whisper.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Button("Сохранить настройки") { saveProviderSettings() }
                            .buttonStyle(WhispActionStyle(prominent: true))
                        Spacer()
                    }
                }
            }
    }

    private var audioPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Входной микрофон", caption: "Выбранное устройство используется для новых записей.", icon: "mic") {
                HStack {
                    Picker("Микрофон", selection: Binding(
                        get: { model.selectedMicrophoneID },
                        set: { model.selectedMicrophoneID = $0 }
                    )) {
                        Text("Системный по умолчанию").tag(UInt32?.none)
                        ForEach(model.inputDevices) { device in
                            Text(device.name + (device.isDefault ? " · по умолчанию" : "")).tag(Optional(device.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.refreshInputDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(WhispActionStyle())
                        .help("Обновить устройства")
                }
                if model.inputDevices.isEmpty {
                    Label("Микрофоны не найдены или доступ ещё не выдан", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            SettingsCard(title: "Две дорожки", caption: "Микрофон и звук приложений записываются раздельно.", icon: "square.stack.3d.up") {
                Label("Системный звук можно включать перед каждой новой лекцией.", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var schedulePage: some View {
        VStack(spacing: 18) {
            SettingsCard(title: "Расписание занятий", caption: "Выберите день, затем добавьте предмет и время.", icon: "calendar") {
                scheduleTable
            }
            SettingsCard(title: "Напоминания о заданиях", caption: "Подготовка к следующему занятию — вечером накануне.", icon: "checklist") {
                Toggle("Создавать напоминания автоматически", isOn: $store.settings.remindersEnabled).toggleStyle(.switch)
                DisclosureGroup("Подключение и дополнительные действия") {
                    reminderSettingsDetails.padding(.top, 10)
                }
            }
        }
    }

    private var reminderSettingsDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            Task {
                                do {
                                    let lists = try await model.reminderService.availableLists()
                                    reminderLists = lists
                                    if store.settings.reminderListIdentifier == nil {
                                        store.settings.reminderListIdentifier = lists.first?.id
                                    }
                                    remindersAccessStatus = lists.isEmpty ? "Списки не найдены" : "Доступ разрешён"
                                } catch {
                                    remindersAccessStatus = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("Разрешить доступ к Reminders", systemImage: "checklist")
                        }
                        .buttonStyle(WhispActionStyle())
                        if !remindersAccessStatus.isEmpty {
                            Text(remindersAccessStatus)
                                .font(.caption)
                                .foregroundStyle(remindersAccessStatus == "Доступ разрешён" ? WhispPalette.success : .secondary)
                        }
                    }

                    Button {
                        Task { await model.createRemindersForExistingAnalyses() }
                    } label: {
                        Label(
                            model.isCreatingBatchReminders
                                ? "Добавляем \(model.batchReminderCurrentIndex)/\(model.batchReminderTotalCount)…"
                                : "Проверить готовые разборы и создать напоминания",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(WhispActionStyle())
                    .disabled(model.isCreatingBatchReminders || model.isBusy)

                    Text("Однократно заново проанализирует готовые разборы, найдёт задания и добавит их в выбранный список Reminders. Лекции с уже созданными напоминаниями пропускаются.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !reminderLists.isEmpty {
                        Picker("Список Reminders", selection: Binding(
                            get: { store.settings.reminderListIdentifier },
                            set: { store.settings.reminderListIdentifier = $0 }
                        )) {
                            Text("Системный по умолчанию").tag(String?.none)
                            ForEach(reminderLists) { list in
                                Text(list.title).tag(Optional(list.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("Если в лекции прозвучит конкретное задание — например, «к следующему уроку принести отчёт» — Whisp добавит его в Apple Reminders и напомнит накануне в 19:00. Инструкции, которые нужно выполнять прямо на проверочной, не добавляются.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

        }
    }

    private var scheduleTable: some View {
        VStack(alignment: .leading, spacing: 18) {
            WhispGlassSegment(selection: $selectedScheduleDay, options: [
                (2, "Пн", nil), (3, "Вт", nil), (4, "Ср", nil), (5, "Чт", nil),
                (6, "Пт", nil), (7, "Сб", nil), (1, "Вс", nil)
            ])
            HStack {
                Text(scheduleDayName(selectedScheduleDay)).font(.headline)
                Spacer()
                Button {
                    store.settings.lessonSchedule.append(LessonScheduleEntry(subject: model.activeSubjects.first ?? "Новый предмет", weekday: selectedScheduleDay))
                } label: { Label("Добавить занятие", systemImage: "plus") }
                .buttonStyle(WhispActionStyle()).controlSize(.small)
            }
            scheduleDayColumn(day: selectedScheduleDay)
        }
    }

    private func scheduleDayColumn(day: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($store.settings.lessonSchedule) { entry in
                if entry.wrappedValue.weekday == day {
                    scheduleRow(entry: entry)
                }
            }

            if !store.settings.lessonSchedule.contains(where: { $0.weekday == day }) {
                Text("Нет уроков")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func scheduleRow(entry: Binding<LessonScheduleEntry>) -> some View {
        let entryID = entry.wrappedValue.id
        let subjects = model.activeSubjects.contains(entry.wrappedValue.subject) ? model.activeSubjects : [entry.wrappedValue.subject] + model.activeSubjects
        let durations = Array(Set([45, 60, 75, 90, 105, 120, 135, 150, 180, 240, entry.wrappedValue.durationMinutes])).sorted()
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Предмет", selection: entry.subject) {
                ForEach(subjects, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 18) {
                DatePicker("Начало", selection: scheduleTimeBinding(entry: entry), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                Picker("Длительность", selection: entry.durationMinutes) {
                    ForEach(durations, id: \.self) { Text("\($0) мин").tag($0) }
                }.pickerStyle(.menu)
                Spacer(minLength: 0)
                Button(role: .destructive) { store.settings.lessonSchedule.removeAll { $0.id == entryID } } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless).help("Удалить занятие").accessibilityLabel("Удалить занятие")
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func scheduleTimeBinding(entry: Binding<LessonScheduleEntry>) -> Binding<Date> {
        let calendar = Calendar.current
        return Binding(
            get: {
                calendar.date(from: DateComponents(hour: entry.wrappedValue.hour, minute: entry.wrappedValue.minute)) ?? Date()
            },
            set: { date in
                entry.wrappedValue.hour = calendar.component(.hour, from: date)
                entry.wrappedValue.minute = calendar.component(.minute, from: date)
            }
        )
    }

    private func scheduleDayName(_ day: Int) -> String {
        switch day {
        case 1: "Воскресенье"
        case 2: "Понедельник"
        case 3: "Вторник"
        case 4: "Среда"
        case 5: "Четверг"
        case 6: "Пятница"
        case 7: "Суббота"
        default: "—"
        }
    }

    private var storagePage: some View {
        VStack(spacing: 16) {
            SettingsCard(
                title: "Хранение ключей и паролей",
                caption: "Способ хранения Gemini API key, пароля прокси и пароля WebDAV на этом Mac.",
                icon: "lock.shield"
            ) {
                WhispGlassSegment(selection: Binding(
                    get: { store.secretStorageMode },
                    set: { newMode in
                        do {
                            try store.saveSecrets(
                                geminiKeys: geminiKeys,
                                proxyPassword: proxyPassword,
                                webDAVPassword: webDAVPassword
                            )
                            try store.setSecretStorageMode(newMode)
                            testResult = "Секреты перенесены в «\(newMode.title)»"
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                ), options: SecretStorageMode.allCases.map { mode in
                    (mode, mode.title, mode.icon)
                })

                Label(store.secretStorageMode.description, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "WebDAV", caption: "Папка Obsidian или другое совместимое хранилище.", icon: "icloud") {
                TextField("URL WebDAV", text: $store.webDAV.baseURL).whispGlassField()
                HStack {
                    TextField("Корневая папка", text: $store.webDAV.rootFolder)
                        .whispGlassField()
                    TextField("Логин", text: $store.webDAV.username)
                        .whispGlassField()
                }
                SecureField("Пароль", text: $webDAVPassword).whispGlassField()
                HStack {
                    WhispGlassGroup {
                        HStack(spacing: 8) {
                            Button("Сохранить") { saveSecrets() }.buttonStyle(WhispActionStyle(prominent: true))
                            Button("Проверить WebDAV") {
                                saveSecrets()
                                Task {
                                    try? await Task.sleep(for: .milliseconds(180))
                                    testResult = await model.testWebDAV()
                                }
                            }
                            .buttonStyle(WhispActionStyle())
                        }
                    }
                    Spacer()
                    ConnectionMark(state: model.webDAVState)
                }
                Divider().padding(.vertical, 4)
                HStack(spacing: 12) {
                    Button {
                        Task { await model.restoreFromWebDAV() }
                    } label: {
                        Label(model.isRestoringFromWebDAV ? "Загрузка лекций..." : "Загрузить / Восстановить лекции из WebDAV", systemImage: "icloud.and.arrow.down")
                    }
                    .buttonStyle(WhispActionStyle())
                    .disabled(model.isBusy || store.webDAV.baseURL.isEmpty)

                    if model.isRestoringFromWebDAV {
                        ProgressView().controlSize(.small)
                        Text(model.statusMessage).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsCard(title: "Локальные копии", caption: "Несинхронизированные лекции автоматически не удаляются.", icon: "internaldrive") {
                Stepper("Хранить после синхронизации: \(store.settings.localRetentionDays) дней", value: $store.settings.localRetentionDays, in: 1...365)
            }
            SettingsCard(title: "Управление конспектами", caption: "Массовая перегенерация конспектов через нейросеть.", icon: "sparkles.rectangle.stack") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Если вы изменили модель AI или правила оформления, вы можете заново сгенерировать конспекты для всех сохранённых лекций.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    WhispGlassGroup {
                        HStack(spacing: 12) {
                            Button {
                                model.showBatchRegenerateSheet = true
                            } label: {
                                Label("Перегенерировать все конспекты...", systemImage: "sparkles")
                            }
                            .buttonStyle(WhispActionStyle())
                            .disabled(model.isBusy)

                            Button {
                                model.revealInFinder()
                            } label: {
                                Label("Открыть папку в Finder", systemImage: "folder")
                            }
                            .buttonStyle(WhispActionStyle())
                        }
                    }
                }
            }
        }
    }

    private var subjectsPage: some View {
        SettingsCard(title: "Предметы", caption: "Свои дисциплины используются в AI-классификации, выборе лекции и расписании.", icon: "books.vertical") {
            SubjectsSettingsContent(store: store)
        }
    }

    private var hotkeysPage: some View {
        SettingsCard(title: "Глобальные клавиши", caption: "Работают, даже когда Whisp находится в фоне.", icon: "keyboard") {
            LabeledContent("Старт, пауза, продолжение") {
                TextField("⌥⌘R", text: $store.settings.hotkeyRecord)
                    .frame(width: 150)
                    .whispGlassField()
            }
            LabeledContent("Завершение") {
                TextField("⌥⌘.", text: $store.settings.hotkeyFinish)
                    .frame(width: 150)
                    .whispGlassField()
            }
            HStack {
                Text("Используйте символы ⌘, ⌥, ⌃, ⇧ и одну клавишу.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Применить") { model.applyHotkeys() }.buttonStyle(WhispActionStyle(prominent: true))
            }
        }
    }

    private var updatesPage: some View {
        VStack(spacing: 16) {
            SettingsCard(
                title: "Обновления Whisp",
                caption: "Проверка GitHub Releases и загрузка нового DMG.",
                icon: "arrow.triangle.2.circlepath"
            ) {
                Toggle("Автоматически проверять при запуске", isOn: Binding(
                    get: { model.updateService.automaticallyChecksForUpdates },
                    set: { model.updateService.automaticallyChecksForUpdates = $0 }
                ))
                    .toggleStyle(.switch)

                WhispGlassSegment(selection: Binding(
                    get: { model.updateService.updateChannel },
                    set: { model.updateService.updateChannel = $0 }
                ), options: UpdateChannel.allCases.map { channel in
                    (channel, channel.title, channel == .stable ? "checkmark.seal" : "testtube.2")
                })

                Label(model.updateService.updateChannel.description, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Установленная версия") {
                    Text(model.updateService.currentVersion).monospacedDigit()
                }

                updateStatus

                WhispGlassGroup {
                    HStack(spacing: 8) {
                        Button {
                            Task { await model.updateService.checkForUpdates() }
                        } label: {
                            Label("Проверить обновления", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(WhispActionStyle())
                        .disabled(isUpdateCheckRunning)

                        if case .available(let release) = model.updateService.state {
                            Button {
                                Task { await model.updateService.installUpdate(release) }
                            } label: {
                                Label("Обновить до \(release.version)", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            }
                            .buttonStyle(WhispActionStyle(prominent: true))
                            .disabled(model.isRecording)

                            Button {
                                Task { await model.updateService.downloadAndOpen(release) }
                            } label: {
                                Label("Скачать DMG вручную", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(WhispActionStyle())
                        }
                    }
                }
            }

            SettingsCard(
                title: "Автоматическое обновление",
                caption: "Whisp обновляется в один клик и перезапускается.",
                icon: "sparkles"
            ) {
                Text("При обновлении Whisp автоматически скачивает образ новой версии, аккуратно заменяет приложение в Applications и перезапускается. Все ваши записи, конспекты и настройки сохраняются в неизменном виде.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch model.updateService.state {
        case .idle:
            Label("Обновления ещё не проверялись", systemImage: "minus.circle").foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Проверяем GitHub Releases…") }
        case .upToDate:
            Label("Установлена актуальная версия", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                Label("Доступна версия \(release.version)", systemImage: "sparkles").foregroundStyle(WhispPalette.accent)
                if release.isPrerelease {
                    Text("Предварительная версия").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                if !release.notes.isEmpty {
                    Text(release.notes).font(.caption).foregroundStyle(.secondary).lineLimit(8)
                }
                Button("Открыть страницу релиза") { model.updateService.openReleasePage(release) }
                    .buttonStyle(WhispActionStyle())
            }
        case .downloading(let release):
            VStack(alignment: .leading, spacing: 7) {
                HStack { ProgressView().controlSize(.small); Text("Скачиваем Whisp \(release.version)…") }
                if let total = model.updateService.downloadTotalBytes, total > 0 {
                    ProgressView(value: model.updateService.downloadProgress)
                    Text("\(formattedBytes(model.updateService.downloadedBytes)) из \(formattedBytes(total))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        case .installing(let release):
            HStack { ProgressView().controlSize(.small); Text("Установка и перезапуск Whisp \(release.version)…") }
        case .downloaded(let release, _):
            Label("DMG версии \(release.version) скачан и открыт", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Button("Открыть GitHub Releases") { model.updateService.openReleasesPage() }
                    .buttonStyle(WhispActionStyle())
            }
        }
    }

    private var isUpdateCheckRunning: Bool {
        switch model.updateService.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var pageSubtitle: String {
        switch selectedPage {
        case .provider: "Сервис, ключи и сетевое подключение"
        case .audio: "Источники записи"
        case .schedule: "Дни и время занятий"
        case .storage: "Obsidian и локальные файлы"
        case .appearance: "Светлая, тёмная или системная тема"
        case .subjects: "Список дисциплин для классификации"
        case .hotkeys: "Управление в активном окне Whisp"
        case .updates: "Версия приложения и новые выпуски"
        }
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 12 else { return "••••••••" }
        let prefix = key.prefix(6)
        let suffix = key.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func saveSecrets() {
        do {
            try store.saveSecrets(geminiKeys: geminiKeys, proxyPassword: proxyPassword, webDAVPassword: webDAVPassword)
            let count = geminiKeys.count
            testResult = count > 1 ? "Сохранено (\(count) ключей)" : "Сохранено в Keychain"
            invalidateGeminiStatus()
        } catch { testResult = error.localizedDescription }
    }

    private func saveJevAPIKey() {
        do {
            try store.saveJevAPIKey(jevAPIKey)
            testResult = jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Ключ Jev удалён"
                : "Ключ Jev сохранён отдельно"
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func saveCustomProviders() {
        do {
            try store.saveCustomProviders(customProviders, apiKeys: customProviderKeys)
            testResult = "Провайдеры сохранены"
            invalidateGeminiStatus()
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func providerConfigurationBinding(
        _ provider: ProviderPreset,
        keyPath: WritableKeyPath<ProviderConfiguration, String>
    ) -> Binding<String> {
        Binding(
            get: {
                (providerConfigurations[provider.rawValue] ?? store.configuration(for: provider))[keyPath: keyPath]
            },
            set: { value in
                var configuration = providerConfigurations[provider.rawValue] ?? store.configuration(for: provider)
                configuration[keyPath: keyPath] = value
                providerConfigurations[provider.rawValue] = configuration
                store.setConfiguration(configuration, for: provider)
            }
        )
    }

    private var appearancePage: some View {
        SettingsCard(
            title: "Внешний вид",
            caption: "Выберите спокойную светлую или тёмную сцену для работы с лекциями.",
            icon: "circle.lefthalf.filled"
        ) {
            WhispGlassSegment(
                selection: $store.settings.appearance,
                options: WhispAppearance.allCases.map { appearance in
                    (appearance, appearance.title, appearance.icon)
                }
            )

            Label(
                "Системная тема следует за macOS. Настройка применяется сразу, включая окно настроек.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func providerAPIKeyBinding(_ provider: ProviderPreset) -> Binding<String> {
        Binding(
            get: { providerAPIKeys[provider.rawValue] ?? "" },
            set: { providerAPIKeys[provider.rawValue] = $0 }
        )
    }

    private func saveProviderSettings() {
        do {
            for provider in ProviderPreset.allCases where provider != .gemini {
                if let configuration = providerConfigurations[provider.rawValue] {
                    store.setConfiguration(configuration, for: provider)
                }
            }
            try store.saveProviderAPIKeys(providerAPIKeys)
            testResult = "Провайдер сохранён"
            invalidateGeminiStatus()
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func saveActiveProviderCredentials() {
        if store.usesGemini {
            saveSecrets()
        } else if store.activeProviderPreset != nil {
            saveProviderSettings()
        } else {
            saveCustomProviders()
        }
    }

    private func invalidateGeminiStatus() {
        model.geminiState = .unchecked
        model.proxyState = store.proxy.isEnabled ? .unchecked : .disabled
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let caption: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .whispQuietSurface(cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .whispContentCard()
    }
}

private struct ConnectionMark: View {
    let state: ServiceConnectionState
    var body: some View {
        switch state {
        case .available: Label("Доступно", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .checking: Label("Проверяем", systemImage: "clock").foregroundStyle(.orange)
        case .unavailable: Label("Недоступно", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .local: Label("Локально", systemImage: "cpu").foregroundStyle(.green)
        case .unchecked: Label("Не проверено", systemImage: "minus.circle").foregroundStyle(.secondary)
        case .disabled: Label("Выключено", systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

private struct SubjectsSettingsContent: View {
    @Bindable var store: SettingsStore
    @State private var newSubject = ""
    var body: some View {
        VStack(spacing: 10) {
            Text("Оставьте переключатель включённым, чтобы Whisp предлагал предмет при анализе лекций.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach($store.settings.subjects) { $subject in
                HStack {
                    Toggle("", isOn: $subject.isEnabled)
                        .labelsHidden()
                    TextField("Предмет", text: $subject.name)
                        .whispGlassField()
                    Button(role: .destructive) {
                        store.settings.subjects.removeAll { $0.id == subject.id }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                TextField("Новый предмет", text: $newSubject)
                    .whispGlassField()
                Button("Добавить свой предмет") {
                    let name = newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty,
                          !store.settings.subjects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
                    store.settings.subjects.append(SubjectItem(name: name, order: store.settings.subjects.count))
                    newSubject = ""
                }
                .buttonStyle(WhispActionStyle())
                .disabled(newSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct KeyStatusBadge: View {
    let status: GeminiKeyStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .unchecked:
                Image(systemName: "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("Не проверен")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView()
                    .controlSize(.mini)
                Text("Проверка...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("Работает")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            case .quotaExceeded(let message):
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text("Квота")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .help(message)
            case .invalid(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                Text("Ошибка")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
                    .help(message)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(WhispPalette.quietFill, in: .capsule)
    }
}
