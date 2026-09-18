import SwiftUI
import AppKit

/// Presented from the sidebar's "Edit Icon…" context menu on a classroom --
/// lets you replace its default book icon with any emoji. Typing/pasting
/// one works directly, and "Choose Emoji…" pops open macOS's own character
/// picker (the same one behind Cmd+Ctrl+Space) so you don't have to hunt
/// for a keyboard shortcut you might not remember.
struct CourseIconEditorView: View {
    var course: ClassroomCourse
    var currentEmoji: String?
    var onSave: (String?) -> Void
    var onDismiss: () -> Void

    @State private var emojiText: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Classroom Icon")
                        .font(.title3.weight(.semibold))
                    Text(course.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

            HStack(spacing: 14) {
                iconPreview
                    .frame(width: 46, height: 46)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Paste or type an emoji", text: $emojiText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFieldFocused)
                        .onChange(of: emojiText) { _, newValue in
                            // An icon is one glyph -- if the picker (or a
                            // paste) drops in more than one, keep only the
                            // most recent so the field never fills up with
                            // a string that wouldn't read as an "icon."
                            if let last = newValue.last, newValue.count > 1 {
                                emojiText = String(last)
                            }
                        }
                        .onSubmit(save)

                    Button {
                        isFieldFocused = true
                        NSApp.orderFrontCharacterPalette(nil)
                    } label: {
                        Label("Choose Emoji…", systemImage: "face.smiling")
                            .font(.caption)
                    }
                }
            }

            HStack {
                Button("Use Default Book Icon") {
                    emojiText = ""
                }
                .disabled(emojiText.isEmpty)

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            emojiText = currentEmoji ?? ""
            isFieldFocused = true
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        if emojiText.isEmpty {
            Image(systemName: "book.closed")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        } else {
            Text(emojiText)
                .font(.system(size: 26))
        }
    }

    private func save() {
        let trimmed = emojiText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed)
        onDismiss()
    }
}
