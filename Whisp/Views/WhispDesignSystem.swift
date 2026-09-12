import SwiftUI

/// Native macOS 26+ visual language for Whisp.
///
/// Liquid Glass is the shared visual language for navigation, controls and
/// functional surfaces. Long-form lecture text stays on a calm content layer
/// so the material remains legible instead of becoming a wall of reflections.
enum WhispPalette {
    static let accent = Color.accentColor
    static let recording = Color.red
    static let warning = Color.orange
    static let success = Color.green

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let content = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    // Compatibility aliases for secondary surfaces that are being phased out.
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let elevated = content
    static let hairline = Color.primary.opacity(0.12)
    static let quietFill = Color.primary.opacity(0.055)
}

enum WhispMetrics {
    static let compactCornerRadius: CGFloat = 10
    static let controlCornerRadius: CGFloat = 12
    static let surfaceCornerRadius: CGFloat = 16
    static let contentWidth: CGFloat = 760
    static let glassFieldHeight: CGFloat = 34
    static let windowMinWidth: CGFloat = 1_120
    static let windowMinHeight: CGFloat = 720
    static let settingsMinWidth: CGFloat = 1_400
    static let settingsMinHeight: CGFloat = 700
}

struct WhispGlassSurface<Content: View>: View {
    private let tint: Color?
    private let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        if let tint {
            content
                .glassEffect(
                    .regular.tint(tint.opacity(0.12)),
                    in: .rect(cornerRadius: WhispMetrics.surfaceCornerRadius)
                )
        } else {
            content
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: WhispMetrics.surfaceCornerRadius)
                )
        }
    }
}

/// Groups sibling Liquid Glass controls without adding a background of its own.
struct WhispGlassGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            content
        }
    }
}

struct WhispStatusMark: View {
    let color: Color
    let title: String
    var icon: String = "circle.fill"

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
}

struct WhispGlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(WhispPalette.hairline)
            .frame(height: 1)
            .allowsHitTesting(false)
    }
}

extension View {
    /// A quiet, flat container for status and explanatory content.
    ///
    /// Use this when a block contains its own Liquid Glass controls. It keeps
    /// the controls readable without stacking another glass surface behind
    /// them.
    func whispQuietSurface(cornerRadius: CGFloat = WhispMetrics.controlCornerRadius) -> some View {
        background(WhispPalette.quietFill, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(WhispPalette.hairline, lineWidth: 1)
            }
    }

    /// Applies the same interactive Liquid Glass treatment to form controls.
    /// Keeping this in one modifier prevents a mixture of rounded borders,
    /// opaque fills and glass controls across the settings and review flows.
    func whispGlassControl(cornerRadius: CGFloat = WhispMetrics.controlCornerRadius) -> some View {
        glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    /// A plain text field with the app-wide Liquid Glass field treatment.
    func whispGlassField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: WhispMetrics.glassFieldHeight)
            .whispGlassControl()
    }

    /// A multiline field that keeps the native editor background transparent
    /// so it can sit cleanly on top of a Liquid Glass surface.
    func whispGlassEditor(cornerRadius: CGFloat = WhispMetrics.controlCornerRadius) -> some View {
        scrollContentBackground(.hidden)
            .padding(8)
            .whispGlassControl(cornerRadius: cornerRadius)
    }
}
