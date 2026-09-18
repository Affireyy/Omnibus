import SwiftUI

/// Where the "everything integrates" ask actually shows up: one subject's
/// lessons and coursework together in a single screen -- laid out to echo
/// the shape of a real Google Classroom class page (a colorful banner
/// identifying the class, then a Classwork/Schedule switcher below it).
/// Chat messages deliberately don't appear here: they're their own thing
/// in the Messages tab, not part of a classroom's identity the way an
/// assignment or a lesson is.
struct SubjectView: View {
    @EnvironmentObject var store: OmnibusStore
    var groupID: String

    @State private var selectedTab: SubjectTab = .classwork

    var body: some View {
        if let group {
            VStack(alignment: .leading, spacing: 16) {
                SubjectBanner(group: group, icon: store.courseIcons[group.id])

                GlassPanel {
                    Picker("View", selection: $selectedTab) {
                        ForEach(SubjectTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch selectedTab {
                    case .classwork:
                        classworkSection
                    case .schedule:
                        scheduleSection
                    }
                }
            }
        } else {
            GlassPanel {
                DashboardEmptyText("This subject is no longer available -- try refreshing.")
            }
        }
    }

    private var group: SubjectGroup? {
        store.subjectGroup(id: groupID)
    }

    // MARK: - Classwork

    @ViewBuilder
    private var classworkSection: some View {
        if sortedCoursework.isEmpty {
            DashboardEmptyText("No coursework for this class.")
        } else {
            VStack(spacing: 12) {
                ForEach(sortedCoursework) { item in
                    SubjectCourseworkRow(item: item)
                }
            }
        }
    }

    private var sortedCoursework: [ClassroomWorkItem] {
        (group?.coursework ?? []).sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    // MARK: - Schedule

    @ViewBuilder
    private var scheduleSection: some View {
        if sortedLessons.isEmpty {
            DashboardEmptyText("No lessons matched to this class.")
        } else {
            VStack(spacing: 4) {
                ForEach(sortedLessons) { lesson in
                    LessonRow(lesson: lesson, showsSubject: false)
                }
            }
        }
    }

    private var sortedLessons: [Lesson] {
        (group?.lessons ?? []).sorted { $0.start < $1.start }
    }
}

// MARK: - Tabs

private enum SubjectTab: String, CaseIterable, Identifiable {
    case classwork, schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classwork: return "Classwork"
        case .schedule: return "Schedule"
        }
    }
}

// MARK: - Banner

/// A colorful class-identity header echoing the banner atop a real Google
/// Classroom class page: a deterministic color per course (there's no
/// cover photo to pull from), the course's own emoji icon if one's been
/// set (see CourseIconEditorView / the sidebar's right-click "Edit Icon")
/// standing in for Classroom's banner artwork, and a quick-glance activity
/// summary in place of the class section/room Classroom shows there
/// (data Omnibus doesn't have from the API).
private struct SubjectBanner: View {
    var group: SubjectGroup
    var icon: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Group {
                if let icon, !icon.isEmpty {
                    Text(icon)
                        .font(.system(size: 110))
                } else {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 80))
                }
            }
            .foregroundStyle(.white.opacity(0.16))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 24)
            .offset(y: 14)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(group.displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(20)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var subtitle: String {
        var parts: [String] = []
        if group.pendingCourseworkCount > 0 {
            parts.append("\(group.pendingCourseworkCount) pending assignment\(group.pendingCourseworkCount == 1 ? "" : "s")")
        }
        if !group.lessons.isEmpty {
            parts.append("\(group.lessons.count) lesson\(group.lessons.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "No recent activity" : parts.joined(separator: "  ·  ")
    }

    private var color: Color {
        courseColor(for: group.id)
    }
}

/// Deterministic -- unlike Swift's `Hasher`, which is randomized per
/// process for DoS-resistance -- so a given class's banner color stays the
/// same across launches instead of shuffling every time the app opens.
private func courseColor(for id: String) -> Color {
    var hash: UInt64 = 5381
    for scalar in id.unicodeScalars {
        hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
    }
    let hue = Double(hash % 360) / 360.0
    return Color(hue: hue, saturation: 0.5, brightness: 0.58)
}

// MARK: - Coursework row

/// A coursework row styled with a small colored icon bubble (red once
/// overdue) rather than the plain text-only ClassroomRow used elsewhere --
/// this screen's whole point is to read a bit more like an actual
/// Classroom class page than the rest of the app's plainer lists do.
private struct SubjectCourseworkRow: View {
    var item: ClassroomWorkItem
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(item.isOverdue ? Color.red : Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No due date")
                        .font(.caption)
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            CourseworkDetailView(item: item) { showingDetail = false }
        }
    }
}
