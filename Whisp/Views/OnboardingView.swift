import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel

    @State private var step = 0
    @State private var geminiKey = ""
    @State private var testMessage = ""
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Whisp", systemImage: "waveform")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WhispPalette.accent)
                Spacer()
                Text("Шаг \(step + 1) из 3")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)

            Group {
                switch step {
                case 0: welcomePage
                case 1: providerPage
                default: audioPage
                }
            }
            .frame(maxWidth: 560, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button("Пропустить настройку") {
                    model.skipOnboarding()
                }
                .buttonStyle(.borderless)

                Spacer()

                if step > 0 {
                    Button("Назад") { step -= 1 }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glass)
                }

                Button(step == 2 ? "Перейти к первой записи" : "Продолжить") {
                    if step == 2 {
                        model.completeOnboarding()
                    } else {
                        if step == 1 {
                            model.settingsStore.geminiAPIKey = geminiKey
                        }
                        step += 1
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.surfaceCornerRadius))
            .padding(18)
        }
        .frame(width: 720, height: 560)
        .background(WhispPalette.canvas)
        .tint(WhispPalette.accent)
        .onAppear {
            geminiKey = model.settingsStore.geminiAPIKey
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(WhispPalette.accent)

            VStack(alignment: .leading, spacing: 10) {
                Text("Лекция превращается в материал для учёбы")
                    .font(.system(size: 30, weight: .semibold))
                Text("Whisp сохранит запись, подготовит расшифровку и поможет быстро проверить главное перед зачётом.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardingFeature("record.circle", "Запись или импорт", "Можно начать с микрофона или готового аудиофайла.")
                onboardingFeature("doc.text.magnifyingglass", "Проверяемый результат", "У каждой реплики есть таймкод, а текст можно исправить вручную.")
                onboardingFeature("graduationcap", "Подготовка к зачёту", "Из лекции можно получить вопросы, карточки и типичные ошибки.")
            }

            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.top, 26)
    }

    private var providerPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text("Подключите расшифровку")
                .font(.system(size: 27, weight: .semibold))
            Text("Для облачной расшифровки нужен ключ активного провайдера. На первом запуске используется Gemini. Ключ хранится локально в выбранном хранилище Whisp.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            if model.settingsStore.usesGemini {
                SecureField("Gemini API key", text: $geminiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: geminiKey) { _, _ in testMessage = "" }

                HStack(spacing: 12) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Проверить подключение", systemImage: "checkmark.shield")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(isTesting || geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !testMessage.isEmpty {
                        Text(testMessage)
                            .font(.caption)
                            .foregroundStyle(testMessage.localizedCaseInsensitiveContains("доступ") || testMessage.localizedCaseInsensitiveContains("работ") ? .green : .secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Label("Активный провайдер: \(model.settingsStore.activeProviderName)", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.callout)
                Text("Для настройки этого провайдера откройте полные настройки после завершения онбординга.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label("Можно продолжить без ключа и использовать локальный fallback, если он доступен.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.top, 52)
    }

    private var audioPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Text("Проверьте источник звука")
                .font(.system(size: 27, weight: .semibold))
            Text("Вы сможете изменить эти параметры позже. Для обычной лекции достаточно микрофона; запись системного звука нужна, если преподаватель или видео звучат через Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Микрофон")
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
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.surfaceCornerRadius))

            Label("Перед отправкой в облако вы увидите и сможете отредактировать результат.", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.top, 52)
    }

    private func onboardingFeature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(WhispPalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        testMessage = "Проверяем…"
        model.settingsStore.geminiAPIKey = geminiKey
        let message = await model.testActiveProvider()
        testMessage = message
        isTesting = false
    }
}
