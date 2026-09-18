import SwiftUI

struct CourseworkView: View {
    @EnvironmentObject var store: OmnibusStore
    @EnvironmentObject var auth: GoogleAuthManager
    var searchText: String

    var body: some View {
        GlassPanel {
            SectionHeader(
                "Coursework",
                systemImage: "graduationcap",
                trailingText: auth.isSignedIn ? "\(filteredItems.count)" : nil
            )

            if !auth.isSignedIn {
                DashboardEmptyText("Sign in with Google in Settings to see coursework.")
            } else if store.isSyncingClassroom && store.classroomItems.isEmpty {
                ProgressView().controlSize(.small)
            } else if filteredItems.isEmpty {
                DashboardEmptyText(searchText.isEmpty ? "No upcoming coursework." : "Nothing matches \"\(searchText)\".")
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredItems) { item in
                        ClassroomRow(item: item)
                    }
                }
            }

            if let error = store.classroomError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private var filteredItems: [ClassroomWorkItem] {
        guard !searchText.isEmpty else { return store.classroomItems }
        return store.classroomItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.courseName.localizedCaseInsensitiveContains(searchText)
        }
    }
}
