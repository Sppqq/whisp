import SwiftUI
import AppKit

/// Native macOS visual language for Whisp, following Apple's Human Interface
/// Guidelines for macOS 26/27 (Liquid Glass).
///
/// Rules of the system:
/// - prefer standard components (sidebar `List`, toolbar, `.searchable`,
///   `.glass` / `.glassProminent` buttons) so the system draws Liquid Glass;
/// - glass belongs to navigation and controls, never to lecture text;
/// - the accent is the user's system accent color; state colors (recording,
///   warning, success) are separate and used only for state;
/// - all text uses SF; no custom fonts, eyebrows or decorative tints.
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
    static let controlCornerRadius: CGFloat = 14
    static let surfaceCornerRadius: CGFloat = 18
    static let contentWidth: CGFloat = 760
    static let pagePadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 24
    static let glassFieldHeight: CGFloat = 34
    static let windowMinWidth: CGFloat = 1_080
    static let windowMinHeight: CGFloat = 720
    static let settingsMinWidth: CGFloat = 980
    static let settingsMinHeight: CGFloat = 700
}

enum WhispMotion {
    static let navigation = Animation.snappy(duration: 0.32, extraBounce: 0.04)
    static let content = Animation.easeInOut(duration: 0.24)
    static let control = Animation.snappy(duration: 0.22, extraBounce: 0.02)

    static let contentTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .center)),
        removal: .opacity
    )
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

/// One glass track with a moving selection pill; segments add no glass layers.
struct WhispGlassSegment<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String, icon: String?)]
    var minHeight: CGFloat = 34
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { index in
                    Button { select(index) } label: {
                        Text(options[index].title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if selection == options[index].value {
                                    Capsule().fill(Color.primary.opacity(0.12))
                                        .matchedGeometryEffect(id: "selection", in: thumb)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == options[index].value ? .isSelected : [])
                    .onKeyPress(.leftArrow) { select(max(0, index - 1)); return .handled }
                    .onKeyPress(.rightArrow) { select(min(options.count - 1, index + 1)); return .handled }
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: .capsule)
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                guard isEnabled, !options.isEmpty else { return }
                let width = max(1, geometry.size.width - 6)
                let index = min(options.count - 1, max(0, Int((value.location.x - 3) / width * CGFloat(options.count))))
                select(index)
            })
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(34, minHeight))
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func select(_ index: Int) {
        guard isEnabled, options.indices.contains(index), selection != options[index].value else { return }
        withAnimation(reduceMotion ? nil : WhispMotion.control) { selection = options[index].value }
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

/// Neutral Liquid Glass label for ordinary actions. Accent colors are reserved
/// for state (success, warning, recording) instead of being painted on every
/// clickable control.
struct WhispGlassActionLabel: View {
    let title: String
    let systemImage: String
    var isBusy = false

    var body: some View {
        HStack(spacing: 7) {
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct WhispGlassPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct WhispGlassIconActionLabel: View {
    let systemImage: String
    var foregroundStyle: Color = .primary
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(foregroundStyle)
            .frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: .circle)
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
    /// Content uses a quiet system surface; glass belongs to navigation and controls.
    func whispContentCard(cornerRadius: CGFloat = WhispMetrics.surfaceCornerRadius) -> some View {
        background(WhispPalette.quietFill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(WhispPalette.hairline.opacity(0.6), lineWidth: 0.5)
            }
    }

    /// A quiet, flat container for status and explanatory content.
    ///
    /// Use this when a block contains its own Liquid Glass controls. It keeps
    /// the controls readable without stacking another glass surface behind
    /// them.
    func whispQuietSurface(cornerRadius: CGFloat = WhispMetrics.controlCornerRadius) -> some View {
        background(WhispPalette.quietFill, in: .rect(cornerRadius: cornerRadius))
    }

    func whispGlassPanel(cornerRadius: CGFloat = WhispMetrics.surfaceCornerRadius) -> some View {
        whispContentCard(cornerRadius: cornerRadius)
    }

    func whispInteractiveGlassSurface(cornerRadius: CGFloat = WhispMetrics.controlCornerRadius) -> some View {
        whispQuietSurface(cornerRadius: cornerRadius)
    }

    func whispGlassField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: WhispMetrics.glassFieldHeight)
            .whispQuietSurface()
    }

    /// A multiline field that keeps the native editor background transparent
    /// so it can sit cleanly on top of a Liquid Glass surface.
    func whispGlassEditor(cornerRadius: CGFloat = WhispMetrics.controlCornerRadius) -> some View {
        scrollContentBackground(.hidden)
            .padding(8)
            .whispQuietSurface(cornerRadius: cornerRadius)
    }
}

/// One size, typeface and shape for all ordinary Mac actions.
struct WhispActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassEffect(prominent ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}


/// Page header for dashboard-style screens: SF large title and a secondary line.
struct WhispPageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Section title in the style of System Settings and Reminders.
struct WhispSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}
