import SwiftUI

/// The home screen: a glanceable status line, a visual timeline of today's
/// classes (with due-today items flagged on it), the full schedule list,
/// lunch, and what's due soon -- everything you'd otherwise check three
/// separate places for, in one read top to bottom.
struct TodayView: View {
    @EnvironmentObject var store: OmnibusStore
    @EnvironmentObject var auth: GoogleAuthManager

    var body: some View {
        let todaysLessons = store.schedule?.lessons(for: .now) ?? []

        GlassPanel {
            statusHeader

            if !todaysLessons.isEmpty {
                DayTimelineBar(
                    lessons: todaysLessons,
                    dueToday: dueTodayItems,
                    rangeStart: timelineStart(for: todaysLessons),
                    rangeEnd: timelineEnd(for: todaysLessons)
                )
            }

            Divider()
            SectionHeader("Today's schedule", systemImage: "calendar")
            scheduleRows(todaysLessons)

            Divider()
            SectionHeader("Lunch", systemImage: "fork.knife")
            lunchRow

            Divider()
            SectionHeader(
                "Due soon",
                systemImage: "exclamationmark.circle",
                trailingText: dueSoonItems.isEmpty ? nil : "\(dueSoonItems.count)"
            )
            dueSoonList
        }
    }

    // MARK: - Status header

    private var statusHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLine)
                    .font(.title3.weight(.semibold))
                if let statusSubline {
                    Text(statusSubline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !dueTodayItems.isEmpty {
                VStack(spacing: 2) {
                    Text("\(dueTodayItems.count)")
                        .font(.title2.weight(.bold))
                    Text("due today")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private var statusLine: String {
        guard let schedule = store.schedule else {
            return store.hasSchoolSoftAccount ? "Syncing your schedule…" : "Add your SchoolSoft account"
        }
        if let active = schedule.activeLesson() {
            return active.subject
        }
        if let next = schedule.nextLesson() {
            return "Free until \(next.start.formatted(date: .omitted, time: .shortened))"
        }
        return schedule.lessons(for: .now).isEmpty ? "No school today" : "Done for the day"
    }

    private var statusSubline: String? {
        guard let schedule = store.schedule else { return nil }
        if let active = schedule.activeLesson() {
            var parts = ["Until \(active.end.formatted(date: .omitted, time: .shortened))"]
            if let room = active.room { parts.append(room) }
            return parts.joined(separator: "  ·  ")
        }
        if let next = schedule.nextLesson() {
            var parts = ["Next: \(next.subject)"]
            if let room = next.room { parts.append(room) }
            return parts.joined(separator: "  ·  ")
        }
        return nil
    }

    // MARK: - Schedule

    @ViewBuilder
    private func scheduleRows(_ lessons: [Lesson]) -> some View {
        if let error = store.schoolSoftError {
            Text(error).font(.subheadline).foregroundStyle(.red)
        } else if lessons.isEmpty {
            if !store.hasSchoolSoftAccount {
                DashboardEmptyText("Add your SchoolSoft account in Settings to see today's schedule.")
            } else if store.schedule == nil {
                ProgressView().controlSize(.small)
            } else {
                DashboardEmptyText("No lessons today.")
            }
        } else {
            VStack(spacing: 6) {
                ForEach(lessons) { lesson in
                    LessonRow(lesson: lesson)
                }
            }
        }
    }

    // MARK: - Lunch

    @ViewBuilder
    private var lunchRow: some View {
        if let menu = store.lunchMenu, let today = menu.menu(for: .now) {
            let dishes = today.dishes(for: .normal)
            if dishes.isEmpty {
                DashboardEmptyText("No menu listed for today.")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(dishes, id: \.self) { dish in
                        Text(dish).font(.title3)
                    }
                }
            }
        } else {
            DashboardEmptyText("No lunch menu synced.")
        }
    }

    // MARK: - Due soon

    private var dueTodayItems: [ClassroomWorkItem] {
        store.classroomItems.filter { item in
            guard let due = item.dueDate else { return false }
            return Calendar.current.isDateInToday(due)
        }
    }

    /// Overdue, due today, or due within the next week -- store.classroomItems
    /// already arrives sorted ascending by due date (nil-last), so filtering
    /// preserves that order: overdue first, then soonest to furthest out.
    private var dueSoonItems: [ClassroomWorkItem] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        return store.classroomItems.filter { item in
            guard let due = item.dueDate else { return false }
            return due <= horizon
        }
    }

    @ViewBuilder
    private var dueSoonList: some View {
        if !auth.isSignedIn {
            DashboardEmptyText("Sign in with Google in Settings to see coursework.")
        } else if store.isSyncingClassroom && store.classroomItems.isEmpty {
            ProgressView().controlSize(.small)
        } else if dueSoonItems.isEmpty {
            DashboardEmptyText("Nothing due in the next 7 days.")
        } else {
            VStack(spacing: 10) {
                ForEach(dueSoonItems) { item in
                    DueSoonRow(item: item)
                }
            }
        }

        if let error = store.classroomError {
            Text(error).font(.caption2).foregroundStyle(.red)
        }
    }

    // MARK: - Timeline range

    private func timelineStart(for lessons: [Lesson]) -> Date {
        let earliest = lessons.map(\.start).min() ?? .now
        return earliest.addingTimeInterval(-30 * 60)
    }

    private func timelineEnd(for lessons: [Lesson]) -> Date {
        let latest = lessons.map(\.end).max() ?? .now
        return latest.addingTimeInterval(30 * 60)
    }
}

// MARK: - Due soon row

/// Like ClassroomRow, but leads with a relative-time badge (Overdue / Today
/// HH:mm / Tomorrow / weekday) instead of a plain date, since the whole
/// point of this list is "how urgent is this at a glance."
private struct DueSoonRow: View {
    var item: ClassroomWorkItem
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 10) {
                Text(relativeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor, in: Capsule())
                    .frame(minWidth: 74)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.courseName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            CourseworkDetailView(item: item) { showingDetail = false }
        }
    }

    private var relativeLabel: String {
        guard let due = item.dueDate else { return "" }
        let calendar = Calendar.current
        if item.isOverdue { return "Overdue" }
        if calendar.isDateInToday(due) {
            return "Today " + due.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInTomorrow(due) {
            return "Tomorrow"
        }
        return due.formatted(.dateTime.weekday(.abbreviated))
    }

    private var badgeColor: Color {
        if item.isOverdue { return .red }
        guard let due = item.dueDate else { return .secondary }
        if Calendar.current.isDateInToday(due) { return .orange }
        return .accentColor
    }
}

