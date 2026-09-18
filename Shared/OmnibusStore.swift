import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Central data layer for the dashboard: coordinates SchoolSoft, Classroom,
/// and Chat fetches, holds the combined state every view reads from, and
/// keeps a small on-disk snapshot so the dashboard isn't blank on a cold,
/// offline launch.
@MainActor
public final class OmnibusStore: ObservableObject {
    public static let shared = OmnibusStore()

    // SchoolSoft
    @Published public var schedule: Schedule?
    @Published public var lunchMenu: LunchMenu?
    @Published public var schoolSoftError: String?
    @Published public var isSyncingSchoolSoft = false

    // Classroom
    @Published public var classroomItems: [ClassroomWorkItem] = []
    @Published public var classroomCourses: [ClassroomCourse] = []
    @Published public var classroomError: String?
    @Published public var isSyncingClassroom = false

    // Chat
    @Published public var chatMessages: [ChatMessageItem] = []
    @Published public var chatSpaces: [ChatSpace] = []
    @Published public var chatError: String?
    @Published public var isSyncingChat = false
    @Published public var isSendingChatMessage = false
    /// A message that's been sent to Chat but not confirmed by a refresh
    /// yet -- see sendChatMessage. Shown in the thread immediately (merged
    /// in alongside chatMessages by MessagesView) with a small spinner
    /// instead of a timestamp, so sending doesn't look like it did nothing
    /// while the request is in flight.
    @Published public var pendingChatMessages: [ChatMessageItem] = []
    /// Real name/photo for people seen in Chat (DM partners and message
    /// senders), keyed by their Chat user id ("users/{id}") -- see
    /// GooglePeopleClient. Missing an entry just means no photo/name could
    /// be resolved for that person; views fall back to an initials avatar.
    @Published public var directoryProfiles: [String: DirectoryProfile] = [:]

    @Published public var lastRefreshed: Date?

    /// Emoji overrides for the sidebar's classroom icons, keyed by course
    /// id -- a course with no entry here just shows the default book icon.
    /// Persisted immediately on change (see setCourseIcon) so a chosen
    /// emoji sticks across launches.
    @Published public var courseIcons: [String: String] = [:]

    /// Best-effort cross-service grouping -- see SubjectGroup for how (and
    /// how confidently) this matches a SchoolSoft subject to a Classroom
    /// course to a Chat space. Recomputed fresh from current state each
    /// time it's read, so it always reflects the latest sync.
    public var subjectGroups: [SubjectGroup] {
        SubjectMatcher.buildGroups(
            courses: classroomCourses,
            lessons: schedule?.lessons ?? [],
            coursework: classroomItems,
            messages: chatMessages
        )
    }

    public func subjectGroup(id: String) -> SubjectGroup? {
        subjectGroups.first { $0.id == id }
    }

    private let schoolSoftService: SchoolSoftScheduleService = SchoolSoftClient()
    private let auth = GoogleAuthManager.shared
    private lazy var classroomClient = GoogleClassroomClient(auth: auth)
    private lazy var chatClient = GoogleChatClient(auth: auth)
    private lazy var peopleClient = GooglePeopleClient(auth: auth)
    private let defaults = UserDefaults.standard

    /// The user's own real Chat display name (e.g. "Desmond Bergman"),
    /// learned from their own already-confirmed sent messages the first
    /// time one is seen (see refreshChat), and persisted so it's available
    /// immediately on future launches too -- used instead of a hardcoded
    /// "You" for the optimistic pending-message placeholder in
    /// sendChatMessage, so it doesn't visibly swap to the real name (and
    /// doesn't briefly render as "YO" in InitialsAvatar) once the message
    /// is confirmed. Getting this via a new Chat/People scope wasn't worth
    /// another round of OAuth Console friction when self-learning it from
    /// data we already fetch works just as well.
    private var ownChatDisplayName: String? {
        didSet {
            guard ownChatDisplayName != oldValue else { return }
            defaults.set(ownChatDisplayName, forKey: "ownChatDisplayName")
        }
    }

    private init() {
        loadCachedSnapshot()
        loadCourseIcons()
        ownChatDisplayName = defaults.string(forKey: "ownChatDisplayName")
    }

    public var hasSchoolSoftAccount: Bool {
        storedSchoolSoftCredentials() != nil
    }

    // MARK: - Refresh

    public func refreshAll() async {
        async let schoolSoft: Void = refreshSchoolSoft()
        async let classroom: Void = refreshClassroom()
        async let chat: Void = refreshChat()
        _ = await (schoolSoft, classroom, chat)
        lastRefreshed = .now
        persistSnapshot()
    }

