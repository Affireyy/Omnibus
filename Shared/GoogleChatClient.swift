import Foundation

public struct ChatMessageItem: Identifiable, Sendable, Equatable {
    public var id: String
    /// Full resource name of the space this message belongs to (e.g.
    /// "spaces/AAAAAAAAAAA") -- an exact id to group/filter by, since two
    /// spaces can share a display name.
    public var spaceID: String
    public var spaceDisplayName: String
    public var senderDisplayName: String
    /// The sender's Chat user resource name (e.g. "users/107..."), when
    /// known -- used to look up their real photo via GooglePeopleClient.
    public var senderID: String?
    public var text: String
    public var createTime: Date
    /// True only for a message this device just sent and is still waiting
    /// on Chat to confirm (see OmnibusStore.sendChatMessage) -- shown with
    /// a small spinner instead of a timestamp so sending doesn't look like
    /// it did nothing while the request is in flight. Never true for a
    /// message that actually came back from the Chat API.
    public var isPending: Bool = false
}

/// A space you're a member of, exposed publicly so the UI can offer a
/// "send to..." picker.
public struct ChatSpace: Identifiable, Sendable, Equatable, Hashable {
    /// Full resource name, e.g. "spaces/AAAAAAAAAAA" -- this IS the id the
    /// Chat API expects everywhere a space is referenced, including as the
    /// parent of a new message.
    public var id: String
    public var displayName: String
    public var isDirectMessage: Bool = false
    /// For a direct-message space, the other person's Chat user resource
    /// name (e.g. "users/107...") -- resolved via spaces.members.list so
    /// Messages can show their real name/photo instead of a generic
    /// "Direct message" label. Nil for group spaces, or if it couldn't be
    /// resolved (e.g. the membership lookup failed or was inconclusive).
    public var dmOtherUserID: String?
}

public enum GoogleChatError: LocalizedError {
    case notSignedIn
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with Google to use Chat."
        case .requestFailed(let code, let body):
            return "Chat API request failed (\(code)): \(body)"
        }
    }
}

/// Talks to the Google Chat REST API as the signed-in user: reads spaces
/// and recent messages, and can send a message on your behalf (requires
/// the full `chat.messages` scope, not just `.readonly` -- see
/// GoogleOAuthConfig.swift).
/// See https://developers.google.com/workspace/chat/api/reference/rest
///
/// Note: on a school/work Google Workspace account, a domain admin may need
/// to have API access enabled before any of these calls succeed -- if every
/// request here fails with a 403, that's very likely the cause and isn't
/// something this app can work around.
public final class GoogleChatClient: Sendable {
    private let auth: GoogleAuthManager

    public init(auth: GoogleAuthManager) {
        self.auth = auth
    }

    /// Spaces you're a member of, for display and for the "send to..."
    /// picker. For each direct-message space, also resolves the other
    /// person via spaces.members.list (needs `chat.memberships.readonly`)
    /// so it can carry their real name instead of a blank "Direct message"
    /// -- pass your own account id (GoogleAuthManager.accountID) so that
    /// lookup can tell you apart from them.
    public func fetchSpaces(limit: Int = 30, selfUserID: String? = nil) async throws -> [ChatSpace] {
        let token = try await auth.validAccessToken()
        let dtos = try await fetchSpaceDTOs(token: token, limit: limit)

        return await withTaskGroup(of: ChatSpace.self) { group in
            for dto in dtos {
                group.addTask {
                    await self.buildSpace(token: token, dto: dto, selfUserID: selfUserID)
                }
            }
            var collected: [ChatSpace] = []
            for await space in group { collected.append(space) }
            return collected
        }
    }

    private func buildSpace(token: String, dto: SpaceDTO, selfUserID: String?) async -> ChatSpace {
        guard dto.spaceType == "DIRECT_MESSAGE" else {
            return ChatSpace(id: dto.name, displayName: dto.displayName ?? "Space", isDirectMessage: false)
        }
        let other: ChatUserRef? = (try? await fetchOtherHumanMember(token: token, spaceName: dto.name, selfUserID: selfUserID)) ?? nil
        return ChatSpace(
            id: dto.name,
            displayName: dto.displayName ?? other?.displayName ?? "Direct message",
            isDirectMessage: true,
            dmOtherUserID: other?.id
        )
    }

