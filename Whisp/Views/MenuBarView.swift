import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isRecording {
                Text(model.isPaused ? "Пауза" : "Идёт запись").font(.headline)
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                Divider()
                Button(model.isPaused ? "Продолжить" : "Пауза") { Task { await model.pauseOrResume() } }
                Button("Завершить…") { model.showStopConfirmation = true }
            } else {
                Button("Начать запись") { Task { await model.startRecording() } }
            }
            Divider()
            Button("Открыть Whisp") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Выйти") {
                if model.isRecording { model.showStopConfirmation = true; NSApp.activate(ignoringOtherApps: true) }
                else { NSApp.terminate(nil) }
            }
        }.padding(4)
    }
}
