import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LectureImportSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var audioURLs: [URL]
    @State private var imageURLs: [URL] = []
    @State private var textURLs: [URL] = []
    @State private var pastedText = ""
    @State private var showTextFilePicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showMoreAudioPicker = false
    @State private var showImageFilePicker = false
    @State private var combinesAudio = true
    @State private var errorMessage: String?
    @State private var isLoadingPhotos = false

    let isAttachment: Bool
    let existingImageCount: Int
    private var photoLimit: Int { max(0, 10 - existingImageCount) }

    let onImport: ([URL], [URL], Bool, String, [URL]) -> Void

    init(
        initialAudioURLs: [URL],
        initialImageURLs: [URL] = [],
        initialTextURLs: [URL] = [],
        isAttachment: Bool = false,
        existingImageCount: Int = 0,
        onImport: @escaping ([URL], [URL], Bool, String, [URL]) -> Void
    ) {
        _audioURLs = State(initialValue: initialAudioURLs)
        _imageURLs = State(initialValue: initialImageURLs)
        _textURLs = State(initialValue: initialTextURLs)
        self.isAttachment = isAttachment
        self.existingImageCount = existingImageCount
        self.onImport = onImport
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isAttachment ? "Добавить материалы" : "Материалы лекции")
                        .font(.title2.weight(.semibold))
                    Text("Добавьте аудио, видео, фото и текст — вместе или по отдельности. Из видео используется звуковая дорожка.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Аудио и видео · \(audioURLs.count)") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(audioURLs.enumerated()), id: \.offset) { _, url in
                            HStack {
                                Label(url.lastPathComponent, systemImage: "waveform").lineLimit(1)
                                Spacer()
                                Button { audioURLs.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).accessibilityLabel("Убрать файл \(url.lastPathComponent)")
                            }.font(.callout)
                        }
                        Button {
                            showMoreAudioPicker = true
                        } label: {
                            Label("Добавить аудио или видео", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Фото · \(imageURLs.count) из \(photoLimit)") {
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
                            .disabled(imageURLs.count >= photoLimit || isLoadingPhotos)

                            PhotosPicker(
                                selection: $selectedPhotos,
                                maxSelectionCount: max(1, photoLimit - imageURLs.count),
                                matching: .images
                            ) {
                                Label("Из галереи", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(imageURLs.count >= photoLimit || isLoadingPhotos)
                        }
                        if imageURLs.isEmpty {
                            Text("Фото можно не добавлять.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if imageURLs.count > photoLimit {
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

                GroupBox("Текст") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(textURLs.enumerated()), id: \.offset) { _, url in
                            HStack {
                                Label(url.lastPathComponent, systemImage: "doc.text").lineLimit(1)
                                Spacer()
                                Button { textURLs.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).accessibilityLabel("Убрать файл \(url.lastPathComponent)")
                            }.font(.callout)
                        }
                        Button { showTextFilePicker = true } label: { Label("Добавить TXT или Markdown", systemImage: "plus") }
                            .buttonStyle(.borderless)
                        Text("Вставьте текст лекции, заметки или расшифровку.").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $pastedText)
                            .font(.body)
                            .frame(minHeight: 130, maxHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.quaternary, in: .rect(cornerRadius: 8))
                            .accessibilityLabel("Текст лекции")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                if audioURLs.isEmpty {
                    Text("Материалы будут использованы при создании конспекта.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if audioURLs.count > 1 && !isAttachment {
                    Picker("Аудио и видео", selection: $combinesAudio) {
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
                        onImport(audioURLs, imageURLs, combinesAudio, pastedText, textURLs)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((audioURLs.isEmpty && imageURLs.isEmpty && textURLs.isEmpty && pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || imageURLs.count > photoLimit || isLoadingPhotos)
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
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let unique = urls.filter { url in
                    LectureImportContent.isMedia(url)
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
                guard imageURLs.count + unique.count <= photoLimit else {
                    errorMessage = "К одной лекции можно добавить не более 10 фото."
                    return
                }
                imageURLs.append(contentsOf: unique)
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showTextFilePicker, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                textURLs.append(contentsOf: urls.filter { LectureImportContent.isText($0) && !textURLs.contains($0) })
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await addGalleryPhotos(items) }
        }
    }

    private var createButtonTitle: String {
        if isAttachment { return "Добавить в лекцию" }
        if audioURLs.isEmpty { return "Создать конспект" }
        return audioURLs.count > 1 && !combinesAudio ? "Создать уроки" : "Создать конспект"
    }

    @MainActor
    private func addGalleryPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        errorMessage = nil
        defer { isLoadingPhotos = false }
        defer { selectedPhotos = [] }
        for item in items {
            guard imageURLs.count < photoLimit else {
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
