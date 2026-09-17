import AVFoundation
import Foundation

@MainActor
final class MobileAudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
        case .permissionDenied: "Нет доступа к микрофону. Разрешите его в Настройках iPhone."
            case .couldNotStart: "Не удалось начать запись. Проверьте доступ к микрофону и попробуйте ещё раз."
            }
        }
    }

    private var recorder: AVAudioRecorder?

    var isRecording: Bool { recorder?.isRecording == true }
    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    func start(at url: URL) async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw RecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        // Keep the route simple and use the hardware's negotiated format. A
        // fixed AAC sample-rate/channel combination can make AVAudioRecorder
        // fail with OSStatus -50 on some iPhone/Bluetooth routes.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 44_100
        // Speech is mono; keeping the negotiated sample rate avoids the
        // OSStatus -50 route failures seen with fixed hardware formats.
        let channels = 1
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.couldNotStart
        }
        self.recorder = recorder
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
