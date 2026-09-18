import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: OmnibusStore
    @Binding var selection: SidebarSelection?

    @State private var editingCourse: ClassroomCourse?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Today", systemImage: "sparkles")
                    .tag(SidebarSelection.today)
                Label("Schedule", systemImage: "calendar")
                    .tag(SidebarSelection.schedule)
                Label("Coursework", systemImage: "graduationcap")
                    .tag(SidebarSelection.coursework)
                Label("Messages", systemImage: "bubble.left.and.bubble.right")
                    .tag(SidebarSelection.messages)
            }

            if !store.classroomCourses.isEmpty {
                Section("Classrooms") {
                    ForEach(store.classroomCourses) { course in
                        Label {
                            Text(course.name)
                                .lineLimit(1)
                        } icon: {
                            courseIcon(for: course)
                        }
                        .tag(SidebarSelection.subject(course.id))
                        .contextMenu {
                            Button {
                                editingCourse = course
                            } label: {
                                Label("Edit Icon…", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Omnibus")
        .frame(minWidth: 200)
        .sheet(item: $editingCourse) { course in
            CourseIconEditorView(
                course: course,
                currentEmoji: store.courseIcons[course.id],
                onSave: { emoji in store.setCourseIcon(emoji, for: course.id) },
                onDismiss: { editingCourse = nil }
            )
        }
    }

    /// The sidebar icon for a classroom -- a custom emoji if one's been set
    /// (see CourseIconEditorView), the plain book icon otherwise.
    @ViewBuilder
    private func courseIcon(for course: ClassroomCourse) -> some View {
        if let emoji = store.courseIcons[course.id], !emoji.isEmpty {
            Text(emoji)
        } else {
            Image(systemName: "book.closed")
        }
    }
}
