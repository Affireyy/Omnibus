import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: OmnibusStore
    var searchText: String

    private let columnWidth: CGFloat = 190

    var body: some View {
        GlassPanel {
            SectionHeader("Schedule", systemImage: "calendar")

            if let schedule = store.schedule {
                let days = schedule.weekdayLessons()
                // Every weekday shows up, even ones with nothing on them --
                // a day silently missing from the row read as broken, not
                // as "you're free." Search is the one case where hiding a
                // non-matching day is actually useful.
                let visibleDays = searchText.isEmpty
                    ? days
                    : days.filter { !filteredLessons(for: $0.lessons).isEmpty }

                if visibleDays.isEmpty {
                    DashboardEmptyText("No lessons match \"\(searchText)\".")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(visibleDays.enumerated()), id: \.element.id) { index, day in
                                dayColumn(day)
                                if index < visibleDays.count - 1 {
                                    Divider()
                                        .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            } else if store.isSyncingSchoolSoft {
                ProgressView().controlSize(.small)
            } else if store.hasSchoolSoftAccount {
                DashboardEmptyText("Not synced yet.")
            } else {
                DashboardEmptyText("Add your SchoolSoft account in Settings.")
            }

            if let error = store.schoolSoftError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Day column

    @ViewBuilder
    private func dayColumn(_ day: WeekdaySchedule) -> some View {
        let dayLessons = filteredLessons(for: day.lessons)
        let isToday = Calendar.current.isDateInToday(day.date)

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(day.date.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Text(day.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if dayLessons.isEmpty {
                DashboardEmptyText(searchText.isEmpty ? "Free day" : "No matches")
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(dayLessons.enumerated()), id: \.element.id) { index, lesson in
                        LessonRow(lesson: lesson)

                        // A gap between this lesson's end and the next one's
                        // start is a real break -- show how long it is
                        // instead of just leaving blank space, so the
                        // schedule reads the way a printed timetable does.
                        // Back-to-back lessons (no gap) get no row at all.
                        if index < dayLessons.count - 1,
                           let minutes = breakDuration(from: lesson, to: dayLessons[index + 1]) {
                            BreakRow(minutes: minutes)
                        }
                    }
                }
            }

            if let menu = store.lunchMenu, let dayMenu = menu.menu(for: day.date) {
                let dishes = dayMenu.dishes(for: .normal)
                if !dishes.isEmpty {
                    Label(dishes.joined(separator: ", "), systemImage: "fork.knife")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .topLeading)
        .background(
            isToday ? Color.accentColor.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func filteredLessons(for lessons: [Lesson]) -> [Lesson] {
        guard !searchText.isEmpty else { return lessons }
        return lessons.filter {
            $0.subject.localizedCaseInsensitiveContains(searchText)
            || ($0.room?.localizedCaseInsensitiveContains(searchText) ?? false)
            || ($0.teacher?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Minutes between one lesson ending and the next starting, or nil if
    /// they're back-to-back (or overlapping/out of order) and there's no
    /// real break to show.
    private func breakDuration(from: Lesson, to: Lesson) -> Int? {
        let minutes = Int(to.start.timeIntervalSince(from.end) / 60)
        return minutes > 0 ? minutes : nil
    }
}

/// A labeled spacer between two lessons showing how long the break between
/// them is, e.g. "25 min break" or "1h 15m break" -- styled as a thin
/// divider line with the duration centered in it, like a printed timetable.
private struct BreakRow: View {
    var minutes: Int

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var label: String {
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, let m):
            return "\(m) min break"
        case (let h, 0):
            return "\(h)h break"
        default:
            return "\(hours)h \(remainder)m break"
        }
    }
}
