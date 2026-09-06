import SwiftUI

struct RecordingView: View {
    @Bindable var model: AppModel
    @State private var followsTranscript = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var capture: AudioCaptureService

    init(model: AppModel) {
        self._model = Bindable(wrappedValue: model)
        self._capture = ObservedObject(wrappedValue: model.audioCapture)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack {
                Text("Живая расшифровка").font(.headline)
                Spacer()
                Toggle("Следить за текстом", isOn: $followsTranscript)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Выключите, чтобы читать предыдущие реплики без автоматической прокрутки")
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)
            transcript
            controlDock
        }
        .background(WhispPalette.canvas)
    }

    private var header: some View {
        HStack(spacing: 16) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .help("Настройки")

            HStack(spacing: 10) {
                Circle()
                    .fill(model.isPaused ? Color.orange : WhispPalette.accent)
                    .frame(width: 9, height: 9)
                    .shadow(color: (model.isPaused ? Color.orange : WhispPalette.accent).opacity(0.45), radius: 5)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(WhispFormatting.timestamp(model.currentSession?.duration ?? 0))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit().tracking(-0.6)
                }
            }

            Spacer()

            RecordingStatePill(model: model)
        }
        .padding(.horizontal, 24).padding(.vertical, 17)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.currentSession?.rawTranscript ?? []) { segment in
                        HStack(alignment: .top, spacing: 16) {
                            Text(WhispFormatting.timestamp(segment.start))
                                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                .frame(width: 46, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(segment.text)
                                    .font(.system(size: 18, weight: .regular))
                                    .lineSpacing(4).textSelection(.enabled)
                                if segment.source == .whisperFallback {
                                    Label("локальная расшифровка", systemImage: "cpu")
                                        .font(.caption2.weight(.medium)).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 30)
                        }
                        .id(segment.id)
                        .transition(.offset(y: 12).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 42).padding(.vertical, 36)
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: model.currentSession?.rawTranscript.count)
            }
            .onChange(of: followsTranscript) { _, follows in
                if follows, let id = model.currentSession?.rawTranscript.last?.id {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.currentSession?.rawTranscript.count) {
                if followsTranscript, let id = model.currentSession?.rawTranscript.last?.id {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: 920)
        .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WhispPalette.hairline))
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 14)
        .overlay {
            if model.currentSession?.rawTranscript.isEmpty == true { listeningState }
        }
    }

    private var listeningState: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle().fill(WhispPalette.accent.opacity(0.09)).frame(width: 74, height: 74)
                Image(systemName: "waveform").font(.system(size: 27, weight: .light)).foregroundStyle(WhispPalette.accent)
            }
            Text(model.isPaused ? "Запись на паузе" : "Слушаю лекцию")
                .font(.title3.weight(.semibold))
            Text(model.isPaused ? "Нажмите «Продолжить», когда будете готовы." : "Завершённые реплики появятся здесь после паузы говорящего.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 390)
        }
    }

    private var controlDock: some View {
        VStack(spacing: 15) {
            HStack(spacing: 22) {
                LevelMeter(
                    value: capture.microphoneLevel,
                    label: selectedMicrophoneName,
                    icon: "mic.fill",
                    receiving: capture.microphoneSignalReceived
                )
                if model.currentSession?.captureSystemAudio == true {
                    LevelMeter(
                        value: capture.systemLevel,
                        label: "Системный звук",
                        icon: "speaker.wave.2.fill",
                        receiving: capture.systemSignalReceived
                    )
                }
            }

            HStack(spacing: 10) {
                Button { Task { await model.pauseOrResume() } } label: {
                    Label(model.isPaused ? "Продолжить" : "Пауза", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 102)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(WhispPalette.accent)

                Button(role: .destructive) { model.showStopConfirmation = true } label: {
                    Label("Завершить", systemImage: "stop.fill").frame(minWidth: 102)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
            Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 26).padding(.top, 15).padding(.bottom, 17)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private var selectedMicrophoneName: String {
        guard let id = model.selectedMicrophoneID,
              let device = model.inputDevices.first(where: { $0.id == id }) else { return "Микрофон" }
        return device.name
    }
}

private struct RecordingStatePill: View {
    let model: AppModel

    private var title: String {
        if model.isPaused { return "Запись на паузе" }
        if model.whisperState == .local { return "Локальная расшифровка" }
        if !model.geminiState.isAvailable { return "Запись без Gemini" }
        return "Запись идёт"
    }

    private var color: Color {
        if model.isPaused { return .orange }
        if model.whisperState == .local || !model.geminiState.isAvailable { return .orange }
        return WhispPalette.accent
    }

    var body: some View {
        Menu {
            Section("Состояние сервисов") {
                ServiceStateRow(title: "Gemini", icon: "sparkles", state: model.geminiState)
                ServiceStateRow(title: "Whisper", icon: "cpu", state: model.whisperState)
                ServiceStateRow(title: "Прокси", icon: "network", state: model.settingsStore.proxy.isEnabled ? model.proxyState : .disabled)
                ServiceStateRow(title: "WebDAV", icon: "icloud", state: model.webDAVState)
            }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .help("Открыть состояние Gemini, Whisper, прокси и WebDAV")
    }
}

private struct ServiceStateRow: View {
    let title: String
    let icon: String
    let state: ServiceConnectionState

    private var color: Color {
        switch state {
        case .available, .local: .green
        case .unavailable: .red
        case .checking: .orange
        case .unchecked, .disabled: .secondary
        }
    }

    private var hint: String {
        switch state {
        case .available: "Доступно"
        case .local: "Работает локально"
        case .checking: "Подключение"
        case .unavailable(let reason): "Недоступно: \(reason)"
        case .unchecked: "Не проверено"
        case .disabled: "Выключено"
        }
    }

    var body: some View {
        Label {
            Text("\(title): \(hint)")
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }
}

private struct LevelMeter: View {
    let value: Float
    let label: String
    let icon: String
    let receiving: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: receiving ? icon : "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(receiving ? Color.secondary : Color.red)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 110, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.08)).overlay(alignment: .leading) {
                    Capsule()
                        .fill(value > 0.82 ? Color.red : WhispPalette.accent)
                        .frame(width: max(3, geometry.size.width * CGFloat(value)))
                        .animation(.linear(duration: 0.08), value: value)
                }
            }.frame(width: 112, height: 5)
        }
        .help(receiving ? "Аудиопоток поступает" : "От устройства ещё не получен аудиопоток")
    }
}
