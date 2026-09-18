import Foundation

/// A person's real name/photo as known to Google's directory -- used to
/// replace the generic "Direct message" label and initials-only avatar
/// with someone's actual name and profile picture, when available.
public struct DirectoryProfile: Sendable, Equatable {
    public var displayName: String?
    public var photoURL: URL?
}

/// One match from a directory name search (see
/// GooglePeopleClient.searchDirectory) -- unlike DirectoryProfile above,
/// this always has an email, since that's what starting a new chat with
/// them needs.
public struct DirectoryPerson: Identifiable, Sendable, Equatable {
    public var id: String { email }
    public var displayName: String
    public var email: String
    public var photoURL: URL?
}

/// Resolves Chat users to their real name/photo via the People API.
///
/// The Chat API itself has no photo field at all, and under user OAuth it
/// mostly only returns a bare user id -- so this is a separate lookup,
/// keyed by the numeric id Chat, the People API, and Google accounts in
/// general all share (Chat's "users/{id}" and People's "people/{id}" are
/// the same {id}).
///
/// Requires the `directory.readonly` scope, which is more sensitive than
/// the rest of what Omnibus asks for -- on a school/work Google Workspace
/// account a domain admin may block it even though everything else works.
/// This fails soft: any lookup that doesn't succeed just comes back
/// missing from the result, and callers fall back to an initials avatar.
public final class GooglePeopleClient: Sendable {
    private let auth: GoogleAuthManager

    public init(auth: GoogleAuthManager) {
        self.auth = auth
    }

    /// Looks up several people at once (People API's batchGet takes up to
    /// 200 resource names in one request), keyed by their Chat user id
    /// ("users/{id}") so callers can look results up the same way they
    /// already reference people elsewhere.
    public func fetchProfiles(chatUserIDs: [String]) async -> [String: DirectoryProfile] {
        let uniqueIDs = Array(Set(chatUserIDs))
        guard !uniqueIDs.isEmpty else { return [:] }
        guard let token = try? await auth.validAccessToken() else { return [:] }

        let resourceNames = uniqueIDs.compactMap { chatID -> String? in
            guard let numericID = chatID.split(separator: "/").last, !numericID.isEmpty else { return nil }
            return "people/\(numericID)"
        }
        guard !resourceNames.isEmpty else { return [:] }

        var components = URLComponents(string: "https://people.googleapis.com/v1/people:batchGet")!
        components.queryItems = resourceNames.map { URLQueryItem(name: "resourceNames", value: $0) }
            + [URLQueryItem(name: "personFields", value: "names,photos")]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            print("[GooglePeopleClient] request itself failed (no response) for \(resourceNames.count) ids")
            return [:]
        }
        guard let http = response as? HTTPURLResponse else {
            print("[GooglePeopleClient] response wasn't HTTP")
            return [:]
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[GooglePeopleClient] batchGet failed with status \(http.statusCode): \(body)")
            return [:]
        }
        guard let decoded = try? JSONDecoder().decode(BatchGetResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[GooglePeopleClient] decode failed. Raw body: \(body)")
            return [:]
        }

        var result: [String: DirectoryProfile] = [:]
        for entry in decoded.responses ?? [] {
            guard let person = entry.person, let resourceName = person.resourceName,
                  let numericID = resourceName.split(separator: "/").last else {
                print("[GooglePeopleClient] a batchGet entry had no usable person: \(entry)")
                continue
            }
            let chatID = "users/\(numericID)"

            let photo = person.photos?.first(where: { $0.isDefault != true }) ?? person.photos?.first
            print("[GooglePeopleClient] \(chatID): name=\(person.names?.first?.displayName ?? "nil") photoCount=\(person.photos?.count ?? 0) chosenPhotoURL=\(photo?.url ?? "nil")")
            result[chatID] = DirectoryProfile(
                displayName: person.names?.first?.displayName,
                photoURL: photo?.url.flatMap(URL.init(string:))
            )
        }
        print("[GooglePeopleClient] resolved \(result.count)/\(resourceNames.count) profiles")
        return result
    }

    /// Searches your Workspace domain's directory by name -- the
    /// suggestions list behind Messages' "Add Chat" search field. Only
    /// finds people in your own school/work domain (not arbitrary outside
    /// addresses), using the same `directory.readonly` scope already
    /// granted for DM photos, so no extra permission is needed. Fails
    /// soft: any error just comes back as no results, since this is
    /// assistive autocomplete, not something the rest of the flow depends
    /// on -- you can always fall back to typing the email directly.
    public func searchDirectory(query: String) async -> [DirectoryPerson] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let token = try? await auth.validAccessToken() else { return [] }

        var components = URLComponents(string: "https://people.googleapis.com/v1/people:searchDirectoryPeople")!
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "readMask", value: "names,emailAddresses,photos"),
            URLQueryItem(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"),
            URLQueryItem(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_CONTACT"),
            URLQueryItem(name: "pageSize", value: "10")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SearchDirectoryResponse.self, from: data) else {
            return []
        }

        return (decoded.people ?? []).compactMap { person -> DirectoryPerson? in
            guard let email = person.emailAddresses?.compactMap(\.value).first else { return nil }
            let photo = person.photos?.first(where: { $0.isDefault != true }) ?? person.photos?.first
            return DirectoryPerson(
                displayName: person.names?.first?.displayName ?? email,
                email: email,
                photoURL: photo?.url.flatMap(URL.init(string:))
            )
        }
    }

    // MARK: - Response shape

    private struct BatchGetResponse: Decodable {
        var responses: [PersonResponseDTO]?
    }
    private struct PersonResponseDTO: Decodable {
        var person: PersonDTO?
    }
    private struct SearchDirectoryResponse: Decodable {
        var people: [PersonDTO]?
    }
    private struct PersonDTO: Decodable {
        var resourceName: String?
        var names: [NameDTO]?
        var photos: [PhotoDTO]?
        var emailAddresses: [EmailAddressDTO]?
    }
    private struct NameDTO: Decodable {
        var displayName: String?
    }
    private struct EmailAddressDTO: Decodable {
        var value: String?
    }
    private struct PhotoDTO: Decodable {
        var url: String?
        var isDefault: Bool?

        enum CodingKeys: String, CodingKey {
            case url
            case isDefault = "default"
        }
    }
}
