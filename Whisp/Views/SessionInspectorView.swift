import SwiftUI

struct SessionInspectorView: View {
    @Bindable var model: AppModel

    private var session: LectureSession? { model.displayedSession }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(for: session)
                        statusSection(for: session)
                        audioSection(for: session)
                        syncSection(for: session)
                        actions
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView(
                    "Нет выбранной лекции",
                    systemImage: "sidebar.trailing",
                    description: Text("Выберите лекцию в библиотеке, чтобы увидеть её состояние и действия.")
                )
            }
        }
        .navigationTitle("Инспектор")
        .background(WhispPalette.canvas)
        .buttonStyle(.glass)
    }

    private func header(for session: LectureSession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(session.subject, systemImage: "book.closed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhispPalette.accent)
            Text(session.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusSection(for session: LectureSession) -> some View {
        inspectorSection("Состояние", icon: "circle.dashed") {
            WhispStatusMark(
                color: statusColor(for: session.status),
                title: session.status.title,
                icon: statusIcon(for: session.status)
            )

            if session.hasPendingBackfill {
                Label("Есть фрагменты для проверки", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(WhispPalette.warning)
            }

            if session.userEditedFinal || session.userEditedNotes || session.userEditedStudentNotes {
                Label("Есть ручные правки", systemImage: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let analysis = session.analysis {
                HStack {
                    Text("AI-уверенность")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(analysis.confidence * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
            }
        }
    }

    private func audioSection(for session: LectureSession) -> some View {
        inspectorSection("Аудио", icon: "waveform") {
            inspectorRow("Длительность", value: WhispFormatting.timestamp(session.duration))
            inspectorRow(
                "Источники",
                value: session.captureSystemAudio ? "Микрофон и система" : "Только микрофон"
            )
            inspectorRow("Фрагменты", value: "\(session.audioChunks.count)")
        }
    }

    private func syncSection(for session: LectureSession) -> some View {
        inspectorSection("Синхронизация", icon: "icloud") {
            WhispStatusMark(
                color: model.webDAVState.isAvailable ? WhispPalette.success : .secondary,
                title: model.webDAVState.isAvailable ? "WebDAV доступен" : "WebDAV не проверен",
                icon: model.webDAVState.isAvailable ? "checkmark.icloud" : "icloud"
            )

            if let syncedAt = session.syncedAt {
                inspectorRow("Последняя синхронизация", value: syncedAt.formatted(date: .abbreviated, time: .shortened))
            }

            inspectorRow("Провайдер", value: model.settingsStore.activeProviderName)
        }
    }

    private var actions: some View {
        WhispGlassGroup {
            Button {
                Task { await model.syncCurrent() }
            } label: {
                Label("Сохранить в Obsidian", systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.currentSession == nil || model.currentSession?.status == .processing)

            Button {
                model.openInObsidian()
            } label: {
                Label("Открыть в Obsidian", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Button {
                model.revealInFinder()
            } label: {
                Label("Показать файлы", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.controlCornerRadius))
    }

    private func inspectorRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func statusColor(for status: LectureStatus) -> Color {
        switch status {
        case .synced: WhispPalette.success
        case .failed: .red
        case .awaitingBackfill: WhispPalette.warning
        case .recording, .paused: WhispPalette.recording
        default: WhispPalette.accent
        }
    }

    private func statusIcon(for status: LectureStatus) -> String {
        switch status {
        case .synced: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .processing: "gearshape.2.fill"
        default: "circle.fill"
        }
    }
}
