import SwiftUI

/// Sheet from Messages' "Add Chat" button -- lets you start a conversation
/// with someone who's never messaged you before, so they're not in
/// fetchSpaces' list yet (Chat's spaces.list only returns spaces you're
/// already a member of). Type a name and pick from live suggestions
/// (searches your school/work Google directory), or type a full email
/// directly and press Start Chat -- the directory search only covers
/// people in your own domain, so a direct email is the fallback for
/// anyone outside it. Reuses an existing DM instead of creating a
/// duplicate if one's already there.
struct NewChatSheet: View {
    /// Returns whether a chat was started (or found) successfully.
    var onStart: (String) async -> Bool
    /// Name-search suggestions as the person types.
    var onSearch: (String) async -> [DirectoryPerson]
    var onDismiss: () -> Void

    @State private var query: String = ""
    @State private var results: [DirectoryPerson] = []
    @State private var isSearching = false
    @State private var isStarting = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            TextField("Search by name, or enter an email", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .disableAutocorrection(true)
                .onSubmit(startWithTypedEmail)
                .onChange(of: query) { _, newValue in scheduleSearch(for: newValue) }

            suggestions

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    startWithTypedEmail()
                } label: {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("Start Chat")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!looksLikeEmail(query) || isStarting)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { isFieldFocused = true }
        .onDisappear { searchTask?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Chat")
                    .font(.title3.weight(.semibold))
                Text("Start a conversation with someone you haven't messaged before.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if isSearching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !results.isEmpty {
            VStack(spacing: 2) {
                ForEach(results) { person in
                    DirectoryPersonRow(person: person) {
                        start(withEmail: person.email)
                    }
                }
            }
        } else if looksLikeEmail(trimmed) {
            DashboardEmptyText("No one found by that name -- Start Chat will message this address directly.")
        } else if trimmed.count >= 2 {
            DashboardEmptyText("No one in your school found matching \"\(trimmed)\".")
        }
    }

    // MARK: - Search

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !looksLikeEmail(trimmed) else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            // Debounce -- wait for a pause in typing before searching, so
            // every keystroke doesn't fire its own request.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await onSearch(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    // MARK: - Starting the chat

    private func looksLikeEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return !trimmed.hasPrefix("@") && domain.contains(".") && !domain.hasSuffix(".")
    }

    private func startWithTypedEmail() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeEmail(trimmed) else { return }
        start(withEmail: trimmed)
    }

    private func start(withEmail email: String) {
        guard !isStarting else { return }
        isStarting = true
        errorText = nil
        Task {
            let succeeded = await onStart(email)
            isStarting = false
            if succeeded {
                onDismiss()
            } else {
                errorText = "Couldn't start a chat with that address -- check it's a Google Chat account you can message."
            }
        }
    }
}

/// One name-search suggestion -- tapping it starts the chat right away,
/// like picking a Spotlight result.
private struct DirectoryPersonRow: View {
    var person: DirectoryPerson
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                PersonAvatar(name: person.displayName, photoURL: person.photoURL, diameter: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(person.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
