import SwiftUI

/// Which screen the sidebar has selected. Kept as one enum shared between
/// the sidebar and the detail switch below, so navigation state lives in
/// exactly one place.
enum SidebarSelection: Hashable {
    case today
    case schedule
    case coursework
    case messages
    case subject(String)
}

/// The whole app window: a sidebar plus a single glass-panel detail area,
/// with one shared toolbar (title, sync status, refresh, settings, search)
/// -- everything routes through this one shell rather than each service
/// owning its own window or chrome.
struct RootView: View {
    @EnvironmentObject var store: OmnibusStore
    @EnvironmentObject var auth: GoogleAuthManager
    @Environment(\.openWindow) private var openWindow
    @State private var selection: SidebarSelection? = .today
    @State private var isRefreshing = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            ZStack {
                DashboardBackground()
                VStack(spacing: 0) {
                    toolbar
                    if isMessagesSelected {
                        // Messages manages its own scrolling in both its
                        // panes, so it gets a plain expanding frame instead
                        // of the ScrollView every other screen sits in --
                        // otherwise it sizes to its content and leaves a
                        // dead gap below it instead of filling the window.
                        MessagesView(searchText: searchText)
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            detailContent
                                .padding(20)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search everything")
        .frame(minWidth: 980, minHeight: 640)
        .task {
            await store.refreshAll()
            store.startAutoRefreshingChat()
        }
    }

    private var isMessagesSelected: Bool {
        if case .messages = selection ?? .today { return true }
        return false
    }

    /// Used for every screen except Messages (see `body`), which renders
    /// itself directly so it can fill the available height instead of
    /// sizing to content inside a ScrollView.
    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .today {
        case .today:
            TodayView()
        case .schedule:
            ScheduleView(searchText: searchText)
        case .coursework:
            CourseworkView(searchText: searchText)
        case .messages:
            MessagesView(searchText: searchText)
        case .subject(let id):
            SubjectView(groupID: id)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(screenTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                if let last = store.lastRefreshed {
                    Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task {
                    isRefreshing = true
                    await store.refreshAll()
                    isRefreshing = false
                }
            } label: {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh everything")
            .disabled(isRefreshing)

            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var screenTitle: String {
        switch selection ?? .today {
        case .today: return "Omnibus"
        case .schedule: return "Schedule"
        case .coursework: return "Coursework"
        case .messages: return "Messages"
        case .subject(let id): return store.subjectGroup(id: id)?.displayName ?? "Subject"
        }
    }
}
