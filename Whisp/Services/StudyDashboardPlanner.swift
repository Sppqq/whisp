import Foundation

struct ScheduledLesson: Identifiable, Hashable, Sendable {
    let entry: LessonScheduleEntry
    let date: Date

    var id: UUID { entry.id }
}

enum StudyDashboardPlanner {
    static func upcomingLessons(
        from schedule: [LessonScheduleEntry],
        after now: Date = Date(),
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [ScheduledLesson] {
        let deadline = calendar.date(byAdding: .day, value: max(1, days), to: now) ?? now

        return schedule.compactMap { entry in
            let occurrence = (0...max(1, days)).compactMap { offset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      calendar.component(.weekday, from: day) == entry.weekday,
                      let candidate = calendar.date(
                        bySettingHour: entry.hour,
                        minute: entry.minute,
                        second: 0,
                        of: day
                      ),
                      candidate >= now,
                      candidate <= deadline else { return nil }
                return candidate
            }.min()

            return occurrence.map { ScheduledLesson(entry: entry, date: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    static func reviewSessions(
        from sessions: [LectureSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LectureSession] {
        sessions
            .filter { !$0.quizMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { nextReviewDate(for: $0, calendar: calendar) <= now }
            .sorted { lhs, rhs in
                let leftNeedsReview = !lhs.quizProgress.needsReview.isEmpty
                let rightNeedsReview = !rhs.quizProgress.needsReview.isEmpty
                if leftNeedsReview != rightNeedsReview { return leftNeedsReview }
                return nextReviewDate(for: lhs, calendar: calendar) < nextReviewDate(for: rhs, calendar: calendar)
            }
    }

    static func nextReviewDate(for session: LectureSession, calendar: Calendar = .current) -> Date {
        guard let lastStudiedAt = session.quizProgress.lastStudiedAt else {
            return .distantPast
        }
        let interval = session.quizProgress.needsReview.isEmpty ? 7 : 1
        return calendar.date(byAdding: .day, value: interval, to: lastStudiedAt) ?? lastStudiedAt
    }
}

/// How the date of an imported lecture is chosen in the import sheet.
enum LectureDateChoice: Hashable, Sendable {
    /// Recording date of the file, matched to the lesson schedule.
    case automatic
    case now
    case custom(Date)
}

/// A past date proposed for an imported lecture.
struct LectureDateSuggestion: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// The audio file was recorded on an earlier day.
        case recordingDate
        /// No recording date; the latest scheduled lesson was on an earlier day.
        case schedule
    }

    let date: Date
    let subject: String?
    let source: Source
}

extension StudyDashboardPlanner {
    /// Suggests an earlier lecture date when material is imported after the day
    /// of the lesson, for example a recording uploaded the next morning.
    ///
    /// - The recording date of the file wins when it is before today; it is
    ///   snapped to the lesson in the schedule that was running at that time.
    /// - Without a usable recording date, the latest scheduled lesson before
    ///   today is proposed, but only when no lesson has started yet today.
    /// - Returns nil when the lecture most likely belongs to today.
    static func suggestedLectureDate(
        recordingDate: Date?,
        schedule: [LessonScheduleEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LectureDateSuggestion? {
        let startOfToday = calendar.startOfDay(for: now)
        let oldestAllowed = calendar.date(byAdding: .day, value: -60, to: startOfToday) ?? startOfToday

        if let recordingDate, recordingDate < startOfToday, recordingDate >= oldestAllowed {
            if let lesson = lesson(around: recordingDate, schedule: schedule, calendar: calendar) {
                return LectureDateSuggestion(date: lesson.date, subject: lesson.entry.subject, source: .recordingDate)
            }
            return LectureDateSuggestion(date: recordingDate, subject: nil, source: .recordingDate)
        }
        if let recordingDate, recordingDate >= startOfToday { return nil }

        let hasStartedLessonToday = schedule.contains { entry in
            guard calendar.component(.weekday, from: now) == entry.weekday,
                  let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: now) else { return false }
            return start <= now
        }
        guard !hasStartedLessonToday,
              let lesson = previousLesson(before: startOfToday, schedule: schedule, calendar: calendar) else { return nil }
        return LectureDateSuggestion(date: lesson.date, subject: lesson.entry.subject, source: .schedule)
    }

    /// The scheduled lesson that was running (with 30 minutes of slack) at `date`.
    static func lesson(
        around date: Date,
        schedule: [LessonScheduleEntry],
        calendar: Calendar = .current
    ) -> ScheduledLesson? {
        let slack: TimeInterval = 30 * 60
        return schedule.compactMap { entry -> ScheduledLesson? in
            guard calendar.component(.weekday, from: date) == entry.weekday,
                  let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: date) else { return nil }
            let end = start.addingTimeInterval(TimeInterval(entry.durationMinutes) * 60)
            guard date >= start.addingTimeInterval(-slack), date <= end.addingTimeInterval(slack) else { return nil }
            return ScheduledLesson(entry: entry, date: start)
        }
        .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// The latest scheduled lesson that started before `date`, within `days` days.
    static func previousLesson(
        before date: Date,
        schedule: [LessonScheduleEntry],
        days: Int = 7,
        calendar: Calendar = .current
    ) -> ScheduledLesson? {
        schedule.compactMap { entry -> ScheduledLesson? in
            (1...max(1, days)).lazy.compactMap { offset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: date),
                      calendar.component(.weekday, from: day) == entry.weekday,
                      let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day),
                      start < date else { return nil }
                return start
            }
            .first
            .map { ScheduledLesson(entry: entry, date: $0) }
        }
        .max { $0.date < $1.date }
    }
}
