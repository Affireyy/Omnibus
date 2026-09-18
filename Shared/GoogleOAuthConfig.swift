import Foundation

/// Fill these in after creating OAuth credentials in Google Cloud Console
/// (APIs & Services > Credentials > Create Credentials > OAuth client ID >
/// Application type: **iOS**). The "iOS" client type is what lets Google
/// redirect back into a native app via a custom URL scheme -- no local web
/// server needed, unlike the "Desktop app" client type. Full walkthrough in
/// SETUP.md at the project root.
public enum GoogleOAuthConfig {
    /// e.g. "123456789-abc123.apps.googleusercontent.com"
    public static let clientID = "922556128890-mggq7hamqkik2htt4n9evpo5m3hh5jtl.apps.googleusercontent.com"

    /// The reversed form of clientID, e.g. "com.googleusercontent.apps.123456789-abc123".
    /// Must exactly match the CFBundleURLSchemes entry in project.yml (App/Info.plist) --
    /// update both places, then run `xcodegen generate` again.
    public static let redirectURIScheme = "com.googleusercontent.apps.922556128890-mggq7hamqkik2htt4n9evpo5m3hh5jtl"

    public static var redirectURI: String { "\(redirectURIScheme):/oauth2redirect" }

    /// Mostly read-only: the exceptions are `chat.messages` (lets Omnibus
    /// send messages as you from the compose bar) and `chat.spaces.create`
    /// (lets it start a new direct message from Messages' "Add Chat"
    /// button, for someone who's never messaged you before). Everything
    /// else only displays data, never modifies it.
    ///
    /// `chat.memberships.readonly` and `directory.readonly` are for
    /// resolving a direct message's real name and photo (see
    /// GooglePeopleClient.swift) -- `directory.readonly` in particular is a
    /// more sensitive scope, and on a school/work Google Workspace account
    /// a domain admin may block it even though the rest of Omnibus works
    /// fine; if so, DMs just keep the generic "Direct message" label and
    /// initials-only avatar instead of failing.
    public static let scopes = [
        "openid",
        "email",
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.announcements.readonly",
        "https://www.googleapis.com/auth/chat.spaces.readonly",
        "https://www.googleapis.com/auth/chat.spaces.create",
        "https://www.googleapis.com/auth/chat.messages",
        "https://www.googleapis.com/auth/chat.memberships.readonly",
        "https://www.googleapis.com/auth/directory.readonly"
    ]

    public static var isConfigured: Bool {
        !clientID.hasPrefix("REPLACE_") && !redirectURIScheme.hasPrefix("REPLACE_")
    }
}