    /// Most recent messages across your spaces, newest first. Fans out
    /// across a capped number of spaces so a workspace with many chats
    /// doesn't turn one dashboard refresh into dozens of requests.
    public func fetchRecentMessages(spaceLimit: Int = 15, messagesPerSpace: Int = 12) async throws -> [ChatMessageItem] {
        let token = try await auth.validAccessToken()
        let spaces = try await fetchSpaceDTOs(token: token, limit: spaceLimit)

        let items: [[ChatMessageItem]] = try await withThrowingTaskGroup(of: [ChatMessageItem].self) { group in
            for space in spaces {
                group.addTask {
                    (try? await self.fetchMessages(token: token, space: space, limit: messagesPerSpace)) ?? []
                }
            }
            var collected: [[ChatMessageItem]] = []
            for try await result in group { collected.append(result) }
            return collected
        }

        return items.flatMap { $0 }.sorted { $0.createTime > $1.createTime }
    }

    /// Starts (or reuses, if one's already there) a direct-message
    /// conversation with someone by email -- for reaching a person who's
    /// never messaged you before and so isn't in fetchSpaces' result.
    /// Needs the broader `chat.spaces.create` scope: creating a space is a
    /// write, unlike everything else this client does (see
    /// GoogleOAuthConfig.swift/SETUP.md).
    public func startDirectMessage(withEmail email: String, selfUserID: String?) async throws -> ChatSpace {
        let token = try await auth.validAccessToken()
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        let dto: SpaceDTO
        let isNewlyCreated: Bool
        if let existing = try? await findDirectMessage(token: token, email: trimmedEmail) {
            dto = existing
            isNewlyCreated = false
        } else {
            dto = try await setupDirectMessage(token: token, email: trimmedEmail)
            isNewlyCreated = true
        }

        var space = await buildSpace(token: token, dto: dto, selfUserID: selfUserID)

        // A brand new space's membership list can lag a moment right after
        // creation, so the member lookup inside buildSpace above can come
        // back empty even though the space itself was created fine --
        // which is exactly why a freshly-added person's name/photo
        // sometimes doesn't resolve the first time. Retry briefly rather
        // than settling for the generic "Direct message" label when we
        // know this is precisely the case that's flaky (an existing space
        // being reopened doesn't need this -- its membership has been
        // stable for a while).
        if isNewlyCreated, space.dmOtherUserID == nil {
            let retryDelaysMs: [UInt64] = [300, 700, 1200]
            for delayMs in retryDelaysMs {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                space = await buildSpace(token: token, dto: dto, selfUserID: selfUserID)
                if space.dmOtherUserID != nil { break }
            }
        }
        return space
    }

    /// Re-resolves a single already-known space (its display name and, for
    /// a DM, the other person via the same member lookup buildSpace uses)
    /// without re-fetching every space via fetchSpaces -- used to quietly
    /// poll a freshly created DM in the background until its membership
    /// list catches up (see OmnibusStore.pollForDirectMessageResolution).
    public func fetchSpace(id: String, selfUserID: String?) async throws -> ChatSpace {
        let token = try await auth.validAccessToken()
        let dto: SpaceDTO = try await get(URL(string: "https://chat.googleapis.com/v1/\(id)")!, token: token)
        return await buildSpace(token: token, dto: dto, selfUserID: selfUserID)
    }

    private func findDirectMessage(token: String, email: String) async throws -> SpaceDTO {
        var components = URLComponents(string: "https://chat.googleapis.com/v1/spaces:findDirectMessage")!
        components.queryItems = [URLQueryItem(name: "name", value: "users/\(email)")]
        return try await get(components.url!, token: token)
    }

    private struct SetupSpaceRequest: Encodable {
        struct SpacePayload: Encodable {
            var spaceType: String
        }
        struct MembershipPayload: Encodable {
            struct MemberPayload: Encodable {
                var name: String
                var type: String
            }
            var member: MemberPayload
        }
        var space: SpacePayload
        var memberships: [MembershipPayload]
    }

