import SwiftUI
import AppKit

/// Messages, laid out like Chat's own website: a resizable list of
/// conversations on the left -- each with a real avatar when one's
/// available and a preview of its last message -- and the selected
/// conversation's thread on the right.
///
/// The split is hand-built (a plain divider you drag) rather than
/// AppKit's HSplitView, which draws its own separate boxed/materialed
/// pane -- that read as a window floating inside the glass panel instead
/// of one continuous surface.
struct MessagesView: View {
    @EnvironmentObject var store: OmnibusStore
    @EnvironmentObject var auth: GoogleAuthManager
    var searchText: String

    @State private var selectedSpaceID: String?
    @State private var listWidth: CGFloat = 280
    @State private var dragStartWidth: CGFloat?
    @State private var isShowingNewChat = false

    private let minListWidth: CGFloat = 220
    private let minDetailWidth: CGFloat = 320
    private let dividerHitWidth: CGFloat = 10

    var body: some View {
        GlassPanel {
            SectionHeader(
                "Messages",
                systemImage: "bubble.left.and.bubble.right",
                trailingText: auth.isSignedIn ? "\(store.chatSpaces.count)" : nil
            )

            // Always available when signed in -- not just once there's
            // already a conversation list to sit above -- since starting
            // your very first chat needs it too.
            if auth.isSignedIn {
                HStack {
                    Spacer()
                    Button {
                        isShowingNewChat = true
                    } label: {
                        Label("Add Chat", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Group {
                if !auth.isSignedIn {
                    centeredState { DashboardEmptyText("Sign in with Google in Settings to see messages.") }
                } else if store.isSyncingChat && store.chatSpaces.isEmpty {
                    centeredState { ProgressView().controlSize(.small) }
                } else if store.chatSpaces.isEmpty {
                    centeredState { DashboardEmptyText("No conversations yet.") }
                } else if filteredSpaces.isEmpty {
                    centeredState { DashboardEmptyText("Nothing matches \"\(searchText)\".") }
                } else {
                    splitView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = store.chatError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
        // Fills the whole detail area (RootView gives Messages a plain
        // expanding frame instead of the scroll view every other screen
        // sits in -- Messages already scrolls itself, in both panes, so a
        // panel that stops at its content height instead of filling the
        // window just reads as a small floating card).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncSelection() }
        .onChange(of: store.chatSpaces) { _, _ in syncSelection() }
        .onChange(of: searchText) { _, _ in syncSelection() }
        .sheet(isPresented: $isShowingNewChat) {
            NewChatSheet(
                onStart: { email in
                    guard let newSpaceID = await store.startDirectMessage(withEmail: email) else { return false }
                    selectedSpaceID = newSpaceID
                    return true
                },
                onSearch: { query in await store.searchChatDirectory(query: query) },
                onDismiss: { isShowingNewChat = false }
            )
        }
    }

    /// Loading/empty/sign-in placeholders, vertically centered in whatever
    /// space Messages has been given rather than pinned to the top with a
    /// dead gap below -- same idea as Mail's "No Mailbox Selected".
    @ViewBuilder
    private func centeredState<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var splitView: some View {
        GeometryReader { geo in
            let maxListWidth = max(minListWidth, geo.size.width - minDetailWidth - dividerHitWidth)
            HStack(spacing: 0) {
                conversationList
                    .frame(width: min(listWidth, maxListWidth))

                divider

                conversationDetail
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Draggable divider

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 4)
            .frame(width: dividerHitWidth)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = dragStartWidth ?? listWidth
                        if dragStartWidth == nil { dragStartWidth = listWidth }
                        listWidth = max(minListWidth, base + value.translation.width)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }

    // MARK: - Left: conversation list

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredSpaces) { space in
                    ConversationRow(
                        space: space,
                        photoURL: photoURL(for: space),
                        lastMessage: lastMessage(for: space),
                        isSelected: space.id == selectedSpaceID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedSpaceID = space.id }
                }
            }
            .padding(6)
        }
        // A brand new conversation's real name/photo can arrive a little
        // after it first shows up (see OmnibusStore.startDirectMessage /
        // pollForDirectMessageResolution) -- fade the swap in instead of
        // popping it in so it reads as "settling in," not a glitch.
        .animation(.easeInOut(duration: 0.3), value: store.chatSpaces)
    }

    // MARK: - Right: selected conversation thread

    @ViewBuilder
    private var conversationDetail: some View {
        if let space = selectedSpace {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    PersonAvatar(name: space.displayName, photoURL: photoURL(for: space), diameter: 30)
                    Text(space.displayName)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 10)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        let thread = threadMessages(for: space)
                        if thread.isEmpty {
                            DashboardEmptyText("No recent messages in this conversation.")
                                .padding(.top, 10)
                        } else {
                            ForEach(thread) { message in
                                ThreadMessageRow(
                                    message: message,
                                    photoURL: photoURL(for: message),
                                    isOwnMessage: isOwnMessage(message)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
                // A just-sent message appears instantly as pending (small
                // spinner, dimmed text) and is then replaced by the real,
                // confirmed one once refreshChat catches up -- animate both
                // that appearance and the swap instead of letting them pop.
                .animation(.easeInOut(duration: 0.2), value: store.pendingChatMessages)
                .animation(.easeInOut(duration: 0.2), value: store.chatMessages)

                Divider()
                ComposeBar(preferredSpaceID: space.id)
                    .padding(.top, 10)
            }
            .padding(.leading, 14)
            .animation(.easeInOut(duration: 0.3), value: store.chatSpaces)
        } else {
            DashboardEmptyText("Select a conversation.")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Data helpers

    private var filteredSpaces: [ChatSpace] {
        let base = store.chatSpaces.filter { space in
            searchText.isEmpty
            || space.displayName.localizedCaseInsensitiveContains(searchText)
            || store.chatMessages.contains {
                $0.spaceID == space.id && $0.text.localizedCaseInsensitiveContains(searchText)
            }
        }
        return base.sorted { lhs, rhs in
            switch (lastMessage(for: lhs)?.createTime, lastMessage(for: rhs)?.createTime) {
            case let (l?, r?): return l > r
            case (nil, nil): return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    private var selectedSpace: ChatSpace? {
        store.chatSpaces.first { $0.id == selectedSpaceID }
    }

    /// Confirmed messages for a space, plus any still-pending ones that
    /// don't yet have a confirmed counterpart. Once `refreshChat()` pulls
    /// in the real, server-confirmed message, its (senderID, text) pair
    /// filters the matching pending bubble out here immediately -- so the
    /// two can never both be visible at once. Relying only on
    /// `sendChatMessage` removing the pending entry from
    /// `pendingChatMessages` left a window open: `refreshChat()` sets
    /// `chatMessages` several suspension points before that removal runs,
    /// and a SwiftUI redraw landing in that window showed both the real
    /// message and the pending one stacked in the thread.
    private func mergedMessages(for space: ChatSpace) -> [ChatMessageItem] {
        let confirmed = store.chatMessages.filter { $0.spaceID == space.id }
        let confirmedKeys = Set(confirmed.map { "\($0.senderID ?? "")|\($0.text)" })
        let pending = store.pendingChatMessages.filter {
            $0.spaceID == space.id && !confirmedKeys.contains("\($0.senderID ?? "")|\($0.text)")
        }
        return confirmed + pending
    }

    private func threadMessages(for space: ChatSpace) -> [ChatMessageItem] {
        mergedMessages(for: space).sorted { $0.createTime < $1.createTime }
    }

    private func lastMessage(for space: ChatSpace) -> ChatMessageItem? {
        mergedMessages(for: space).max { $0.createTime < $1.createTime }
    }

    private func photoURL(for space: ChatSpace) -> URL? {
        guard let id = space.dmOtherUserID else { return nil }
        return store.directoryProfiles[id]?.photoURL
    }

    private func photoURL(for message: ChatMessageItem) -> URL? {
        guard let id = message.senderID else { return nil }
        return store.directoryProfiles[id]?.photoURL
    }

    /// A message this device sent -- always true for a still-pending one
    /// (it can only ever be ours), otherwise a match against our own
    /// signed-in account id. Drives ThreadMessageRow's left/right layout.
    private func isOwnMessage(_ message: ChatMessageItem) -> Bool {
        if message.isPending { return true }
        guard let senderID = message.senderID, let accountID = auth.accountID else { return false }
        return senderID == "users/\(accountID)"
    }

    /// Keeps the selection pointed at a conversation that's actually still
    /// in view -- picks the most recent one by default, and re-picks if a
    /// search narrows the list past the current selection.
    private func syncSelection() {
        if let selectedSpaceID, filteredSpaces.contains(where: { $0.id == selectedSpaceID }) {
            return
        }
        selectedSpaceID = filteredSpaces.first?.id
    }
}

// MARK: - Conversation list row

private struct ConversationRow: View {
    var space: ChatSpace
    var photoURL: URL?
    var lastMessage: ChatMessageItem?
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            PersonAvatar(name: space.displayName, photoURL: photoURL, diameter: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(space.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let lastMessage {
                    Text(lastMessage.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No recent messages")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if let lastMessage {
                Text(lastMessage.createTime.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

// MARK: - Thread message row

private struct ThreadMessageRow: View {
    var message: ChatMessageItem
    var photoURL: URL?
    /// Puts this row on the right (your own messages) vs. the left
    /// (everyone else's), the same convention every chat app uses.
    var isOwnMessage: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isOwnMessage {
                PersonAvatar(name: message.senderDisplayName, photoURL: photoURL, diameter: 30)
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(message.senderDisplayName)
                        .font(.caption.weight(.semibold))
                    if message.isPending {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text(message.createTime.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let imageAttachmentURL = message.imageAttachmentURL {
                    AuthenticatedRemoteImage(url: imageAttachmentURL, requiresAuth: message.imageAttachmentRequiresAuth)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(message.isPending ? .secondary : .primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isOwnMessage ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
            }
            .frame(maxWidth: 440, alignment: isOwnMessage ? .trailing : .leading)

            if isOwnMessage {
                PersonAvatar(name: message.senderDisplayName, photoURL: photoURL, diameter: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwnMessage ? .trailing : .leading)
    }
}
