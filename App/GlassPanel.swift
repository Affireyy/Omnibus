import SwiftUI

/// The single glass surface every screen is drawn on -- deliberately just
/// one panel per screen (not one per data source) so Schedule, Coursework,
/// and Chat read as facets of one app rather than three bolted-together
/// widgets. Internal divisions within a screen use SectionHeader + Divider,
/// not separate glass panels.
struct GlassPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassSurface(cornerRadius: 24)
    }
}

/// Small heading used to divide a GlassPanel into sections without
/// introducing another visual box.
struct SectionHeader: View {
    var title: String
    var systemImage: String
    var trailingText: String?

    init(_ title: String, systemImage: String, trailingText: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.trailingText = trailingText
    }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Shared "nothing here yet" style so every screen reads consistently.
struct DashboardEmptyText: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
