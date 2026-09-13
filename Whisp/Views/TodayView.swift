import SwiftUI

private struct DashboardTask: Identifiable {
    let id: String
    let draft: ReminderDraft
    let session: LectureSession
    let dueDate: Date
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
                    dueDate: dueDate
                )
            }
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    private var reviewSessions: [LectureSession] {
        StudyDashboardPlanner.reviewSessions(from: model.sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summary
                lessonsSection
                tasksSection
                reviewSection
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(WhispPalette.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Сегодня")
                    .font(.largeTitle.bold())
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
            Button {
                model.showStartScreen()
            } label: {
                Label("Новая лекция", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isBusy)
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            summaryCard(
                value: lessons.filter { Calendar.current.isDateInToday($0.date) }.count,
                title: "занятий сегодня",
                icon: "calendar",
                color: WhispPalette.accent
            )
            summaryCard(
                value: tasks.count,
                title: "актуальных заданий",
                icon: "checklist",
                color: WhispPalette.warning
            )
            summaryCard(
                value: reviewSessions.count,
                title: "лекций повторить",
                icon: "rectangle.stack.badge.clock",
                color: .purple
            )
        }
    }

    private func summaryCard(value: Int, title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .glassEffect(
                    .regular.tint(color.opacity(0.16)),
                    in: .rect(cornerRadius: WhispMetrics.compactCornerRadius)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.title2.monospacedDigit().bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .whispGlassPanel(cornerRadius: WhispMetrics.surfaceCornerRadius)
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
                        .glassEffect(
                            .regular.tint(WhispPalette.accent.opacity(0.14)),
                            in: .rect(cornerRadius: 11)
                        )

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
                    .whispGlassPanel()
                }
            }
        }
    }

    @ViewBuilder private var tasksSection: some View {
        dashboardSection(title: "Задания", icon: "checklist") {
            if tasks.isEmpty {
                emptyRow("Нет актуальных заданий", detail: "Новые поручения появятся здесь после разбора лекции.")
            } else {
                ForEach(tasks.prefix(6)) { item in
                    Button {
                        model.selectSession(item.session.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.session.createdReminderIDs.isEmpty ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(item.session.createdReminderIDs.isEmpty ? WhispPalette.warning : WhispPalette.success)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.draft.title)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Text("\(item.session.subject) · \(item.session.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
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
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .whispInteractiveGlassSurface()
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
                                Text(session.title)
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
                    .whispInteractiveGlassSurface()
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
            Label(title, systemImage: icon)
                .font(.headline)
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
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .whispGlassPanel()
    }
}