// MARK: - Day timeline bar

/// A proportional, absolutely-positioned bar for today's class blocks
/// (not sequentially packed -- gaps between lessons render as real gaps),
/// with a live "now" marker and small flags for anything due today,
/// positioned at its actual due time along the same axis.
private struct DayTimelineBar: View {
    var lessons: [Lesson]
    var dueToday: [ClassroomWorkItem]
    var rangeStart: Date
    var rangeEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !dueToday.isEmpty {
                dueMarkerRow
            }
            lessonBarRow
            timeLabelRow
        }
    }

    private var dueMarkerRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(dueToday) { item in
                    if let due = item.dueDate {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(item.isOverdue ? Color.red : Color.orange)
                            .offset(x: xPosition(for: due, totalWidth: geo.size.width) - 4)
                    }
                }
            }
        }
        .frame(height: 10)
    }

    private var lessonBarRow: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))

                ForEach(lessons) { lesson in
                    let startX = xPosition(for: lesson.start, totalWidth: width)
                    let endX = xPosition(for: lesson.end, totalWidth: width)
                    let blockWidth = max(endX - startX, 3)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(lesson.isActive() ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .frame(width: blockWidth)
                        .overlay(alignment: .leading) {
                            Text(lesson.subject)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.vertical, 3)
                        .offset(x: startX)
                }

                if isNowInRange {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2)
                        .offset(x: xPosition(for: Date(), totalWidth: width))
                }
            }
        }
        .frame(height: 26)
    }

    private var timeLabelRow: some View {
        HStack {
            Text(rangeStart.formatted(date: .omitted, time: .shortened))
            Spacer()
            Text(rangeEnd.formatted(date: .omitted, time: .shortened))
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var isNowInRange: Bool {
        let now = Date()
        return now >= rangeStart && now <= rangeEnd
    }

    private func xPosition(for date: Date, totalWidth: CGFloat) -> CGFloat {
        let totalSeconds = max(rangeEnd.timeIntervalSince(rangeStart), 60)
        let clamped = min(max(date, rangeStart), rangeEnd)
        let fraction = clamped.timeIntervalSince(rangeStart) / totalSeconds
        return totalWidth * CGFloat(fraction)
    }
}
