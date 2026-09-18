import SwiftUI

/// The "send a Chat message" control shown under the selected conversation
/// in Messages. When `preferredSpaceID` is set it sends straight to that
/// conversation (no picker needed); without one it falls back to a "send
/// to..." picker over every space, for reuse elsewhere later.
struct ComposeBar: View {
    @EnvironmentObject var store: OmnibusStore
    var preferredSpaceID: String?

    @State private var selectedSpace: ChatSpace?
    @State private var draft = ""

    var body: some View {
        if store.chatSpaces.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Only show the "send to" picker when nothing has already
                // narrowed it down -- inside a specific conversation, who
                // you're sending to is obvious from context.
                if preferredSpaceID == nil {
                    Picker("Send to", selection: $selectedSpace) {
                        ForEach(store.chatSpaces) { space in
                            Text(space.displayName).tag(Optional(space))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }

                HStack(spacing: 8) {
                    TextField("Message…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)

                    Button(action: send) {
                        if store.isSendingChatMessage {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        store.isSendingChatMessage
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedSpace == nil
                    )
                }
            }
            .onAppear { syncSelection() }
            .onChange(of: store.chatSpaces) { _, _ in syncSelection() }
            .onChange(of: preferredSpaceID) { _, _ in syncSelection() }
        }
    }

    private func send() {
        guard let space = selectedSpace else { return }
        let text = draft
        draft = ""
        Task { await store.sendChatMessage(text, to: space) }
    }

    private func syncSelection() {
        if let preferredSpaceID, let match = store.chatSpaces.first(where: { $0.id == preferredSpaceID }) {
            selectedSpace = match
            return
        }
        if selectedSpace == nil || !store.chatSpaces.contains(where: { $0.id == selectedSpace?.id }) {
            selectedSpace = store.chatSpaces.first
        }
    }
}
