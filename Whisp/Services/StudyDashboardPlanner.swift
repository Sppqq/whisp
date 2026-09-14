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
