import Foundation

final class RecordingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var startDate: Date?
    private var pauseDate: Date?
    private var pausedDuration: TimeInterval = 0

    func start(at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        startDate = date
        pauseDate = nil
        pausedDuration = 0
    }

    func pause(at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        if pauseDate == nil { pauseDate = date }
    }

    func resume(at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        if let pauseDate { pausedDuration += date.timeIntervalSince(pauseDate) }
        self.pauseDate = nil
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let startDate else { return 0 }
        let activeEnd = pauseDate ?? date
        return max(0, activeEnd.timeIntervalSince(startDate) - pausedDuration)
    }
}
