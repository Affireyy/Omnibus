import Foundation
import AuthenticationServices
import CryptoKit
import Security
#if canImport(AppKit)
import AppKit
#endif

public struct GoogleTokens: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var scope: String?
}

public enum GoogleAuthError: LocalizedError, Sendable {
    case notConfigured
    case cancelled
    case invalidCallback
    case tokenExchangeFailed(String)
    case noRefreshToken

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google sign-in isn't configured yet. Add your OAuth client ID in Shared/GoogleOAuthConfig.swift (see SETUP.md)."
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidCallback:
            return "Google's sign-in response was missing an authorization code."
        case .tokenExchangeFailed(let reason):
            return "Could not complete Google sign-in: \(reason)"
        case .noRefreshToken:
            return "Google didn't return a refresh token. Sign out and back in -- if this keeps happening, remove any prior consent for this app at myaccount.google.com/permissions and try again."
        }
    }
}

/// Handles the whole Google OAuth 2.0 + PKCE lifecycle for both Classroom
/// and Chat: presenting the consent screen, exchanging the returned code for
/// tokens, refreshing silently when expired, and storing everything in
/// Keychain via the shared `KeychainHelper` (never UserDefaults/plaintext).
///
/// This performs "user" OAuth (acting as the signed-in person, read-only),
/// not app/bot authentication -- appropriate for a personal dashboard that
/// just displays your own coursework and messages.
@MainActor
public final class GoogleAuthManager: NSObject, ObservableObject {
    public static let shared = GoogleAuthManager()

    @Published public private(set) var isSignedIn: Bool
    @Published public private(set) var accountEmail: String?
    /// Google's stable numeric id for the signed-in account (the OIDC
    /// `sub` claim) -- the same id space Chat's `users/{id}` and the
    /// People API's `people/{id}` use, so this is how we recognize "you"
    /// when figuring out who the *other* person in a DM is.
    @Published public private(set) var accountID: String?
    @Published public private(set) var lastError: String?

    private let tokenAccount = "google-oauth-tokens"
    private let emailAccount = "google-oauth-email"
    private let idAccount = "google-oauth-account-id"
    private var webSession: ASWebAuthenticationSession?

    private override init() {
        isSignedIn = KeychainHelper.get(for: "google-oauth-tokens") != nil
        accountEmail = KeychainHelper.get(for: "google-oauth-email")
        accountID = KeychainHelper.get(for: "google-oauth-account-id")
        super.init()
    }

    // MARK: - Sign in / out

    public func signIn() async throws {
        guard GoogleOAuthConfig.isConfigured else { throw GoogleAuthError.notConfigured }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        do {
            let callbackURL = try await presentSession(url: components.url!, scheme: GoogleOAuthConfig.redirectURIScheme)

            guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
                  returnedState == state,
                  let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw GoogleAuthError.invalidCallback
            }

            let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)
            // Google can silently drop a requested scope instead of
            // erroring or re-prompting -- most often because a Workspace
            // domain admin hasn't allow-listed this app for it. Comparing
            // what we asked for against what actually came back is the
            // only way to tell that apart from a real code/Console bug.
            let granted = Set((tokens.scope ?? "").split(separator: " ").map(String.init))
            let requested = Set(GoogleOAuthConfig.scopes)
            let missing = requested.subtracting(granted)
            print("[GoogleAuthManager] granted scopes: \(granted.sorted())")
            if !missing.isEmpty {
                print("[GoogleAuthManager] MISSING scopes (requested but not granted): \(missing.sorted())")
            }
            try store(tokens)
            isSignedIn = true
            lastError = nil
            await refreshAccountProfile()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    public func signOut() {
        KeychainHelper.delete(for: tokenAccount)
        KeychainHelper.delete(for: emailAccount)
        KeychainHelper.delete(for: idAccount)
        isSignedIn = false
        accountEmail = nil
        accountID = nil
        lastError = nil
    }

    // MARK: - Access token retrieval (used by Classroom/Chat clients)

    /// Returns a currently-valid access token, transparently refreshing via
    /// the stored refresh token if the cached one has expired.
    public func validAccessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw GoogleAuthError.notConfigured }

        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }

        guard let refreshToken = tokens.refreshToken else { throw GoogleAuthError.noRefreshToken }
        tokens = try await refresh(refreshToken: refreshToken)
        try store(tokens)
        return tokens.accessToken
    }

    // MARK: - Token exchange / refresh

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.decodeTokenResponse(data: data, response: response, existingRefreshToken: nil)
    }

    private func refresh(refreshToken: String) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.decodeTokenResponse(data: data, response: response, existingRefreshToken: refreshToken)
    }

    private static func decodeTokenResponse(data: Data, response: URLResponse, existingRefreshToken: String?) throws -> GoogleTokens {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw GoogleAuthError.tokenExchangeFailed(body)
        }
        struct RawResponse: Decodable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Int
            var scope: String?
        }
        do {
            let raw = try JSONDecoder().decode(RawResponse.self, from: data)
            return GoogleTokens(
                accessToken: raw.access_token,
                refreshToken: raw.refresh_token ?? existingRefreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(raw.expires_in)),
                scope: raw.scope
            )
        } catch {
            throw GoogleAuthError.tokenExchangeFailed("Unexpected response shape (\(error.localizedDescription)).")
        }
    }

    // MARK: - Keychain storage

    private func store(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let json = String(data: data, encoding: .utf8) else { return }
        KeychainHelper.save(password: json, for: tokenAccount)
    }

    private func loadTokens() -> GoogleTokens? {
        guard let json = KeychainHelper.get(for: tokenAccount), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }

    private func refreshAccountProfile() async {
        guard let token = try? await validAccessToken() else { return }
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let userInfo = try? JSONDecoder().decode(UserInfo.self, from: result.0) else { return }
        accountEmail = userInfo.email
        accountID = userInfo.sub
        KeychainHelper.save(password: userInfo.email, for: emailAccount)
        KeychainHelper.save(password: userInfo.sub, for: idAccount)
    }

    private struct UserInfo: Decodable { var sub: String; var email: String }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let pairs = fields.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    // MARK: - ASWebAuthenticationSession

    private func presentSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            session.start()
        }
    }
}

extension GoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(AppKit)
        return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
