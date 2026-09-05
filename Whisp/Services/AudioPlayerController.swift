import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioPlayerController {
    private var player: AVPlayer?
    private var observer: Any?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var loadedURL: URL?
    var playbackRate: Float = 1.0

    static let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    func load(_ url: URL) {
        if loadedURL == url { return }
        removeObserver()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        loadedURL = url
        currentTime = 0
        duration = 0
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = max(0, time.seconds)
                if let itemDuration = self.player?.currentItem?.duration.seconds, itemDuration.isFinite {
                    self.duration = itemDuration
                }
                self.isPlaying = (self.player?.rate ?? 0) > 0
            }
        }
    }

    func play() {
        guard let player else { return }
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }

    func cycleRate() {
        let current = playbackRate
        let next: Float
        switch current {
        case ..<1.0: next = 1.0
        case 1.0..<1.25: next = 1.25
        case 1.25..<1.5: next = 1.5
        case 1.5..<1.75: next = 1.75
        case 1.75..<2.0: next = 2.0
        default: next = 1.0
        }
        setRate(next)
    }

    func skip(by seconds: TimeInterval) {
        let target = max(0, min(duration > 0 ? duration : Double.greatestFiniteMagnitude, currentTime + seconds))
        seek(to: target)
    }

    func seek(to seconds: TimeInterval) {
        let targetTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        if isPlaying {
            player?.rate = playbackRate
        }
    }

    func stop() {
        player?.pause()
        isPlaying = false
        seek(to: 0)
    }

    private func removeObserver() {
        if let observer, let player { player.removeTimeObserver(observer) }
        observer = nil
    }
}
