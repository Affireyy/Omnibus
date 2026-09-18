import SwiftUI
import AppKit

/// The "send a Chat message" control shown under the selected conversation
/// in Messages. When `preferredSpaceID` is set it sends straight to that
/// conversation (no picker needed); without one it falls back to a "send
/// to..." picker over every space, for reuse elsewhere later.
struct ComposeBar: View {
    @EnvironmentObject var store: OmnibusStore
    var preferredSpaceID: String?

    @State private var selectedSpace: ChatSpace?
    @State private var draft = ""
    @State private var attachedFileURL: URL?
    @State private var attachmentError: String?
    @State private var isShowingGifPicker = false

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

                if let attachedFileURL {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(attachedFileURL.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            self.attachedFileURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if let attachmentError {
                    Text(attachmentError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    Menu {
                        Button("GIFs") { isShowingGifPicker = true }
                        Button("Attach Files") { chooseFile() }
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(store.isSendingChatMessage)
                    .help("Attach a GIF or file")

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
                        || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedFileURL == nil)
                        || selectedSpace == nil
                    )
                }
            }
            .onAppear { syncSelection() }
            .onChange(of: store.chatSpaces) { _, _ in syncSelection() }
            .onChange(of: preferredSpaceID) { _, _ in syncSelection() }
            .sheet(isPresented: $isShowingGifPicker) {
                GifPickerView { url in
                    if let reason = GoogleChatClient.blockedAttachmentReason(for: url) {
                        attachmentError = reason
                        return
                    }
                    attachmentError = nil
                    attachedFileURL = url
                }
            }
        }
    }

    /// Opens a plain file picker (the app isn't sandboxed -- see
    /// AUTOUPDATE.md -- so no security-scoped bookmark dance is needed to
    /// read the chosen file back later) and checks it against Chat's known
    /// restrictions right away, rather than waiting until send to find out
    /// it won't be accepted.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let reason = GoogleChatClient.blockedAttachmentReason(for: url) {
            attachmentError = reason
            return
        }
        attachmentError = nil
        attachedFileURL = url
    }

    private func send() {
        guard let space = selectedSpace else { return }
        let text = draft
        let attachment = attachedFileURL
        draft = ""
        attachedFileURL = nil
        attachmentError = nil
        Task {
            let sent = await store.sendChatMessage(text, attachmentFileURL: attachment, to: space)
            // Restore just the attachment on failure -- text is harder to
            // restore predictably since the person may already be typing
            // something new by the time the send comes back.
            if !sent, let attachment {
                attachedFileURL = attachment
            }
        }
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
