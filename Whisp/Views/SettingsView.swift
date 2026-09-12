import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case provider = "Провайдер"
    case audio = "Звук"
    case schedule = "Расписание"
    case storage = "Хранилище"
    case appearance = "Вид"
    case subjects = "Предметы"
    case hotkeys = "Клавиши"
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

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var store: SettingsStore
    @State private var page: SettingsPage? = .provider
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var geminiKey = ""
    @State private var geminiKeys: [String] = []
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
    @State private var remindersAccessStatus = ""
    @State private var reminderLists: [ReminderService.ReminderListOption] = []

    init(model: AppModel) {
        self._model = Bindable(wrappedValue: model)
        self._store = Bindable(wrappedValue: model.settingsStore)
    }

    private var selectedPage: SettingsPage { page ?? .provider }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Whisp")
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedPage.rawValue)
                            .font(.largeTitle.weight(.semibold))
                        Text(pageSubtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    pageContent
                }
                .padding(30)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(WhispPalette.canvas)
            .navigationTitle("Настройки")
        }
        .navigationSplitViewStyle(.balanced)
        .background(WhispPalette.canvas)
        .tint(WhispPalette.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
            }
        }
        .onAppear {
            geminiKeys = store.geminiAPIKeys
            geminiKey = store.geminiAPIKey
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
                title: "Провайдер расшифровки",
                caption: "Выберите сервис для финальной расшифровки и создания конспектов. Gemini выбран для Live-режима, но его можно заменить.",
                icon: "point.3.connected.trianglepath.dotted"
            ) {
                Picker("Активный провайдер", selection: $store.settings.activeProviderID) {
                    ForEach(ProviderPreset.allCases) { provider in
                        Label(provider == .gemini ? "\(provider.title) (Live и по умолчанию)" : provider.title, systemImage: provider.icon)
                            .tag(provider.rawValue)
                    }
                    ForEach(customProviders) { provider in
                        Text(provider.name.isEmpty ? "Свой провайдер" : provider.name).tag(provider.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .whispGlassControl()

                Label(
                    "Почему Gemini? Сейчас только он поддерживает Live-расшифровку во время записи. Для остальных провайдеров Whisp использует локальный Whisper до финальной обработки.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .whispQuietSurface()

                if !store.usesGemini {
                    Label(
                        "Live-расшифровка доступна только через Gemini; до финальной расшифровки будет работать локальный Whisper.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            activeProviderSettings

            SettingsCard(
                title: "Google Gemini API",
                caption: "Ключи хранятся локально. При исчерпании квоты одного ключа Whisp автоматически переключится на следующий.",
                icon: "key.horizontal"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(geminiKeys.enumerated()), id: \.offset) { index, key in
                        let status = store.status(for: key)
                        HStack(spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(WhispPalette.accent)
                                .frame(width: 28, alignment: .leading)

                            Text(maskKey(key))
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)

                            // Status badge
                            KeyStatusBadge(status: status)

                            WhispGlassGroup {
                                HStack(spacing: 5) {
                                    Button {
                                        Task {
                                            _ = await model.testSingleGeminiKey(key)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.glass)
                                    .foregroundStyle(.secondary)
                                    .help("Проверить этот ключ")

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(key, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.glass)
                                    .foregroundStyle(.secondary)
                                    .help("Скопировать ключ")

                                    Button(role: .destructive) {
                                        if geminiKeys.indices.contains(index) {
                                            geminiKeys.remove(at: index)
                                            saveSecrets()
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.glass)
                                    .foregroundStyle(.secondary)
                                    .disabled(geminiKeys.count <= 1)
                                    .help(geminiKeys.count <= 1 ? "Должен остаться хотя бы один ключ" : "Удалить этот ключ")
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField("Добавить ещё один Gemini API Key...", text: $newKey)
                            .whispGlassField()

                        WhispGlassGroup {
                            HStack(spacing: 8) {
                                Button {
                                    let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    if !geminiKeys.contains(trimmed) {
                                        geminiKeys.append(trimmed)
                                        newKey = ""
                                        saveSecrets()
                                    }
                                } label: {
                                    Label("Добавить", systemImage: "plus")
                                }
                                .buttonStyle(.glass)
                                .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Вставить списком") {
                                    batchKeysText = geminiKeys.joined(separator: "\n")
                                    showBatchPaste = true
                                }
                                .buttonStyle(.glass)
                                .font(.caption)
                            }
                        }
                    }

                    if showBatchPaste {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Вставьте ключи (по одному на строку или через запятую):")
                                .font(.caption2).foregroundStyle(.secondary)
                            TextEditor(text: $batchKeysText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 80)
                                .padding(4)
                                .scrollContentBackground(.hidden)
                                .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
                            WhispGlassGroup {
                                HStack(spacing: 8) {
                                    Button("Применить список") {
                                        let parsed = batchKeysText.components(separatedBy: CharacterSet.newlines)
                                            .flatMap { $0.components(separatedBy: ",") }
                                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            .filter { !$0.isEmpty }
                                        if !parsed.isEmpty {
                                            geminiKeys = parsed
                                            saveSecrets()
                                        }
                                        showBatchPaste = false
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.small)

                                    Button("Отмена") { showBatchPaste = false }
                                        .buttonStyle(.glass)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(10)
                        .whispQuietSurface(cornerRadius: WhispMetrics.compactCornerRadius)
                    }
                }

                Divider()

                HStack {
                    WhispGlassGroup {
                        HStack(spacing: 8) {
                            Button("Сохранить") { saveSecrets() }.buttonStyle(.glassProminent)

                            Button {
                                saveActiveProviderCredentials()
                                Task {
                                    isTestingAll = true
                                    testResult = store.usesGemini
                                        ? await model.testAllGeminiKeys()
                                        : await model.testActiveProvider()
                                    isTestingAll = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if isTestingAll {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise.badge.checkmark")
                                    }
                                    Text(store.usesGemini ? "Проверить все ключи (\(geminiKeys.count))" : "Проверить провайдера")
                                }
                            }
                            .buttonStyle(.glass)
                            .disabled(isTestingAll)
                        }
                    }

                    Spacer()
                    ConnectionMark(state: model.geminiState)
                }
            }

            SettingsCard(
                title: "Свои Gemini-совместимые провайдеры",
                caption: "Укажите базовый URL API без пути /v1beta. Ключи сохраняются отдельно от настроек.",
                icon: "server.rack"
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach($customProviders) { $provider in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                TextField("Название", text: $provider.name)
                                    .whispGlassField()
                                Button(role: .destructive) {
                                    let id = provider.id.uuidString
                                    customProviders.removeAll { $0.id == provider.id }
                                    customProviderKeys[id] = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Удалить провайдера")
                            }
                            TextField("Базовый URL, например https://api.example.com", text: $provider.baseURL)
                                .whispGlassField()
                            HStack {
                                TextField("Модель расшифровки", text: $provider.transcriptionModel)
                                    .whispGlassField()
                                TextField("Модель для конспекта", text: $provider.analysisModel)
                                    .whispGlassField()
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

                    WhispGlassGroup {
                        HStack(spacing: 8) {
                            Button {
                                customProviders.append(CustomProvider())
                            } label: {
                                Label("Добавить провайдера", systemImage: "plus")
                            }
                            .buttonStyle(.glass)

                            Button("Сохранить провайдеров") { saveCustomProviders() }
                                .buttonStyle(.glassProminent)
                        }
                    }
                }
            }

            SettingsCard(title: "Прокси", caption: "Используется для Gemini и совместимых провайдеров. WebDAV идёт напрямую.", icon: "network") {
                Toggle("Использовать прокси", isOn: $store.proxy.isEnabled)
                    .toggleStyle(.switch)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
                    .onChange(of: store.proxy.isEnabled) { _, _ in
                        UserDefaults.standard.set(true, forKey: "proxy_explicitly_configured")
                    }
                HStack {
                    Picker("Тип", selection: $store.proxy.kind) {
                        Text("SOCKS5").tag(ProxyConfiguration.Kind.socks5)
                        Text("HTTP").tag(ProxyConfiguration.Kind.http)
                    }
                    .frame(width: 150)
                    .whispGlassControl()
                    TextField("Хост", text: $store.proxy.host)
                        .whispGlassField()
                    TextField("Порт", value: $store.proxy.port, format: .number.grouping(.never))
                        .frame(width: 92)
                        .whispGlassField()
                }
                HStack {
                    TextField("Логин", text: $store.proxy.username)
                        .whispGlassField()
                    SecureField("Пароль", text: $proxyPassword)
                        .whispGlassField()
                }
            }
        }
    }

    @ViewBuilder private var activeProviderSettings: some View {
        if let provider = store.activeProviderPreset, provider != .gemini {
            SettingsCard(
                title: provider.title,
                caption: provider.requiresAPIKey
                    ? "API key хранится отдельно. URL и модели можно заменить под свой аккаунт."
                    : "Локальный сервис. URL и модели можно настроить под запущенный инстанс.",
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
                        Button("Сохранить провайдера") { saveProviderSettings() }
                            .buttonStyle(.glassProminent)
                        Spacer()
                    }
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
                    .frame(maxWidth: .infinity)
                    .whispGlassControl()
                    Button { model.refreshInputDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.glass)
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
        VStack(spacing: 16) {
            SettingsCard(
                title: "Расписание уроков",
                caption: "Whisp использует ближайший урок как срок для заданий из лекции.",
                icon: "calendar"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Создавать напоминания автоматически", isOn: $store.settings.remindersEnabled)
                        .toggleStyle(.switch)

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
                        .buttonStyle(.glass)
                        if !remindersAccessStatus.isEmpty {
                            Text(remindersAccessStatus)
                                .font(.caption)
                                .foregroundStyle(remindersAccessStatus == "Доступ разрешён" ? WhispPalette.success : .secondary)
                        }
                    }

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
                        .whispGlassControl()
                    }

                    Text("Если в лекции прозвучит конкретное задание — например, «к следующему уроку принести отчёт» — Whisp добавит его в Apple Reminders. Доступ к напоминаниям macOS запросит при первом таком задании.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Выберите предмет и время в нужном дне. Предметы берутся из раздела «Предметы».")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(1...7, id: \.self) { day in
                                scheduleDayColumn(day: day)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func scheduleDayColumn(day: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Calendar.current.weekdaySymbols[(day + 5) % 7])
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    store.settings.lessonSchedule.append(
                        LessonScheduleEntry(subject: model.activeSubjects.first ?? "Новый предмет", weekday: day)
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Добавить урок")
            }

            ForEach($store.settings.lessonSchedule) { entry in
                if entry.wrappedValue.weekday == day {
                    scheduleRow(entry: entry)
                }
            }

            if !store.settings.lessonSchedule.contains(where: { $0.weekday == day }) {
                Text("Нет уроков")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .top)
        .whispQuietSurface()
    }

    private func scheduleRow(entry: Binding<LessonScheduleEntry>) -> some View {
        let subjects = model.activeSubjects.contains(entry.wrappedValue.subject)
            ? model.activeSubjects
            : [entry.wrappedValue.subject] + model.activeSubjects
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Предмет", selection: entry.subject) {
                    ForEach(subjects, id: \.self) { subject in
                        Text(subject).tag(subject)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    store.settings.lessonSchedule.removeAll { $0.id == entry.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                Stepper("\(String(format: "%02d:%02d", entry.wrappedValue.hour, entry.wrappedValue.minute))", value: entry.hour, in: 0...23)
                    .labelsHidden()
                Stepper("Минуты", value: entry.minute, in: 0...59, step: 5)
                    .labelsHidden()
                Stepper("\(entry.wrappedValue.durationMinutes) мин", value: entry.durationMinutes, in: 15...240, step: 15)
                    .labelsHidden()
            }
        }
        .padding(12)
        .whispQuietSurface()
    }

    private var storagePage: some View {
        VStack(spacing: 16) {
            SettingsCard(
                title: "Хранение ключей и паролей",
                caption: "Способ хранения Gemini API key, пароля прокси и пароля WebDAV на этом Mac.",
                icon: "lock.shield"
            ) {
                Picker("Хранилище секретов", selection: Binding(
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
                )) {
                    ForEach(SecretStorageMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)

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
                            Button("Сохранить") { saveSecrets() }.buttonStyle(.glassProminent)
                            Button("Проверить WebDAV") {
                                saveSecrets()
                                Task {
                                    try? await Task.sleep(for: .milliseconds(180))
                                    testResult = await model.testWebDAV()
                                }
                            }
                            .buttonStyle(.glass)
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
                    .buttonStyle(.glass)
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
                            .buttonStyle(.glass)
                            .disabled(model.isBusy)

                            Button {
                                model.revealInFinder()
                            } label: {
                                Label("Открыть папку в Finder", systemImage: "folder")
                            }
                            .buttonStyle(.glass)
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
                Button("Применить") { model.applyHotkeys() }.buttonStyle(.glassProminent)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)

                Picker("Канал обновлений", selection: Binding(
                    get: { model.updateService.updateChannel },
                    set: { model.updateService.updateChannel = $0 }
                )) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)

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
                        .buttonStyle(.glass)
                        .disabled(isUpdateCheckRunning)

                        if case .available(let release) = model.updateService.state {
                            Button {
                                Task { await model.updateService.installUpdate(release) }
                            } label: {
                                Label("Обновить до \(release.version)", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(model.isRecording)

                            Button {
                                Task { await model.updateService.downloadAndOpen(release) }
                            } label: {
                                Label("Скачать DMG вручную", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.glass)
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
                    .buttonStyle(.glass)
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
                    .buttonStyle(.glass)
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
            }
        )
    }

    private var appearancePage: some View {
        SettingsCard(
            title: "Внешний вид",
            caption: "Выберите спокойную светлую или тёмную сцену для работы с лекциями.",
            icon: "circle.lefthalf.filled"
        ) {
            Picker("Тема", selection: $store.settings.appearance) {
                ForEach(WhispAppearance.allCases) { appearance in
                    Label(appearance.title, systemImage: appearance.icon).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)

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
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(WhispPalette.accent)
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
        .whispQuietSurface(cornerRadius: WhispMetrics.surfaceCornerRadius)
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .whispGlassControl(cornerRadius: WhispMetrics.compactCornerRadius)
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
                .buttonStyle(.glass)
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
