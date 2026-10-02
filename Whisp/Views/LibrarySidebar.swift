import SwiftUI

struct LibrarySidebar: View {
    @Bindable var model: AppModel
    @Binding var selectedSubject: String
    @State private var showNoteQueue = false
    @State private var queueSelection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Button { model.showStartScreen() } label: {
                Label("Новая лекция", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WhispActionStyle(prominent: true))
            .controlSize(.large)
            .disabled(model.isRecording)
            .help("Новая запись или импорт · ⌘N")
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Button { model.showTodayDashboard() } label: {
                Label("Сегодня", systemImage: "calendar")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(model.showsToday ? WhispPalette.quietFill : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            .disabled(model.isRecording)

            LibraryBrowser(model: model, selectedSubject: $selectedSubject)
                .disabled(model.isRecording)
            if model.isRestoringFromWebDAV {
                ProgressView(model.statusMessage).font(.caption).padding(12)
            }
            Divider()
            HStack(spacing: 16) {
                SettingsLink { Label("Настройки", systemImage: "gearshape") }
                    .buttonStyle(.plain)
                Spacer()
                Button { showNoteQueue = true } label: {
                    Label("Очередь", systemImage: "text.badge.plus")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showNoteQueue) { noteQueuePanel }
                .disabled(model.isRecording)
            }
            .font(.callout).foregroundStyle(.secondary).padding(16)
        }
        .navigationTitle("Whisp")
    }

    private var noteQueuePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Очередь конспектов").font(.headline)
            if let id = model.activeAnalysisSessionID,
               let session = model.sessions.first(where: { $0.id == id }) {
                Label("Генерируется: \(session.title)", systemImage: "sparkles")
                    .font(.caption)
                Text(model.statusMessage).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(model.queuedAnalysisSessionIDs, id: \.self) { id in
                if let session = model.sessions.first(where: { $0.id == id }) {
                    HStack {
                        Text(WhispFormatting.displayTitle(session.title)).font(.caption).lineLimit(2)
                        Spacer()
                        Button { model.removeQueuedAnalysis(for: id) } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain)
                            .help("Убрать из очереди")
                    }
                }
            }
            Divider()
            Text("Выберите лекции для генерации").font(.subheadline)
            Text("Готовые конспекты выбранных лекций будут перегенерированы.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.sessions.filter { !$0.finalTranscript.isEmpty || !$0.rawTranscript.isEmpty || !$0.attachedImagePaths.isEmpty }) { session in
                        Toggle(WhispFormatting.displayTitle(session.title), isOn: Binding(
                            get: { queueSelection.contains(session.id) },
                            set: { checked in
                                if checked { queueSelection.insert(session.id) }
                                else { queueSelection.remove(session.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .disabled(model.isAnalysisQueued(for: session.id))
                    }
                }
            }
            .frame(height: 230)
            Button("Добавить выбранные (\(queueSelection.count))") {
                for session in model.sessions where queueSelection.contains(session.id) {
                    model.enqueueAnalysis(for: session.id)
                }
                queueSelection.removeAll()
            }
            .buttonStyle(WhispActionStyle(prominent: true))
            .disabled(queueSelection.isEmpty)
        }
        .padding(18)
        .frame(width: 390)
    }

}
