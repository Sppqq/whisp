import AVFoundation
import Foundation

/// Reads when an audio or video file was recorded.
enum LectureDateResolver {
    /// Creation date from the media metadata, falling back to the file dates.
    ///
    /// File dates from today are ignored: a file copied, downloaded or
    /// AirDropped today gets today's date even if it was recorded earlier, so
    /// the schedule is a better guide in that case.
    static func recordingDate(of url: URL, now: Date = Date(), calendar: Calendar = .current) async -> Date? {
        let asset = AVURLAsset(url: url)
        if let item = try? await asset.load(.creationDate),
           let date = try? await item.load(.dateValue) {
            return date
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        guard let fileDate = [values?.creationDate, values?.contentModificationDate].compactMap({ $0 }).min(),
              fileDate < calendar.startOfDay(for: now) else { return nil }
        return fileDate
    }

    /// The date an imported lecture gets for the chosen option.
    static func resolve(
        _ choice: LectureDateChoice,
        audioURL: URL?,
        schedule: [LessonScheduleEntry],
        now: Date = Date()
    ) async -> (date: Date, suggestion: LectureDateSuggestion?) {
        switch choice {
        case .now:
            return (now, nil)
        case .custom(let date):
            return (date, nil)
        case .automatic:
            let recordingDate: Date?
            if let audioURL { recordingDate = await Self.recordingDate(of: audioURL, now: now) } else { recordingDate = nil }
            let suggestion = StudyDashboardPlanner.suggestedLectureDate(
                recordingDate: recordingDate,
                schedule: schedule,
                now: now
            )
            return (suggestion?.date ?? now, suggestion)
        }
    }
}
