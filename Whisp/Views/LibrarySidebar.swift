import SwiftUI

struct LibrarySidebar: View {
    @Bindable var model: AppModel
    @Binding var selectedSubject: String
    @State private var showNoteQueue = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Button { model.showTodayDashboard() } label: {
                    WhispDestinationRow(title: "Сегодня", systemImage: "sun.max", isSelected: model.showsToday)
                }
                .buttonStyle(.plain)
                Button { model.showStartScreen() } label: {
                    WhispDestinationRow(
                        title: "Новая лекция",
                        systemImage: "waveform.badge.plus",
                        isSelected: !model.showsToday && !model.showsLibrary && !model.isRecording
                    )
                }
                .buttonStyle(.plain)
                .help("Новая запись или импорт · ⌘N")
            }
            .disabled(model.isRecording)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            WhispSectionLabel(title: "Библиотека", systemImage: "books.vertical", trailing: "\(model.sessions.count)")
                .padding(.horizontal, 22)
                .padding(.top, 10)

            LibraryBrowser(model: model, selectedSubject: $selectedSubject)
                .disabled(model.isRecording)
            if hasNoteQueue {
                Button { showNoteQueue = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Очередь конспектов · \(model.queuedAnalysisSessionIDs.count)", systemImage: "text.badge.plus")
                            .font(.callout.weight(.semibold))
                        if let id = model.activeAnalysisSessionID,
                           let session = model.sessions.first(where: { $0.id == id }) {
                            Text("Генерируется: \(WhispFormatting.displayTitle(session.title))")
                                .font(.caption).lineLimit(2)
                        }
                        Text(model.queuedAnalysisSessionIDs.isEmpty ? "Нет ожидающих лекций" : "Ожидают генерации: \(model.queuedAnalysisSessionIDs.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .whispContentCard(cornerRadius: WhispMetrics.controlCornerRadius)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            if model.isRestoringFromWebDAV {
                ProgressView(model.statusMessage).font(.caption).padding(12)
            }
            HStack(spacing: 16) {
                SettingsLink { Label("Настройки", systemImage: "gearshape") }
                    .buttonStyle(.plain)
                Spacer()
                if hasNoteQueue {
                    Button { showNoteQueue = true } label: {
                        Label("Очередь · \(model.queuedAnalysisSessionIDs.count)", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNoteQueue) { noteQueuePanel }
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: WhispMetrics.controlCornerRadius))
            .padding(10)
        }
        .navigationTitle("Whisp")
        .onChange(of: hasNoteQueue) { _, hasQueue in
            if !hasQueue { showNoteQueue = false }
        }
    }

    private var hasNoteQueue: Bool {
        model.activeAnalysisSessionID != nil || !model.queuedAnalysisSessionIDs.isEmpty
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

        }
        .padding(18)
        .frame(width: 390)
    }

}