    public func refreshSchoolSoft() async {
        guard let creds = storedSchoolSoftCredentials() else { return }
        isSyncingSchoolSoft = true
        defer { isSyncingSchoolSoft = false }
        do {
            let newSchedule = try await schoolSoftService.fetchSchedule(using: creds)
            schedule = newSchedule
            lunchMenu = try? await schoolSoftService.fetchLunchMenu(using: creds)
            schoolSoftError = nil
        } catch {
            schoolSoftError = error.localizedDescription
        }
    }

    public func refreshClassroom() async {
        guard auth.isSignedIn else {
            classroomItems = []
            classroomCourses = []
            classroomError = nil
            return
        }
        isSyncingClassroom = true
        defer { isSyncingClassroom = false }
        do {
            async let coursesTask = classroomClient.fetchCourses()
            async let itemsTask = classroomClient.fetchRecentCoursework()
            classroomCourses = try await coursesTask
            classroomItems = try await itemsTask
            classroomError = nil
        } catch {
            classroomError = error.localizedDescription
        }
    }

    public func refreshChat() async {
        guard auth.isSignedIn else {
            chatMessages = []
            chatSpaces = []
            directoryProfiles = [:]
            chatError = nil
            return
        }
        isSyncingChat = true
        defer { isSyncingChat = false }
        do {
            async let messages = chatClient.fetchRecentMessages()
            async let spaces = chatClient.fetchSpaces(selfUserID: auth.accountID)
            chatMessages = try await messages
            chatSpaces = try await spaces
            chatError = nil

            if let selfID = auth.accountID,
               let ownMessage = chatMessages.first(where: { $0.senderID == "users/\(selfID)" }) {
                ownChatDisplayName = ownMessage.senderDisplayName
            }

            let peopleToLookUp = Set(chatSpaces.compactMap(\.dmOtherUserID))
                .union(chatMessages.compactMap(\.senderID))
            directoryProfiles = await peopleClient.fetchProfiles(chatUserIDs: Array(peopleToLookUp))
        } catch {
            chatError = error.localizedDescription
        }
    }

    /// Name-search suggestions for Messages' "Add Chat" field -- see
    /// GooglePeopleClient.searchDirectory. Read-only, so unlike
    /// startDirectMessage below this doesn't touch any published state;
    /// the view just awaits it directly per keystroke (debounced there).
    public func searchChatDirectory(query: String) async -> [DirectoryPerson] {
        await peopleClient.searchDirectory(query: query)
    }

    /// Starts (or reuses) a direct message with someone by email who isn't
    /// in your conversation list yet, refreshes Chat so the new
    /// conversation and their profile show up, and returns the new space's
    /// id so the caller can select it straight away. Returns nil (and sets
    /// `chatError`) on failure -- e.g. no Chat account at that address.
    @discardableResult
    public func startDirectMessage(withEmail email: String) async -> String? {
        guard auth.isSignedIn else { return nil }
        isSyncingChat = true
        defer { isSyncingChat = false }
        do {
            let space = try await chatClient.startDirectMessage(withEmail: email, selfUserID: auth.accountID)
            await refreshChat()
            // spaces.list (and its own per-space member lookup) can lag a
            // moment right after a brand new space is created -- refreshChat
            // might not include the space at all yet, or might include it
            // but without the other person's name resolved (buildSpace's
            // member lookup, run fresh for every space during a normal
            // refresh, doesn't get the retries `space` above already went
            // through for exactly this situation). Either way, upsert our
            // already-resolved copy over whatever refreshChat found rather
            // than only filling the gap when the space is missing outright
            // -- otherwise a degraded entry from the bulk refresh can
            // silently win and the name/photo still won't show.
            chatSpaces.removeAll { $0.id == space.id }
            chatSpaces.insert(space, at: 0)

            // refreshChat's own photo lookup ran before we knew about this
            // person (or before their membership had resolved), so fetch
            // their profile directly using the id `space` already has.
            if let otherID = space.dmOtherUserID, directoryProfiles[otherID] == nil {
                let profiles = await peopleClient.fetchProfiles(chatUserIDs: [otherID])
                directoryProfiles.merge(profiles) { _, new in new }
            }

            // The retries inside chatClient.startDirectMessage cover the
            // common case, but Chat's membership propagation can
            // occasionally take longer than that short window -- rather
            // than make you notice and press the toolbar refresh button,
            // keep quietly re-checking just this one conversation in the
            // background for a while and fill in its real name/photo the
            // moment it's ready. (MessagesView animates on chatSpaces
            // changes, so this update fades in instead of popping in.)
            if space.dmOtherUserID == nil {
                pollForDirectMessageResolution(spaceID: space.id)
            }

            return space.id
        } catch {
            chatError = error.localizedDescription
            return nil
        }
    }

