import SwiftUI

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
                    Text("Что изменилось")
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
