import SwiftUI

@main
struct WhispApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Whisp", id: "main") {
            MainView(model: model)
                .frame(minWidth: 1_050, minHeight: 680)
                .preferredColorScheme(preferredColorScheme)
                .task { await model.launch() }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model)
                .frame(width: 680, height: 620)
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