    /// Background follow-up for startDirectMessage above: re-fetches just
    /// one space, at widening intervals, until its other-person id
    /// resolves or we give up (~35s total). Silently does nothing if the
    /// space already resolved some other way (e.g. a manual refresh) or
    /// was removed by the time a check runs.
    private func pollForDirectMessageResolution(spaceID: String) {
        Task {
            let delaysSeconds: [UInt64] = [2, 3, 5, 7, 8, 10]
            for delay in delaysSeconds {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)

                guard let index = chatSpaces.firstIndex(where: { $0.id == spaceID }) else { return }
                guard chatSpaces[index].dmOtherUserID == nil else { return }

                guard let resolved = try? await chatClient.fetchSpace(id: spaceID, selfUserID: auth.accountID),
                      let otherID = resolved.dmOtherUserID else { continue }

                chatSpaces[index] = resolved
                if directoryProfiles[otherID] == nil {
                    let profiles = await peopleClient.fetchProfiles(chatUserIDs: [otherID])
                    directoryProfiles.merge(profiles) { _, new in new }
                }
                return
            }
        }
    }

    /// Sends `text` to the given space. Shows it in the thread right away
    /// as a pending message (see `pendingChatMessages`) rather than waiting
    /// on the network round trip and a full refresh before it appears at
    /// all -- that round trip is what actually takes a while, and there's
    /// no reason the UI has to sit still for it. Returns whether it
    /// ultimately succeeded; on failure, `chatError` is set with the reason
    /// and the pending message is removed rather than left stuck spinning.
    @discardableResult
    public func sendChatMessage(_ text: String, to space: ChatSpace) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let pending = ChatMessageItem(
            id: "pending-\(UUID().uuidString)",
            spaceID: space.id,
            spaceDisplayName: space.displayName,
            senderDisplayName: ownChatDisplayName ?? "You",
            senderID: auth.accountID.map { "users/\($0)" },
            text: trimmed,
            createTime: .now,
            isPending: true
        )
        pendingChatMessages.append(pending)

        isSendingChatMessage = true
        defer { isSendingChatMessage = false }
        do {
            try await chatClient.sendMessage(text: trimmed, to: space.id)
            await refreshChat()
            pendingChatMessages.removeAll { $0.id == pending.id }
            return true
        } catch {
            chatError = error.localizedDescription
            pendingChatMessages.removeAll { $0.id == pending.id }
            return false
        }
    }

    // MARK: - SchoolSoft credentials

    /// Mirrors the @AppStorage keys the Settings view writes, so both read
    /// from the same source of truth: URL/username in UserDefaults,
    /// password only ever in Keychain.
    public func storedSchoolSoftCredentials() -> SchoolSoftCredentials? {
        let url = defaults.string(forKey: "schoolURL") ?? ""
        let username = defaults.string(forKey: "username") ?? ""
        guard !url.isEmpty, !username.isEmpty, let password = KeychainHelper.get(for: username) else { return nil }
        return SchoolSoftCredentials(schoolURL: url, username: username, password: password)
    }

    public func saveSchoolSoftAccount(url: String, username: String, password: String) {
        defaults.set(url, forKey: "schoolURL")
        defaults.set(username, forKey: "username")
        KeychainHelper.save(password: password, for: username)
    }

    public func clearSchoolSoftAccount() {
        let username = defaults.string(forKey: "username") ?? ""
        if !username.isEmpty { KeychainHelper.delete(for: username) }
        defaults.removeObject(forKey: "schoolURL")
        defaults.removeObject(forKey: "username")
        schedule = nil
        lunchMenu = nil
    }

    // MARK: - Classroom icons

    /// Sets (or, with nil/empty, clears back to the default book icon) the
    /// emoji shown for a classroom in the sidebar.
    public func setCourseIcon(_ emoji: String?, for courseId: String) {
        if let emoji, !emoji.isEmpty {
            courseIcons[courseId] = emoji
        } else {
            courseIcons.removeValue(forKey: courseId)
        }
        guard let data = try? JSONEncoder().encode(courseIcons) else { return }
        defaults.set(data, forKey: "courseIcons")
    }

    private func loadCourseIcons() {
        guard let data = defaults.data(forKey: "courseIcons"),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        courseIcons = decoded
    }

    // MARK: - Disk cache

    private struct Snapshot: Codable {
        var schedule: Schedule?
        var lunchMenu: LunchMenu?
        var lastRefreshed: Date?
    }

    private var cacheDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Omnibus", isDirectory: true)
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent("dashboard-cache.json")
    }

    private func persistSnapshot() {
        let snapshot = Snapshot(schedule: schedule, lunchMenu: lunchMenu, lastRefreshed: lastRefreshed)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    private func loadCachedSnapshot() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        schedule = snapshot.schedule
        lunchMenu = snapshot.lunchMenu
        lastRefreshed = snapshot.lastRefreshed
    }
}
