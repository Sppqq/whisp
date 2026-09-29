import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LectureImportSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var audioURLs: [URL]
    @State private var imageURLs: [URL] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showMoreAudioPicker = false
    @State private var showImageFilePicker = false
    @State private var combinesAudio = true
    @State private var errorMessage: String?
    @State private var isLoadingPhotos = false

    let onImport: ([URL], [URL], Bool) -> Void

    init(
        initialAudioURLs: [URL],
        initialImageURLs: [URL] = [],
        onImport: @escaping ([URL], [URL], Bool) -> Void
    ) {
        _audioURLs = State(initialValue: initialAudioURLs)
        _imageURLs = State(initialValue: initialImageURLs)
        self.onImport = onImport
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Материалы лекции")
                        .font(.title2.weight(.semibold))
                    Text("Выберите несколько аудио и фото вместе или добавьте конспект только по фотографиям.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Аудио · \(audioURLs.count)") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(audioURLs.enumerated()), id: \.offset) { _, url in
                            Label(url.lastPathComponent, systemImage: "waveform")
                                .lineLimit(1)
                                .font(.callout)
                        }
                        Button {
                            showMoreAudioPicker = true
                        } label: {
                            Label("Добавить ещё аудио", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Фото · \(imageURLs.count) из 10") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(imageURLs.enumerated()), id: \.offset) { _, url in
                            HStack {
                                Label(url.lastPathComponent, systemImage: "photo")
                                    .lineLimit(1)
                                    .font(.callout)
                                Spacer()
                                Button {
                                    LectureImportStaging.cleanup([url])
                                    imageURLs.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Убрать фото \(url.lastPathComponent)")
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                showImageFilePicker = true
                            } label: {
                                Label("Из файлов", systemImage: "folder")
                            }
                            .buttonStyle(.borderless)
                            .disabled(imageURLs.count >= 10 || isLoadingPhotos)

                            PhotosPicker(
                                selection: $selectedPhotos,
                                maxSelectionCount: max(1, 10 - imageURLs.count),
                                matching: .images
                            ) {
                                Label("Из галереи", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(imageURLs.count >= 10 || isLoadingPhotos)
                        }
                        if imageURLs.isEmpty {
                            Text("Фото можно не добавлять.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if imageURLs.count > 10 {
                            Text("Уберите лишние фото — максимум 10 на урок.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if isLoadingPhotos {
                            ProgressView("Добавляем фото из галереи…")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if audioURLs.isEmpty {
                    Text("Аудио не выбрано — конспект будет составлен только по фото.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if audioURLs.count > 1 {
                    Picker("Аудио", selection: $combinesAudio) {
                        Text("Один общий урок").tag(true)
                        Text("Отдельные уроки").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(combinesAudio
                         ? "Аудиозаписи будут соединены по порядку в один урок."
                         : "Для каждого аудиофайла создастся отдельный урок.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Отмена", role: .cancel) {
                        LectureImportStaging.cleanup(imageURLs)
                        dismiss()
                    }
                    Spacer()
                    Button(createButtonTitle) {
                        onImport(audioURLs, imageURLs, combinesAudio)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((audioURLs.isEmpty && imageURLs.isEmpty) || imageURLs.count > 10 || isLoadingPhotos)
                }
            }
            .padding(24)
            #if os(macOS)
            .frame(minWidth: 400, idealWidth: 520, maxWidth: 620)
            #else
            .frame(maxWidth: 620)
            #endif
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
        .fileImporter(
            isPresented: $showMoreAudioPicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let unique = urls.filter { url in
                    UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
                        && !audioURLs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL })
                }
                audioURLs.append(contentsOf: unique)
                errorMessage = unique.isEmpty ? "Новые аудиофайлы не выбраны." : nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showImageFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let unique = urls.filter { url in
                    UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
                        && !imageURLs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL })
                }
                guard imageURLs.count + unique.count <= 10 else {
                    errorMessage = "К одной лекции можно добавить не более 10 фото."
                    return
                }
                imageURLs.append(contentsOf: unique)
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await addGalleryPhotos(items) }
        }
    }

    private var createButtonTitle: String {
        if audioURLs.isEmpty { return "Создать конспект по фото" }
        return audioURLs.count > 1 && !combinesAudio ? "Создать уроки" : "Создать конспект"
    }

    @MainActor
    private func addGalleryPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        errorMessage = nil
        defer { isLoadingPhotos = false }
        defer { selectedPhotos = [] }
        for item in items {
            guard imageURLs.count < 10 else {
                errorMessage = "К одной лекции можно добавить не более 10 фото."
                return
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "Не удалось прочитать выбранное фото из галереи."
                    continue
                }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let url = try LectureImportStaging.writePhoto(
                    data,
                    filename: "Фото-\(UUID().uuidString).\(ext)"
                )
                imageURLs.append(url)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
