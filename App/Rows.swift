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

/// Loads an image from a URL (optionally with a bearer token) and renders
/// it through AnimatedOrStaticImage above so GIFs actually animate. This
/// is the shared plumbing behind both AuthenticatedRemoteImage below
/// (Chat's own uploaded attachments, which need Chat's OAuth token) and
/// the GIF picker's preview grid (plain public GIPHY/Tenor URLs, which
/// don't).
struct RemoteAnimatedImage: View {
    var url: URL
    var authToken: String? = nil
    /// When both are finite, the loaded image gets an explicit, computed
    /// `.frame(width:height:)` that fits within this box while keeping
    /// its own aspect ratio -- more reliable here than SwiftUI's
    /// `.aspectRatio(_:contentMode:)` modifier, which doesn't negotiate
    /// size the same way for an NSViewRepresentable as it does for a
    /// plain SwiftUI Image, and was cropping GIFs instead of fitting the
    /// whole picture in them. Left `.infinity` (the default) for a grid
    /// tile, where the caller (the GIF picker) already bounds this with
    /// its own outer `.frame` + `.clipped()`.
    var maxWidth: CGFloat = .infinity
    var maxHeight: CGFloat = .infinity
    /// When set, the loaded image becomes tappable and calls this with
    /// itself instead of doing nothing -- left nil in the GIF picker,
    /// where the whole tile is already a Button of its own (a second,
    /// unconditional tap recognizer here would fight that Button for the
    /// gesture and could break picking a GIF entirely).
    var onTap: ((NSImage) -> Void)? = nil

    @State private var image: NSImage?
    @State private var failed = false
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let image {
                imageContent(image)
            } else if failed {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .task(id: url) { await load() }
    }

    @ViewBuilder
    private func imageContent(_ image: NSImage) -> some View {
        let sized = Group {
            if maxWidth.isFinite && maxHeight.isFinite {
                let fitted = Self.fittedSize(for: image.size, maxWidth: maxWidth, maxHeight: maxHeight)
                AnimatedOrStaticImage(image: image)
                    .frame(width: fitted.width, height: fitted.height)
            } else {
                AnimatedOrStaticImage(image: image)
                    .aspectRatio(image.size, contentMode: .fit)
            }
        }
        if let onTap {
            sized
                .contentShape(Rectangle())
                .onTapGesture { onTap(image) }
        } else {
            sized
        }
    }

    /// The largest size that fits `imageSize` inside the given box while
    /// keeping its aspect ratio -- plain letterbox-fit math, computed
    /// ourselves rather than leant on a SwiftUI layout modifier.
    private static func fittedSize(for imageSize: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: min(maxWidth, 120), height: min(maxHeight, 90))
        }
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func load() async {
        guard loadedURL != url else { return }
        failed = false
        image = nil
        do {
            var request = URLRequest(url: url)
            if let authToken {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let nsImage = NSImage(data: data) else {
                failed = true
                return
            }
            image = nsImage
            loadedURL = url
        } catch {
            failed = true
        }
    }
}

/// A Chat message's image (a real uploaded attachment, or a GIF sent
/// through Chat's own native "Add GIF" button -- see
/// ChatMessageItem.imageAttachmentRequiresAuth for which is which). An
/// uploaded attachment's Media API URL needs the same bearer token as
/// every other Chat API call; a native GIF pick's URL is already a plain
/// public one and must NOT get our Chat token (wrong host entirely).
struct AuthenticatedRemoteImage: View {
    var url: URL
    var requiresAuth: Bool = true
    var maxWidth: CGFloat = 240
    var maxHeight: CGFloat = 240
    /// Forwarded straight to RemoteAnimatedImage -- see its own onTap for
    /// why this is opt-in rather than always attaching a tap gesture.
    var onTap: ((NSImage) -> Void)? = nil

    @State private var token: String?
    @State private var tokenFailed = false

    var body: some View {
        Group {
            if !requiresAuth {
                RemoteAnimatedImage(url: url, maxWidth: maxWidth, maxHeight: maxHeight, onTap: onTap)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let token {
                RemoteAnimatedImage(url: url, authToken: token, maxWidth: maxWidth, maxHeight: maxHeight, onTap: onTap)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if tokenFailed {
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
                    .task { await loadToken() }
            }
        }
    }

    private func loadToken() async {
        do {
            token = try await GoogleAuthManager.shared.validAccessToken()
        } catch {
            tokenFailed = true
        }
    }
}

/// A full-size, zoomable look at a message's image, opened by tapping it
/// in the thread (see ThreadMessageRow) -- shown centered over the whole
/// window instead of the small inline bubble size. Scroll/pinch (trackpad
/// magnification) zooms, drag pans once zoomed in, and double-clicking
/// toggles between fit and a closer look. Click the dimmed background or
/// the close button, or press Escape, to dismiss.
struct ImageZoomOverlay: View {
    var image: NSImage
    var onDismiss: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            AnimatedOrStaticImage(image: image)
                .aspectRatio(image.size, contentMode: .fit)
                .scaleEffect(zoom)
                .offset(offset)
                .padding(48)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = min(max(lastZoom * value, 1), 6)
                        }
                        .onEnded { _ in
                            lastZoom = zoom
                            if zoom <= 1 {
                                zoom = 1
                                lastZoom = 1
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoom > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if zoom > 1 {
                            zoom = 1
                            lastZoom = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            zoom = 2.5
                            lastZoom = 2.5
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
        }
        // Escape closes it too, not just clicking away -- the usual
        // expectation for anything that opens over the whole window.
        .onExitCommand(perform: onDismiss)
    }
}
