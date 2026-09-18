import SwiftUI
import AppKit

/// Presented when you click a coursework item anywhere in Omnibus (Today's
/// due-soon list, Coursework, or a classroom's own page) -- keeps you inside
/// the app instead of bouncing out to the Classroom website. The website is
/// still one click away via "Open in Classroom," for when you actually need
/// to submit work there. Any files/links/videos/forms attached to the
/// assignment are listed here too, each opening straight to its own page
/// (Drive, YouTube, a form, whatever it is) without going through Classroom
/// first.
struct CourseworkDetailView: View {
    var item: ClassroomWorkItem
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workTypeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())

                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.courseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

            if let due = item.dueDate {
                Label {
                    Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(item.isOverdue ? .red : .primary)
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }
                .font(.subheadline)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else if item.materials.isEmpty {
                        DashboardEmptyText("No description was added for this item.")
                    }

                    if !item.materials.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Files")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            VStack(spacing: 4) {
                                ForEach(item.materials) { material in
                                    MaterialRow(material: material)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            Divider()

            HStack {
                Spacer()
                if let link = item.alternateLink {
                    Button {
                        NSWorkspace.shared.open(link)
                    } label: {
                        Label("Open in Classroom", systemImage: "arrow.up.right.square")
                    }
                }
                Button("Close") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var workTypeLabel: String {
        switch item.workType {
        case "ASSIGNMENT": return "Assignment"
        case "SHORT_ANSWER_QUESTION": return "Short answer"
        case "MULTIPLE_CHOICE_QUESTION": return "Multiple choice"
        case "COURSE_MATERIAL": return "Material"
        default: return "Coursework"
        }
    }
}

/// One attached file/link/video/form, opened in the browser (or the Drive/
/// Forms/YouTube app, whichever macOS routes it to) on click.
private struct MaterialRow: View {
    var material: ClassroomMaterial

    var body: some View {
        Button {
            NSWorkspace.shared.open(material.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: material.systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(material.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