    private func setupDirectMessage(token: String, email: String) async throws -> SpaceDTO {
        let url = URL(string: "https://chat.googleapis.com/v1/spaces:setup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SetupSpaceRequest(
                space: .init(spaceType: "DIRECT_MESSAGE"),
                memberships: [.init(member: .init(name: "users/\(email)", type: "HUMAN"))]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleChatError.requestFailed(-1, "No response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GoogleChatError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(SpaceDTO.self, from: data)
    }

    /// Sends a plain-text message to the given space (its `ChatSpace.id`,
    /// e.g. "spaces/AAAAAAAAAAA"), as you.
    public func sendMessage(text: String, to spaceName: String) async throws {
        let token = try await auth.validAccessToken()
        let url = URL(string: "https://chat.googleapis.com/v1/\(spaceName)/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleChatError.requestFailed(-1, "No response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GoogleChatError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Spaces

    private struct SpaceDTO: Decodable {
        var name: String
        var displayName: String?
        var spaceType: String?
    }
    private struct SpacesResponse: Decodable {
        var spaces: [SpaceDTO]?
    }

    private func fetchSpaceDTOs(token: String, limit: Int) async throws -> [SpaceDTO] {
        var components = URLComponents(string: "https://chat.googleapis.com/v1/spaces")!
        components.queryItems = [URLQueryItem(name: "pageSize", value: String(limit))]
        let response: SpacesResponse = try await get(components.url!, token: token)
        return Array((response.spaces ?? []).prefix(limit))
    }

    // MARK: - Members (for resolving a DM's other person)

    struct ChatUserRef: Sendable {
        var id: String
        var displayName: String?
    }

    private struct MemberUserDTO: Decodable {
        var name: String
        var displayName: String?
        var type: String?
    }
    private struct MembershipDTO: Decodable {
        var member: MemberUserDTO?
    }
    private struct MembersResponse: Decodable {
        var memberships: [MembershipDTO]?
    }

    /// The other human in a direct-message space -- deliberately returns
    /// nil (rather than guessing) unless exactly one human member besides
    /// yourself is found, so a DM never ends up mislabeled with the wrong
    /// person's name.
    private func fetchOtherHumanMember(token: String, spaceName: String, selfUserID: String?) async throws -> ChatUserRef? {
        var components = URLComponents(string: "https://chat.googleapis.com/v1/\(spaceName)/members")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "member.type = \"HUMAN\""),
            URLQueryItem(name: "pageSize", value: "10"),
            // Without this, someone who's never messaged you before never
            // shows up here at all -- they're an *invited* member of a
            // freshly created DM space until they actually open it, and
            // members.list excludes invited (not-yet-joined) members by
            // default. This isn't a timing/propagation thing retrying
            // would ever fix -- the query itself was excluding them.
            URLQueryItem(name: "showInvited", value: "true")
        ]
        let response: MembersResponse = try await get(components.url!, token: token)
        let members = (response.memberships ?? []).compactMap(\.member)

        let selfID = selfUserID.map { "users/\($0)" }
        let others = members.filter { $0.name != selfID }
        guard others.count == 1, let other = others.first else { return nil }
        return ChatUserRef(id: other.name, displayName: other.displayName)
    }

    // MARK: - Messages

    private struct SenderDTO: Decodable {
        var name: String?
        var displayName: String?
        var type: String?
    }
    private struct MessageDTO: Decodable {
        var name: String
        var text: String?
        var createTime: String
        var sender: SenderDTO?
    }
    private struct MessagesResponse: Decodable {
        var messages: [MessageDTO]?
    }

    private func fetchMessages(token: String, space: SpaceDTO, limit: Int) async throws -> [ChatMessageItem] {
        var components = URLComponents(string: "https://chat.googleapis.com/v1/\(space.name)/messages")!
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: String(limit)),
            URLQueryItem(name: "orderBy", value: "createTime desc")
        ]
        let response: MessagesResponse = try await get(components.url!, token: token)

        return (response.messages ?? []).compactMap { dto in
            guard let text = dto.text, !text.isEmpty, let createTime = Self.parseTimestamp(dto.createTime) else { return nil }
            return ChatMessageItem(
                id: dto.name,
                spaceID: space.name,
                spaceDisplayName: space.displayName ?? "Direct message",
                senderDisplayName: dto.sender?.displayName ?? (dto.sender?.type == "BOT" ? "Bot" : "Someone"),
                senderID: dto.sender?.name,
                text: text,
                createTime: createTime
            )
        }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleChatError.requestFailed(-1, "No response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GoogleChatError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
