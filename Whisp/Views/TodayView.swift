import SwiftUI

private struct DashboardTask: Identifiable {
    let id: String
    let draft: ReminderDraft
    let session: LectureSession
    let dueDate: Date
    let isCompleted: Bool
}

struct TodayView: View {
    @Bindable var model: AppModel

    private var lessons: [ScheduledLesson] {
        StudyDashboardPlanner.upcomingLessons(from: model.settingsStore.settings.lessonSchedule)
    }

    private var tasks: [DashboardTask] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return model.sessions.flatMap { session -> [DashboardTask] in
            (session.analysis?.reminders ?? []).compactMap { draft in
                guard !draft.isInClassAssessmentInstruction else { return nil }
                let dueDate = model.reminderService.resolvedDueDate(
                    for: draft,
                    subject: session.subject,
                    after: session.startedAt ?? session.createdAt,
                    schedule: model.settingsStore.settings.lessonSchedule
                )
                guard let dueDate, dueDate >= startOfToday else { return nil }
                return DashboardTask(
                    id: "\(session.id.uuidString)-\(draft.id.uuidString)",
                    draft: draft,
                    session: session,
                    dueDate: dueDate,
                    isCompleted: session.completedReminderIDs.contains(draft.id)
                )
            }
        }
        .sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.dueDate < $1.dueDate
        }
    }

    private var reviewSessions: [LectureSession] {
        StudyDashboardPlanner.reviewSessions(from: model.sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summary
                recentSection
                tasksSection
                lessonsSection
                reviewSection
            }
            .frame(maxWidth: WhispMetrics.contentWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(WhispPalette.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Сегодня")
                    .font(.largeTitle.weight(.semibold))
                Text(Date().formatted(
                    Date.FormatStyle()
                        .weekday(.wide)
                        .day()
                        .month(.wide)
                        .locale(Locale(identifier: "ru_RU"))
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryCard(value: lessons.filter { Calendar.current.isDateInToday($0.date) }.count, title: "Занятия сегодня", icon: "calendar", color: WhispPalette.accent)
            Divider().frame(height: 38)
            summaryCard(value: tasks.filter { !$0.isCompleted }.count, title: "Задания", icon: "checklist", color: WhispPalette.warning)
            Divider().frame(height: 38)
            summaryCard(value: reviewSessions.count, title: "Повторение", icon: "clock.arrow.circlepath", color: .purple)
        }
        .padding(.vertical, 8).whispContentCard()
    }

    private func summaryCard(value: Int, title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(value)").font(.title2.monospacedDigit().bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity)
    }

    @ViewBuilder private var recentSection: some View {
        if !model.sessions.isEmpty {
            dashboardSection(title: "Продолжить изучение", icon: "book") {
                ForEach(model.sessions.prefix(2)) { session in
                    Button { model.selectSession(session.id) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary).frame(width: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(WhispFormatting.displayTitle(session.title)).font(.callout.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text("\(session.subject) · \(WhispFormatting.lectureDate(session.startedAt ?? session.createdAt))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).whispContentCard()
                }
            }
        }
    }

    @ViewBuilder private var lessonsSection: some View {
        dashboardSection(title: "Ближайшие занятия", icon: "calendar.day.timeline.left") {
            if lessons.isEmpty {
                emptyRow(
                    "Расписание пока не заполнено",
                    detail: "Добавьте занятия, и Whisp будет связывать с ними задания из лекций."
                ) {
                    model.showSettings = true
                }
            } else {
                ForEach(lessons.prefix(5)) { lesson in
                    HStack(spacing: 14) {
                        VStack(spacing: 1) {
                            Text(lesson.date.formatted(.dateTime.day()))
                                .font(.title3.monospacedDigit().bold())
                            Text(lesson.date.formatted(
                                Date.FormatStyle()
                                    .month(.abbreviated)
                                    .locale(Locale(identifier: "ru_RU"))
                            ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 48, height: 48)
.background(WhispPalette.quietFill, in: .rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(lesson.entry.subject)
                                .font(.callout.weight(.semibold))
                            Text(lesson.date.formatted(
                                Date.FormatStyle()
                                    .weekday(.wide)
                                    .hour()
                                    .minute()
                                    .locale(Locale(identifier: "ru_RU"))
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(lesson.entry.durationMinutes) мин")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .whispContentCard()
                }
            }
        }
    }

    @ViewBuilder private var tasksSection: some View {
        dashboardSection(title: "Задания", icon: "checklist") {
            if tasks.isEmpty {
                emptyRow("Нет актуальных заданий", detail: "Новые поручения появятся здесь после разбора лекции.")
            } else {
                ForEach(tasks) { item in
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            withAnimation(WhispMotion.control) {
                                model.toggleReminderCompletion(
                                    sessionID: item.session.id,
                                    reminderID: item.draft.id
                                )
                            }
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(item.isCompleted ? WhispPalette.success : .secondary)
                                .frame(width: 30, height: 30)

                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isCompleted ? "Вернуть задание" : "Отметить выполненным")

                        Button {
                            model.selectSession(item.session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(WhispFormatting.withoutDecorativeEmoji(item.draft.title))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .strikethrough(item.isCompleted)
                                    .multilineTextAlignment(.leading)
                                Text("\(item.session.subject) · \(WhispFormatting.displayTitle(item.session.title))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item.isCompleted {
                            Text("Выполнено")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(WhispPalette.success)
                        } else {
                            Text(item.dueDate.formatted(
                                Date.FormatStyle()
                                    .day()
                                    .month(.abbreviated)
                                    .hour()
                                    .minute()
                                    .locale(Locale(identifier: "ru_RU"))
                            ))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            withAnimation(WhispMotion.content) {
                                model.deleteReminder(
                                    sessionID: item.session.id,
                                    reminderID: item.draft.id
                                )
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)

                        }
                        .buttonStyle(.plain)
                        .help("Удалить задание")
                    }
                    .padding(12)
                    .whispContentCard()
                    .opacity(item.isCompleted ? 0.72 : 1)
                    .contextMenu {
                        Button(item.isCompleted ? "Вернуть в активные" : "Отметить выполненным") {
                            model.toggleReminderCompletion(
                                sessionID: item.session.id,
                                reminderID: item.draft.id
                            )
                        }
                        Divider()
                        Button("Удалить", role: .destructive) {
                            model.deleteReminder(
                                sessionID: item.session.id,
                                reminderID: item.draft.id
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var reviewSection: some View {
        dashboardSection(title: "Пора повторить", icon: "brain.head.profile") {
            if reviewSessions.isEmpty {
                emptyRow("На сегодня всё", detail: "Карточки вернутся после выбранного интервала повторения.")
            } else {
                ForEach(reviewSessions.prefix(5)) { session in
                    Button {
                        model.selectSession(session.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: session.quizProgress.needsReview.isEmpty ? "rectangle.stack" : "arrow.counterclockwise.circle.fill")
                                .font(.title3)
                                .foregroundStyle(session.quizProgress.needsReview.isEmpty ? WhispPalette.accent : WhispPalette.warning)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(WhispFormatting.displayTitle(session.title))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(reviewCaption(for: session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .whispContentCard()
                }
            }
        }
    }

    private func reviewCaption(for session: LectureSession) -> String {
        if !session.quizProgress.needsReview.isEmpty {
            return "Повторить вопросов: \(session.quizProgress.needsReview.count) · \(session.subject)"
        }
        if session.quizProgress.lastStudiedAt == nil {
            return "Ещё не проходили · \(session.subject)"
        }
        return "Плановое повторение · \(session.subject)"
    }

    private func dashboardSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.headline)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func emptyRow(
        _ title: String,
        detail: String,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button("Настроить", action: action)
                    .buttonStyle(WhispActionStyle())
                    .controlSize(.small)
            }
        }
        .padding(14)
        .whispContentCard()
    }
}
