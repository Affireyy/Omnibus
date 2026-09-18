import SwiftUI
import AppKit

/// Shared row views used across Today / Schedule / Coursework / Messages /
/// Subject screens, so the same kind of item always looks the same no
/// matter which screen it's shown on -- another small piece of "this is
/// one app," not three.

struct LessonRow: View {
    var lesson: Lesson
    var showsSubject: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(lesson.isActive() ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                if showsSubject {
                    Text(lesson.subject)
                        .font(.subheadline.weight(.medium))
                }
                Text([lesson.formattedTimeRange, lesson.room].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            if lesson.isActive() {
                Text("Now")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

struct ClassroomRow: View {
    var item: ClassroomWorkItem
    var showsCourse: Bool = true
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if showsCourse {
                        Text(item.courseName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let due = item.dueDate {
                        Text(showsCourse ? "·  Due \(due.formatted(date: .abbreviated, time: .omitted))" : "Due \(due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(item.isOverdue ? .red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            CourseworkDetailView(item: item) { showingDetail = false }
        }
    }
}

struct ChatRow: View {
    var message: ChatMessageItem
    var showsSpace: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(message.senderDisplayName)
                    .font(.caption.weight(.semibold))
                if showsSpace {
                    Text("in \(message.spaceDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(message.createTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.text)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
    }
}
/// Wraps NSImageView (rather than SwiftUI's Image(nsImage:), which only
/// ever shows a GIF's first frame) so an animated GIF attachment actually
/// animates, the same way it would in Finder's Quick Look or a browser.
struct AnimatedOrStaticImage: NSViewRepresentable {
    var image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
        }
    }
}

/// A Chat message's image attachment (a photo, or a GIF sent via the
/// compose bar's GIF picker) -- Chat's thumbnailUri/downloadUri both need
/// the same bearer token as every other Chat API call, so plain SwiftUI
/// AsyncImage(url:) (no custom headers) can't load them directly. This
/// fetches the bytes itself with GoogleAuthManager's token, then renders
/// through AnimatedOrStaticImage above so GIFs actually animate instead
/// of freezing on their first frame.
struct AuthenticatedRemoteImage: View {
    var url: URL
    var maxWidth: CGFloat = 240
    var maxHeight: CGFloat = 240

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                AnimatedOrStaticImage(image: image)
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if failed {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 120, height: 90)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 120, height: 90)
                    .overlay { ProgressView().controlSize(.small) }
                    .task { await load() }
            }
        }
    }

    private func load() async {
        do {
            let token = try await GoogleAuthManager.shared.validAccessToken()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let nsImage = NSImage(data: data) else {
                failed = true
                return
            }
            image = nsImage
        } catch {
            failed = true
        }
    }
}
