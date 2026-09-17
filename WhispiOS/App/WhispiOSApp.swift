import SwiftUI

@main
struct WhispiOSApp: App {
    @State private var model = MobileAppModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(model)
                .task { await model.load() }
                .preferredColorScheme(model.preferredColorScheme)
        }
    }
}
