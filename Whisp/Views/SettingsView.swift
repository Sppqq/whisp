import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case audio = "Звук"
    case storage = "Хранилище"
    case subjects = "Предметы"
    case hotkeys = "Клавиши"
    case updates = "Обновления"
    var id: Self { self }
    var icon: String {
        switch self {
        case .gemini: "sparkles"
        case .audio: "waveform.badge.mic"
        case .storage: "externaldrive"
        case .subjects: "books.vertical"
        case .hotkeys: "keyboard"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var store: SettingsStore
    @State private var page: SettingsPage = .gemini
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

    init(model: AppModel) {
        self._model = Bindable(wrappedValue: model)
        self._store = Bindable(wrappedValue: model.settingsStore)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Настройки Whisp").font(.title2.weight(.semibold))
                    Text(pageSubtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(appVersionLabel)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isSuccessfulTestResult ? Color.green : Color.red)
                            .lineLimit(2).frame(maxWidth: 260, alignment: .trailing)
                    }
                }
            }.padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 17)

            HStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { page = item; testResult = "" }
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(page == item ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 22).padding(.bottom, 14)

            Divider()
            ScrollView {
                pageContent.padding(26).frame(maxWidth: 660)
            }
        }
        .background(WhispPalette.canvas)
        .tint(WhispPalette.accent)
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
        switch page {
        case .gemini: geminiPage
        case .audio: audioPage
        case .storage: storagePage
        case .subjects: subjectsPage
        case .hotkeys: hotkeysPage
        case .updates: updatesPage
        }
    }

    private var geminiPage: some View {
        VStack(spacing: 16) {
            SettingsCard(
                title: "Провайдер расшифровки",
                caption: "Выберите сервис для финальной расшифровки и создания конспектов.",
                icon: "point.3.connected.trianglepath.dotted"
            ) {
                Picker("Активный провайдер", selection: $store.settings.activeProviderID) {
                    ForEach(ProviderPreset.allCases) { provider in
                        Label(provider == .gemini ? "\(provider.title) (по умолчанию)" : provider.title, systemImage: provider.icon)
                            .tag(provider.rawValue)
                    }
                    ForEach(customProviders) { provider in
                        Text(provider.name.isEmpty ? "Свой провайдер" : provider.name).tag(provider.id.uuidString)
                    }
                }
                .pickerStyle(.menu)

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
                                .background(WhispPalette.canvas, in: RoundedRectangle(cornerRadius: 6))

                            // Status badge
                            KeyStatusBadge(status: status)

                            // Small individual test button
                            Button {
                                Task {
                                    _ = await model.testSingleGeminiKey(key)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Проверить этот ключ")

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(key, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
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
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(geminiKeys.count <= 1)
                            .help(geminiKeys.count <= 1 ? "Должен остаться хотя бы один ключ" : "Удалить этот ключ")
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField("Добавить ещё один Gemini API Key...", text: $newKey)
                            .textFieldStyle(.roundedBorder)

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
                        .buttonStyle(.bordered)
                        .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Вставить списком") {
                            batchKeysText = geminiKeys.joined(separator: "\n")
                            showBatchPaste = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    if showBatchPaste {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Вставьте ключи (по одному на строку или через запятую):")
                                .font(.caption2).foregroundStyle(.secondary)
                            TextEditor(text: $batchKeysText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 80)
                                .padding(4)
                                .background(WhispPalette.canvas, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(WhispPalette.hairline))
                            HStack {
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
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("Отмена") { showBatchPaste = false }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(WhispPalette.canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()

                HStack {
                    Button("Сохранить") { saveSecrets() }.buttonStyle(.borderedProminent)

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
                    .buttonStyle(.bordered)
                    .disabled(isTestingAll)

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
                                    .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    let id = provider.id.uuidString
                                    customProviders.removeAll { $0.id == provider.id }
                                    customProviderKeys[id] = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Удалить провайдера")
                            }
                            TextField("Базовый URL, например https://api.example.com", text: $provider.baseURL)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                TextField("Модель расшифровки", text: $provider.transcriptionModel)
                                TextField("Модель для конспекта", text: $provider.analysisModel)
                            }
                            .textFieldStyle(.roundedBorder)
                            SecureField("API key", text: Binding(
                                get: { customProviderKeys[provider.id.uuidString] ?? "" },
                                set: { customProviderKeys[provider.id.uuidString] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding(12)
                        .background(WhispPalette.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                    }

                    HStack {
                        Button {
                            customProviders.append(CustomProvider())
                        } label: {
                            Label("Добавить провайдера", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        Button("Сохранить провайдеров") { saveCustomProviders() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            SettingsCard(title: "Прокси", caption: "Используется для Gemini и совместимых провайдеров. WebDAV идёт напрямую.", icon: "network") {
                Toggle("Использовать прокси", isOn: $store.proxy.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: store.proxy.isEnabled) { _, _ in
                        UserDefaults.standard.set(true, forKey: "proxy_explicitly_configured")
                    }
                HStack {
                    Picker("Тип", selection: $store.proxy.kind) {
                        Text("SOCKS5").tag(ProxyConfiguration.Kind.socks5)
                        Text("HTTP").tag(ProxyConfiguration.Kind.http)
                    }.frame(width: 150)
                    TextField("Хост", text: $store.proxy.host)
                    TextField("Порт", value: $store.proxy.port, format: .number.grouping(.never)).frame(width: 92)
                }
                HStack {
                    TextField("Логин", text: $store.proxy.username)
                    SecureField("Пароль", text: $proxyPassword)
                }
            }
        }
    }

    @ViewBuilder private var activeProviderSettings: some View {
        if let provider = store.activeProviderPreset, provider != .gemini {
            SettingsCard(
                title: provider.title,
                caption: "API key хранится отдельно. URL и модели можно заменить под свой аккаунт.",
                icon: provider.icon
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Базовый URL API", text: providerConfigurationBinding(provider, keyPath: \.baseURL))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Модель расшифровки", text: providerConfigurationBinding(provider, keyPath: \.transcriptionModel))
                        TextField("Модель для конспекта", text: providerConfigurationBinding(provider, keyPath: \.analysisModel))
                    }
                    .textFieldStyle(.roundedBorder)
                    SecureField("API key", text: providerAPIKeyBinding(provider))
                        .textFieldStyle(.roundedBorder)

                    if provider == .anthropic {
                        Label("Anthropic используется для конспектов; для расшифровки аудио выберите Gemini или OpenAI-совместимый API.", systemImage: "info.circle")
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
                            .buttonStyle(.borderedProminent)
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
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Button { model.refreshInputDevices() } label: { Image(systemName: "arrow.clockwise") }
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

                Label(store.secretStorageMode.description, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "WebDAV", caption: "Папка Obsidian или другое совместимое хранилище.", icon: "icloud") {
                TextField("URL WebDAV", text: $store.webDAV.baseURL).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Корневая папка", text: $store.webDAV.rootFolder)
                    TextField("Логин", text: $store.webDAV.username)
                }
                SecureField("Пароль", text: $webDAVPassword).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Сохранить") { saveSecrets() }.buttonStyle(.borderedProminent)
                    Button("Проверить WebDAV") {
                        saveSecrets()
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            testResult = await model.testWebDAV()
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
                    .buttonStyle(.bordered)
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
                    HStack(spacing: 12) {
                        Button {
                            model.showBatchRegenerateSheet = true
                        } label: {
                            Label("Перегенерировать все конспекты...", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)

                        Button {
                            model.revealInFinder()
                        } label: {
                            Label("Открыть папку в Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var subjectsPage: some View {
        SettingsCard(title: "Предметы", caption: "Gemini выбирает только из включённых дисциплин.", icon: "books.vertical") {
            SubjectsSettingsContent(store: store)
        }
    }

    private var hotkeysPage: some View {
        SettingsCard(title: "Глобальные клавиши", caption: "Работают, даже когда Whisp находится в фоне.", icon: "keyboard") {
            LabeledContent("Старт, пауза, продолжение") { TextField("⌥⌘R", text: $store.settings.hotkeyRecord).frame(width: 150) }
            LabeledContent("Завершение") { TextField("⌥⌘.", text: $store.settings.hotkeyFinish).frame(width: 150) }
            HStack {
                Text("Используйте символы ⌘, ⌥, ⌃, ⇧ и одну клавишу.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Применить") { model.applyHotkeys() }.buttonStyle(.borderedProminent)
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

                Label(model.updateService.updateChannel.description, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Установленная версия") {
                    Text(model.updateService.currentVersion).monospacedDigit()
                }

                updateStatus

                HStack {
                    Button {
                        Task { await model.updateService.checkForUpdates() }
                    } label: {
                        Label("Проверить обновления", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdateCheckRunning)

                    if case .available(let release) = model.updateService.state {
                        Button {
                            Task { await model.updateService.installUpdate(release) }
                        } label: {
                            Label("Обновить до \(release.version)", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRecording)

                        Button {
                            Task { await model.updateService.downloadAndOpen(release) }
                        } label: {
                            Label("Скачать DMG вручную", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
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
                    .buttonStyle(.link)
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
                    .buttonStyle(.link)
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
        switch page {
        case .gemini: "Модели, ключ и сетевое подключение"
        case .audio: "Источники записи"
        case .storage: "Obsidian и локальные файлы"
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
                    .frame(width: 30, height: 30).background(WhispPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(WhispPalette.hairline))
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
            ForEach($store.settings.subjects) { $subject in
                HStack {
                    Toggle("", isOn: $subject.isEnabled).labelsHidden()
                    TextField("Предмет", text: $subject.name)
                    Button(role: .destructive) {
                        store.settings.subjects.removeAll { $0.id == subject.id }
                    } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                TextField("Новый предмет", text: $newSubject)
                Button("Добавить") {
                    let name = newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    store.settings.subjects.append(SubjectItem(name: name, order: store.settings.subjects.count))
                    newSubject = ""
                }.buttonStyle(.bordered)
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
        .background(WhispPalette.canvas.opacity(0.6), in: Capsule())
    }
}
