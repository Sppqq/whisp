import SwiftUI

@main
struct WhispApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Whisp", id: "main") {
            MainView(model: model)
                .frame(minWidth: 1_120, minHeight: 720)
                .preferredColorScheme(preferredColorScheme)
                .task { await model.launch() }
        }
        .defaultSize(width: 1_280, height: 820)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model)
                .frame(width: 900, height: 700)
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
