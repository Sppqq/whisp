import SwiftUI

@main
struct WhispApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Whisp", id: "main") {
            MainView(model: model)
                .frame(minWidth: WhispMetrics.windowMinWidth, minHeight: WhispMetrics.windowMinHeight)
                .preferredColorScheme(preferredColorScheme)
                .task { await model.launch() }
        }
        .defaultSize(width: 1_280, height: 820)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: WhispMetrics.settingsMinWidth, minHeight: WhispMetrics.settingsMinHeight)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settingsStore.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
