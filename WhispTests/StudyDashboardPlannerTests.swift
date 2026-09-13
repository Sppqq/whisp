import XCTest
@testable import Whisp

final class StudyDashboardPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ru_RU")
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    func testUpcomingLessonsAreSortedAndSkipFinishedLessonToday() {
        let mondayMorning = date(2026, 9, 14, 10)
        let schedule = [
            LessonScheduleEntry(subject: "История", weekday: 3, hour: 9, minute: 30, durationMinutes: 90),
            LessonScheduleEntry(subject: "Математика", weekday: 2, hour: 9, minute: 0, durationMinutes: 90),
            LessonScheduleEntry(subject: "Физика", weekday: 2, hour: 12, minute: 0, durationMinutes: 90)
        ]

        let result = StudyDashboardPlanner.upcomingLessons(
            from: schedule,
            after: mondayMorning,
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.entry.subject), ["Физика", "История", "Математика"])
        XCTAssertEqual(result.first?.date, date(2026, 9, 14, 12))
        XCTAssertEqual(result.last?.date, date(2026, 9, 21, 9))
    }

    func testReviewIntervalsPrioritizeQuestionsMarkedForReview() {
        let now = date(2026, 9, 14, 12)
        var difficult = LectureSession(title: "Сложная тема", quizMarkdown: "## Контрольные вопросы")
        difficult.quizProgress.needsReview = [1]
        difficult.quizProgress.lastStudiedAt = date(2026, 9, 13, 11)

        var completed = LectureSession(title: "Пройденная тема", quizMarkdown: "## Контрольные вопросы")
        completed.quizProgress.answeredCorrectly = [0, 1]
        completed.quizProgress.lastStudiedAt = date(2026, 9, 7, 11)

        var notDue = LectureSession(title: "Ещё рано", quizMarkdown: "## Контрольные вопросы")
        notDue.quizProgress.lastStudiedAt = date(2026, 9, 13, 11)

        let result = StudyDashboardPlanner.reviewSessions(
            from: [completed, notDue, difficult],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.title), ["Сложная тема", "Пройденная тема"])
    }

    @MainActor
    func testReminderForNextLessonIsScheduledOnPreviousEvening() {
        let service = ReminderService(calendar: calendar)
        let lectureDate = date(2026, 9, 14, 10)
        let schedule = [
            LessonScheduleEntry(subject: "История", weekday: 3, hour: 9, minute: 30, durationMinutes: 90)
        ]

        let result = service.resolvedDueDate(
            for: ReminderDraft(title: "Принести карту", notes: "", dueHint: "к следующему уроку"),
            subject: "История",
            after: lectureDate,
            schedule: schedule
        )

        XCTAssertEqual(result, date(2026, 9, 14, 19))
    }

    @MainActor
    func testReminderAfterOneLessonUsesTheFollowingOccurrence() {
        let service = ReminderService(calendar: calendar)
        let lectureDate = date(2026, 9, 14, 10)
        let schedule = [
            LessonScheduleEntry(subject: "История", weekday: 3, hour: 9, minute: 30, durationMinutes: 90)
        ]

        let result = service.resolvedDueDate(
            for: ReminderDraft(title: "Доклад", notes: "", dueHint: "через 1 урок"),
            subject: "История",
            after: lectureDate,
            schedule: schedule
        )

        XCTAssertEqual(result, date(2026, 9, 21, 19))
    }
}
