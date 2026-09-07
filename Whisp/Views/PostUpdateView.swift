import SwiftUI
import Foundation

struct PostUpdateView: View {
    let version: String
    let previousVersion: String
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    changelogSection

                    Text("Как теперь работать с записью")
                        .font(.headline)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        PostUpdateHighlight(
                            icon: "text.quote",
                            title: "Стенограмма",
                            caption: "Готовый текст для чтения",
                            detail: "Реплики объединены, спикеры и таймкоды остаются под рукой. Текст можно править и искать.",
                            tint: WhispPalette.accent
                        )

                        PostUpdateHighlight(
                            icon: "waveform",
                            title: "Сырой звук",
                            caption: "Исходный материал для сверки",
                            detail: "Ближе к аудиопотоку: полезен, чтобы проверить спорное место и быстро перейти к нужной секунде.",
                            tint: .secondary
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Открывайте Стенограмму для работы с текстом", systemImage: "text.alignleft")
                        Label("Открывайте Сырой звук для проверки записи", systemImage: "speaker.wave.2")
                        Label("Переключение находится рядом с плеером", systemImage: "arrow.left.arrow.right")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WhispPalette.quietFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WhispPalette.hairline))
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Понятно") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(18)
        }
        .background(WhispPalette.canvas)
        .tint(WhispPalette.accent)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(WhispPalette.accent)
                .frame(width: 56, height: 56)
                .background(WhispPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("Обновление завершено")
                    .font(.title2.weight(.semibold))
                Text("Whisp \(version) готов к работе")
                    .font(.title3.weight(.medium))
                if !previousVersion.isEmpty {
                    Text("Версия \(previousVersion) → \(version)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var changelogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Полный changelog")
                    .font(.headline)

                Spacer()

                Text("Версия \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if releaseChanges.isEmpty {
                    Text("Полный changelog этой сборки не найден в приложении.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(releaseChanges.indices, id: \.self) { index in
                            let change = releaseChanges[index]
                            PostUpdateChangeRow(change: change)

                            if index < releaseChanges.count - 1 {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WhispPalette.hairline))
        }
    }

    private var releaseChanges: [PostUpdateChange] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return ChangelogParser.changes(for: version, in: markdown)
    }
}

private enum ChangelogParser {
    static func changes(for version: String, in markdown: String) -> [PostUpdateChange] {
        let section = section(for: version, in: markdown) ?? ""
        var category = "Изменения"
        var changes: [PostUpdateChange] = []

        for line in section.split(whereSeparator: \.isNewline) {
            let value = String(line).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("### ") {
                category = String(value.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if value.hasPrefix("- ") {
                let title = String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                changes.append(PostUpdateChange(
                    icon: icon(for: category),
                    category: category,
                    title: title
                ))
            }
        }

        return changes
    }

    private static func section(for version: String, in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        let versionHeader = "## [\(version.trimmingCharacters(in: .whitespacesAndNewlines))]"
        let start = lines.firstIndex { $0.hasPrefix(versionHeader) }
            ?? lines.firstIndex { $0.hasPrefix("## [Unreleased]") }
        guard let start else { return nil }

        let followingLine = start + 1
        let end = followingLine < lines.endIndex
            ? (lines[followingLine...].firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex)
            : lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    private static func icon(for category: String) -> String {
        let normalized = category.lowercased()
        if normalized.contains("добав") { return "plus.circle" }
        if normalized.contains("исправ") { return "checkmark.circle" }
        if normalized.contains("совмест") { return "macwindow" }
        if normalized.contains("провер") { return "checkmark.seal" }
        return "arrow.triangle.2.circlepath"
    }
}

private struct PostUpdateChange: Identifiable {
    let id: String
    let icon: String
    let category: String
    let title: String

    init(icon: String, category: String, title: String) {
        self.id = "\(category)-\(title)"
        self.icon = icon
        self.category = category
        self.title = title
    }
}

private struct PostUpdateChangeRow: View {
    let change: PostUpdateChange

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: change.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WhispPalette.accent)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(change.category.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhispPalette.accent)

                Text(change.title)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

private struct PostUpdateHighlight: View {
    let icon: String
    let title: String
    let caption: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(caption).font(.caption.weight(.medium)).foregroundStyle(tint)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background(WhispPalette.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WhispPalette.hairline))
    }
}
