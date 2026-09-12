import EventKit
import Foundation

@MainActor
final class ReminderService {
    private let store = EKEventStore()

    struct ReminderListOption: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
    }

    func requestAccess() async throws -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            return true
        }
        return try await store.requestFullAccessToReminders()
    }

    func availableLists() async throws -> [ReminderListOption] {
        guard try await requestAccess() else { throw ReminderServiceError.accessDenied }
        return store.calendars(for: .reminder)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { ReminderListOption(id: $0.calendarIdentifier, title: $0.title) }
    }

    func createReminders(
        drafts: [ReminderDraft],
        session: LectureSession,
        schedule: [LessonScheduleEntry],
        listIdentifier: String? = nil
    ) async throws -> [String] {
        guard !drafts.isEmpty else { return [] }
        guard try await requestAccess() else {
            throw ReminderServiceError.accessDenied
        }
        let calendar = listIdentifier.flatMap { identifier in
            store.calendars(for: .reminder).first { $0.calendarIdentifier == identifier }
        } ?? store.defaultCalendarForNewReminders()
        guard let calendar else {
            throw ReminderServiceError.noReminderList
        }

        let source = "Whisp · \(session.title)"
        var identifiers: [String] = []
        for draft in drafts.prefix(5) where !draft.isInClassAssessmentInstruction {
            guard let dueDate = resolvedDueDate(
                for: draft,
                subject: session.subject,
                after: session.startedAt ?? session.createdAt,
                schedule: schedule
            ), dueDate > Date() else { continue }
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let dueHint = draft.dueHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let deadline = dueHint.isEmpty ? "" : "\nСрок в лекции: \(dueHint)"
            reminder.notes = "\(draft.notes.trimmingCharacters(in: .whitespacesAndNewlines))\(deadline)\n\nИсточник: \(source)"
            reminder.calendar = calendar
            reminder.dueDateComponents = Calendar.current.dateComponents([.calendar, .year, .month, .day, .hour, .minute], from: dueDate)
            try store.save(reminder, commit: true)
            identifiers.append(reminder.calendarItemIdentifier)
        }
        return identifiers
    }

    func resolvedDueDate(
        for draft: ReminderDraft,
        subject: String,
        after date: Date,
        schedule: [LessonScheduleEntry]
    ) -> Date? {
        let hint = draft.dueHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hint.isEmpty || hint.contains("следующ") && hint.contains("урок") {
            return preparationDate(
                before: nextLessonDate(subject: subject, after: date, schedule: schedule)
            )
        }

        if hint.contains("урок"), let count = firstNumber(in: hint) {
            return lessonAfter(subject: subject, count: count + 1, after: date, schedule: schedule)
                .map { preparationDate(before: $0) }
        }

        if (hint.contains("след") && hint.contains("недел")) || hint.contains("через неделю") {
            return lessonInFollowingWeek(subject: subject, after: date, schedule: schedule)
                .map { preparationDate(before: $0) }
        }

        let weekdays: [(String, Int)] = [
            ("понедельник", 2), ("вторник", 3), ("сред", 4),
            ("четверг", 5), ("пятниц", 6), ("суббот", 7), ("воскрес", 1)
        ]
        if let weekday = weekdays.first(where: { hint.contains($0.0) })?.1 {
            return nextLessonOnWeekday(weekday, subject: subject, after: date, schedule: schedule)
                .map { preparationDate(before: $0) }
        }

        return preparationDate(before: nextLessonDate(subject: subject, after: date, schedule: schedule))
    }

    /// Remind the student the evening before the lesson, leaving time to do
    /// homework or pack something instead of notifying at the classroom door.
    func preparationDate(before lessonDate: Date) -> Date {
        let calendar = Calendar.current
        let previousDay = calendar.date(byAdding: .day, value: -1, to: lessonDate) ?? lessonDate
        return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: previousDay) ?? previousDay
    }

    func nextLessonDate(subject: String, after date: Date, schedule: [LessonScheduleEntry]) -> Date {
        let calendar = Calendar.current
        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = schedule.filter {
            normalizedSubject.isEmpty || $0.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedSubject
        }
        let usable = candidates.isEmpty ? schedule : candidates
        guard !usable.isEmpty else { return date.addingTimeInterval(86_400) }

        return usable.compactMap { entry -> Date? in
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                      calendar.component(.weekday, from: day) == entry.weekday else { continue }
                guard let candidate = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day) else { continue }
                if candidate > date { return candidate }
            }
            return nil
        }.min() ?? date.addingTimeInterval(86_400)
    }

    private func firstNumber(in text: String) -> Int? {
        if let number = text.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first {
            return number
        }
        let words = ["один": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5]
        return words.first(where: { text.contains($0.key) })?.value
    }

    private func lessonAfter(subject: String, count: Int, after date: Date, schedule: [LessonScheduleEntry]) -> Date? {
        var cursor = date
        var result: Date?
        for _ in 0..<max(1, count) {
            result = nextLessonDate(subject: subject, after: cursor, schedule: schedule)
            guard let result else { return nil }
            cursor = result
        }
        return result
    }

    private func nextLessonOnWeekday(
        _ weekday: Int,
        subject: String,
        after date: Date,
        schedule: [LessonScheduleEntry]
    ) -> Date? {
        let calendar = Calendar.current
        let candidates = schedule.filter {
            $0.weekday == weekday && (subject.isEmpty || $0.subject.caseInsensitiveCompare(subject) == .orderedSame)
        }
        let usable = candidates.isEmpty ? schedule.filter { $0.weekday == weekday } : candidates
        return usable.compactMap { entry in
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                      calendar.component(.weekday, from: day) == weekday,
                      let candidate = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day),
                      candidate > date else { continue }
                return candidate
            }
            return nil
        }.min()
    }

    private func lessonInFollowingWeek(subject: String, after date: Date, schedule: [LessonScheduleEntry]) -> Date? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        guard let nextMonday = calendar.date(byAdding: .day, value: 7 - daysFromMonday, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        let candidates = schedule.filter {
            subject.isEmpty || $0.subject.caseInsensitiveCompare(subject) == .orderedSame
        }
        let usable = candidates.isEmpty ? schedule : candidates
        return usable.compactMap { entry in
            guard let dayOffset = [2, 3, 4, 5, 6, 7, 1].firstIndex(of: entry.weekday),
                  let day = calendar.date(byAdding: .day, value: dayOffset, to: nextMonday),
                  let candidate = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day) else {
                return nil
            }
            return candidate
        }.min()
    }
}

enum ReminderServiceError: LocalizedError {
    case accessDenied
    case noReminderList

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Whisp не получил доступ к Apple Reminders. Разрешите его в настройках macOS."
        case .noReminderList: "В Apple Reminders не найден список для новых напоминаний."
        }
    }
}
