import SwiftUI

/// What the content column lists. Mirrors the mailbox/folder model of Mail and Notes.
enum LibraryScope: Hashable {
    case today
    case all
    case subject(String)
}

/// Native source-list sidebar: destinations on top, subjects as folders below.
struct LibrarySidebar: View {
    @Bindable var model: AppModel
    @Binding var scope: LibraryScope?

    private var subjects: [(name: String, count: Int)] {
        Dictionary(grouping: model.sessions, by: \.subject)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(selection: $scope) {
            Section {
                Label("Сегодня", systemImage: "sun.max")
                    .tag(LibraryScope.today)
                Label("Все лекции", systemImage: "books.vertical")
                    .badge(model.sessions.count)
                    .tag(LibraryScope.all)
            }
            if !subjects.isEmpty {
                Section("Предметы") {
                    ForEach(subjects, id: \.name) { subject in
                        Label(subject.name, systemImage: "folder")
                            .badge(subject.count)
                            .tag(LibraryScope.subject(subject.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(model.isRecording)
        .safeAreaInset(edge: .bottom) {
            if model.isRestoringFromWebDAV {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.statusMessage).lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Toolbar item for the note-generation queue. Hidden when the queue is empty.
struct NoteQueueToolbarButton: View {
    @Bindable var model: AppModel
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Label("Очередь конспектов", systemImage: "text.badge.plus")
        }
        .badge(model.queuedAnalysisSessionIDs.count + (model.activeAnalysisSessionID == nil ? 0 : 1))
        .help("Очередь конспектов")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { panel }
        .onChange(of: hasQueue) { _, hasQueue in
            if !hasQueue { isPresented = false }
        }
    }

    private var hasQueue: Bool {
        model.activeAnalysisSessionID != nil || !model.queuedAnalysisSessionIDs.isEmpty
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Очередь конспектов").font(.headline)
            if let id = model.activeAnalysisSessionID,
               let session = model.sessions.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(WhispFormatting.displayTitle(session.title), systemImage: "sparkles")
                        .font(.callout.weight(.medium))
                    Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.queuedAnalysisSessionIDs.isEmpty {
                Text("Нет ожидающих лекций").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Ожидают генерации").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(model.queuedAnalysisSessionIDs, id: \.self) { id in
                    if let session = model.sessions.first(where: { $0.id == id }) {
                        HStack {
                            Text(WhispFormatting.displayTitle(session.title)).font(.callout).lineLimit(2)
                            Spacer()
                            Button { model.removeQueuedAnalysis(for: id) } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Убрать из очереди")
                            .accessibilityLabel("Убрать из очереди")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

/// Toolbar item for the cloud upload queue. Hidden when nothing is queued.
struct SyncQueueToolbarButton: View {
    @Bindable var model: AppModel
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Label("Очередь синхронизации", systemImage: "icloud.and.arrow.up")
        }
        .badge(model.syncQueueSessionIDs.count + (model.syncingSessionID == nil ? 0 : 1))
        .help("Очередь синхронизации")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { panel }
        .onChange(of: model.hasSyncQueue) { _, hasQueue in
            if !hasQueue { isPresented = false }
        }
    }

    private func title(for id: UUID) -> String {
        model.sessions.first(where: { $0.id == id }).map { WhispFormatting.displayTitle($0.title) } ?? "Лекция"
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Очередь синхронизации").font(.headline)
            if let id = model.syncingSessionID {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title(for: id), systemImage: "icloud.and.arrow.up")
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    if model.cloudUploadSessionID == id, let progress = model.cloudUploadProgress {
                        if progress.totalFiles > 0 {
                            ProgressView(value: Double(progress.completedFiles), total: Double(progress.totalFiles))
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                        Text(progress.stage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if model.syncQueueSessionIDs.isEmpty {
                Text("Других лекций в очереди нет").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Ожидают загрузки").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(model.syncQueueSessionIDs, id: \.self) { id in
                    HStack {
                        Text(title(for: id)).font(.callout).lineLimit(2)
                        Spacer()
                        Button { model.removeQueuedSync(for: id) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Убрать из очереди")
                        .accessibilityLabel("Убрать из очереди")
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
