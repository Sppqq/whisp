import AVFoundation
import AudioToolbox
import Combine
import CoreGraphics
import CoreMedia
import CoreAudio
import Foundation
import ScreenCaptureKit

@MainActor
final class AudioCaptureService: NSObject, ObservableObject {
    enum CaptureError: LocalizedError, Equatable {
        case microphoneDenied, screenCaptureDenied, noDisplay, invalidAudioFormat
        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Нет доступа к микрофону"
            case .screenCaptureDenied: "Разрешите Whisp запись экрана и системного звука в настройках macOS, затем перезапустите приложение"
            case .noDisplay: "Не найден дисплей для захвата системного звука"
            case .invalidAudioFormat: "Неподдерживаемый аудиоформат"
            }
        }
    }

    var onSamples: (([Float], AudioSource) -> Void)?
    var onChunk: ((AudioChunk) -> Void)?
    var onError: ((String) -> Void)?
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var microphoneSignalReceived = false
    @Published private(set) var systemSignalReceived = false

    private var engine = AVAudioEngine()
    private let ioQueue = DispatchQueue(label: "app.whisp.audio-writer")
    private var microphoneWriter: AVAudioFile?
    private var systemWriter: AVAudioFile?
    private var stream: SCStream?
    private var streamOutput: SystemAudioOutput?
    private var sessionDirectory: URL?
    private var sessionStartedAt = Date()
    private var pauseBeganAt: Date?
    private var accumulatedPause: TimeInterval = 0
    private var currentChunkStarted: TimeInterval = 0
    private var rotationTimer: Timer?
    private(set) var isPaused = false
    private(set) var capturesSystemAudio = false

    func requestPermissions(systemAudio: Bool) async throws {
        // AVAudioEngine uses AVAudioApplication's TCC permission on macOS.
        // Requesting through AVCaptureDevice can return a denial without
        // presenting the microphone prompt for an audio-engine-only app.
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else { throw CaptureError.microphoneDenied }
        if systemAudio, !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            throw CaptureError.screenCaptureDenied
        }
    }

    func refreshInputDevices() {
        inputDevices = AudioDeviceManager.inputDevices()
    }

    func start(directory: URL, systemAudio: Bool, microphoneID: UInt32?) async throws {
        try await requestPermissions(systemAudio: systemAudio)
        sessionDirectory = directory
        sessionStartedAt = Date()
        pauseBeganAt = nil
        accumulatedPause = 0
        currentChunkStarted = 0
        capturesSystemAudio = systemAudio
        isPaused = false
        microphoneLevel = 0
        systemLevel = 0
        microphoneSignalReceived = false
        systemSignalReceived = false
        refreshInputDevices()
        if let microphoneID,
           inputDevices.contains(where: { $0.id == microphoneID }) {
            try AudioDeviceManager.applyInputDevice(microphoneID, to: engine.inputNode.audioUnit)
        }
        try openMicrophoneWriter()
        try startMicrophone()
        if systemAudio { try await startSystemAudio() }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in try? self?.rotateSegments() }
        }
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pauseBeganAt = Date()
        closeCurrentChunks()
    }

    func resume() throws {
        guard isPaused else { return }
        if let pauseBeganAt { accumulatedPause += Date().timeIntervalSince(pauseBeganAt) }
        pauseBeganAt = nil
        currentChunkStarted = elapsed
        try openMicrophoneWriter()
        isPaused = false
    }

    func stop() async {
        rotationTimer?.invalidate()
        rotationTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let stream { try? await stream.stopCapture() }
        stream = nil
        streamOutput = nil
        closeCurrentChunks()
        engine.reset()
        engine = AVAudioEngine()
        microphoneLevel = 0
        systemLevel = 0
    }

    private var elapsed: TimeInterval {
        let currentPause = pauseBeganAt.map { Date().timeIntervalSince($0) } ?? 0
        return max(0, Date().timeIntervalSince(sessionStartedAt) - accumulatedPause - currentPause)
    }

    private func startMicrophone() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.invalidAudioFormat }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let copy = Self.copy(buffer)
            let normalized = PCMNormalizer.mono16kFloat(from: copy)
            let level = Self.rms(normalized)
            Task { @MainActor in
                guard !self.isPaused else { return }
                do { try self.microphoneWriter?.write(from: copy) }
                catch { self.onError?("Не записывается микрофон: \(error.localizedDescription)") }
                guard !normalized.isEmpty else {
                    self.onError?("Микрофон подключён, но формат аудио не удалось преобразовать")
                    return
                }
                self.microphoneSignalReceived = true
                self.microphoneLevel = level
                self.onSamples?(normalized, .microphone)
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let output = SystemAudioOutput(owner: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: ioQueue)
        try await stream.startCapture()
        self.stream = stream
        self.streamOutput = output
    }

    fileprivate func consumeSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isPaused, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        do {
            if systemWriter == nil, let description = CMSampleBufferGetFormatDescription(sampleBuffer) {
                try openSystemWriter(format: AVAudioFormat(cmAudioFormatDescription: description))
            }
            guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
            let normalized = PCMNormalizer.mono16kFloat(from: buffer)
            let level = Self.rms(normalized)
            Task { @MainActor in
                guard !normalized.isEmpty else {
                    self.onError?("Системный звук подключён, но формат аудио не удалось преобразовать")
                    return
                }
                self.systemSignalReceived = true
                self.systemLevel = level
                self.onSamples?(normalized, .system)
            }
            try systemWriter?.write(from: buffer)
        } catch {
            onError?("Не записывается системный звук: \(error.localizedDescription)")
        }
    }

    private func rotateSegments() throws {
        closeCurrentChunks()
        currentChunkStarted = elapsed
        try openMicrophoneWriter()
    }

    private func openMicrophoneWriter() throws {
        guard let directory = sessionDirectory else { return }
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let url = chunkURL(directory: directory, source: .microphone)
        microphoneWriter = try Self.makeAACFile(url: url, inputFormat: inputFormat, bitrate: 96_000)
    }

    private func openSystemWriter(format: AVAudioFormat?) throws {
        guard let directory = sessionDirectory else { return }
        let fallback = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let url = chunkURL(directory: directory, source: .system)
        systemWriter = try Self.makeAACFile(url: url, inputFormat: format ?? fallback, bitrate: 128_000)
    }

    private func closeCurrentChunks() {
        let end = elapsed
        if let writer = microphoneWriter {
            let path = writer.url.lastPathComponent
            microphoneWriter = nil
            onChunk?(AudioChunk(source: .microphone, start: currentChunkStarted, end: end, relativePath: path))
        }
        if let writer = systemWriter {
            let path = writer.url.lastPathComponent
            systemWriter = nil
            onChunk?(AudioChunk(source: .system, start: currentChunkStarted, end: end, relativePath: path))
        }
    }

    private func chunkURL(directory: URL, source: AudioSource) -> URL {
        let prefix = source == .microphone ? "mic" : "system"
        return directory.appending(path: String(format: "%@-%06d.m4a", prefix, Int(currentChunkStarted)))
    }

    private static func makeAACFile(url: URL, inputFormat: AVAudioFormat, bitrate: Int) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: bitrate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        return try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity)!
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: buffer.audioBufferList)
        )
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(source.count, destination.count) {
            let sourceBuffer = source[index]
            let destinationBuffer = destination[index]
            if let sourceData = sourceBuffer.mData, let destinationData = destinationBuffer.mData {
                memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
            }
        }
        return copy
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return min(1, sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)) * 18)
    }
}

