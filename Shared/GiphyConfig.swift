import Foundation

/// GIPHY is used for the compose bar's GIF picker. Tenor (Google's GIF
/// API) stopped accepting new API clients in January 2026, and the other
/// commonly-suggested free alternative (Klipy) doesn't have a stable,
/// publicly documented API shape to build against -- GIPHY's does.
///
/// Get a free key at https://developers.giphy.com (Create an App > API,
/// not SDK). The "Beta" key GIPHY hands out immediately works fine for
/// personal use; full walkthrough in SETUP.md at the project root.
public enum GiphyConfig {
    public static let apiKey = "YOUR_GIPHY_API_KEY"
}
