import SwiftUI

/// Fallback for `PersonAvatar` below when there's no real photo to show:
/// a colored initials badge, the same way most chat apps handle a contact
/// with no picture. The color is derived from the name with a stable hash
/// (not Swift's randomized Hasher) so the same person keeps the same
/// color across app launches.
struct InitialsAvatar: View {
    var name: String
    var diameter: CGFloat = 36

    var body: some View {
        let label = Self.initials(for: name)
        let isEmoji = label.first?.isEmoji ?? false

        Circle()
            .fill(Self.color(for: name))
            .frame(width: diameter, height: diameter)
            .overlay {
                Text(label)
                    .font(.system(size: diameter * (isEmoji ? 0.55 : 0.4), weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Group chats named with a leading emoji (a common way to give a
        // group its own "picture" on the Chat website without uploading a
        // real image) -- show that emoji on its own rather than mashing it
        // together with a letter from the next word, which just came out
        // mangled/clipped in a circle this small.
        if let first = trimmed.first, first.isEmoji {
            return String(first)
        }

        let words = trimmed
            .split(separator: " ")
            .filter { !$0.isEmpty }
        if words.count >= 2 {
            return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return first.prefix(2).uppercased()
        }
        return "?"
    }

    private static let palette: [Color] = [
        .blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .cyan, .brown
    ]

    /// A simple djb2-style hash -- deterministic across runs, unlike
    /// Swift's built-in Hasher (which is seeded randomly per process).
    static func color(for name: String) -> Color {
        var hash: UInt32 = 5381
        for byte in name.utf8 {
            hash = (hash << 5) &+ hash &+ UInt32(byte)
        }
        let index = Int(hash % UInt32(palette.count))
        return palette[index]
    }
}

/// True for an emoji character, whether it's a single codepoint (like "🎉")
/// or a multi-scalar sequence joined with ZWJ/variation selectors (like a
/// skin-tone or family emoji) -- Swift still counts either as one
/// `Character` (grapheme cluster), so this checks the underlying scalars.
private extension Character {
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji
            && (firstScalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

/// A real profile picture when one's available (fetched via
/// GooglePeopleClient/OmnibusStore.directoryProfiles), falling back to
/// InitialsAvatar while it loads, if it fails to load, or if there's no
/// photo URL for this person at all -- so a missing/blocked lookup (e.g.
/// `directory.readonly` denied on a locked-down school account) never
/// leaves a blank circle.
struct PersonAvatar: View {
    var name: String
    var photoURL: URL?
    var diameter: CGFloat = 36

    var body: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                } else {
                    InitialsAvatar(name: name, diameter: diameter)
                }
            }
            .frame(width: diameter, height: diameter)
        } else {
            InitialsAvatar(name: name, diameter: diameter)
        }
    }
}
