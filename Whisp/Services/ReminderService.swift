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
        try await store.requestFullAccessToReminders()
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

        let dueDate = nextLessonDate(subject: session.subject, after: session.startedAt ?? session.createdAt, schedule: schedule)
        let source = "Whisp · (session.title)"
        var identifiers: [String] = []
        for draft in drafts.prefix(5) {
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.notes = "(draft.notes.trimmingCharacters(in: .whitespacesAndNewlines))\n\nИсточник: (source)"
            reminder.calendar = calendar
            reminder.dueDateComponents = Calendar.current.dateComponents([.calendar, .year, .month, .day, .hour, .minute], from: dueDate)
            try store.save(reminder, commit: true)
            identifiers.append(reminder.calendarItemIdentifier)
        }
        return identifiers
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
