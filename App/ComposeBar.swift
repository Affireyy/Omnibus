import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @FocusState private var isDraftFocused: Bool

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
                        .focused($isDraftFocused)

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
            // Cmd+V is handled app-wide via OmnibusApp's replaced Paste
            // command (see its comment -- the OS default just beeps at a
            // plain text field for a file/image paste) -- only offer to
            // handle it while this is actually the focused message field,
            // so pasting elsewhere in the app (e.g. Settings) isn't
            // hijacked into attaching to whatever conversation happens to
            // be open here.
            .onChange(of: isDraftFocused) { _, focused in
                PasteCoordinator.shared.handler = focused ? { handlePasteFromClipboard() } : nil
            }
            .onDisappear {
                PasteCoordinator.shared.handler = nil
            }
            .sheet(isPresented: $isShowingGifPicker) {
                GifPickerView { url in attach(fileAt: url) }
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
        attach(fileAt: url)
    }

    /// Shared by every way a file can become the pending attachment
    /// (Finder picker, the GIF picker, and pasting) -- always runs it
    /// through the same known-restrictions check before accepting it.
    private func attach(fileAt url: URL) {
        if let reason = GoogleChatClient.blockedAttachmentReason(for: url) {
            attachmentError = reason
            return
        }
        attachmentError = nil
        attachedFileURL = url
    }

    /// Called by PasteCoordinator (via OmnibusApp's replaced Paste command)
    /// only while this is the focused message field. Reads NSPasteboard
    /// directly rather than relying on SwiftUI's onPasteCommand -- that
    /// modifier never actually fired here, since the default Edit menu's
    /// Paste already sends `paste:` straight to the focused NSTextField's
    /// field editor before onPasteCommand's own responder ever sees it.
    /// Returns true if the clipboard held a real file/image and this
    /// attached it; false means "nothing for me here," so the caller
    /// falls back to a normal text paste.
    private func handlePasteFromClipboard() -> Bool {
        let pasteboard = NSPasteboard.general

        // A real file (e.g. copied in Finder) -- preferred over raw image
        // bytes when both are somehow present, since it keeps the
        // attachment's real filename instead of a generic "pasted-*".
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            attach(fileAt: url)
            return true
        }

        // Raw image bytes with no file of their own yet (e.g. "Copy
        // Image" from a browser, or a screenshot tool's clipboard
        // capture) -- write them to one so they can go through the same
        // attachment pipeline as everything else.
        guard let imageType = pasteboard.types?.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true }),
              let data = pasteboard.data(forType: imageType) else {
            return false
        }
        let ext = UTType(imageType.rawValue)?.preferredFilenameExtension ?? "png"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasted-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: tempURL, options: .atomic)
            attach(fileAt: tempURL)
            return true
        } catch {
            return false
        }
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