private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    weak var owner: AudioCaptureService?
    init(owner: AudioCaptureService) { self.owner = owner }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        Task { @MainActor [weak owner] in owner?.consumeSystemAudio(sampleBuffer) }
    }
}

enum AudioDeviceManager {
    static func inputDevices() -> [AudioInputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &byteCount) == noErr else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        let readStatus = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, buffer.baseAddress!)
        }
        guard readStatus == noErr else { return [] }

        let defaultID = defaultInputDeviceID()
        return ids.compactMap { id in
            guard inputChannelCount(for: id) > 0 else { return nil }
            return AudioInputDevice(
                id: id,
                name: deviceName(for: id) ?? "Микрофон \(id)",
                isDefault: id == defaultID
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return status == noErr ? id : nil
    }

    static func applyInputDevice(_ id: AudioDeviceID, to audioUnit: AudioUnit?) throws {
        guard let audioUnit else { throw AudioDeviceError.audioUnitUnavailable }
        var mutableID = id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioDeviceError.cannotSelect(status) }
    }

    private static func deviceName(for id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }

    private static func inputChannelCount(for id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

enum AudioDeviceError: LocalizedError {
    case audioUnitUnavailable
    case cannotSelect(OSStatus)

    var errorDescription: String? {
        switch self {
        case .audioUnitUnavailable: "Аудиодвижок микрофона недоступен"
        case .cannotSelect(let status): "Не удалось выбрать микрофон (CoreAudio \(status))"
        }
    }
}
