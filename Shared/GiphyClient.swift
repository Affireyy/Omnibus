import Foundation

/// A single search result from GIPHY -- just the two renditions Omnibus
/// actually needs: a small preview for the picker grid, and the
/// original-quality file to actually attach and send.
public struct GiphyGif: Identifiable, Sendable, Equatable {
    public var id: String
    public var previewURL: URL
    public var downloadURL: URL
}

public enum GiphyError: Error, LocalizedError {
    case requestFailed(Int, String)
    case noKey

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let body):
            return "GIPHY request failed (\(code)): \(body)"
        case .noKey:
            return "Add a GIPHY API key in GiphyConfig.swift to search GIFs -- see SETUP.md."
        }
    }
}

public final class GiphyClient {
    public static let shared = GiphyClient()
    private init() {}

    public func search(_ query: String, limit: Int = 24) async throws -> [GiphyGif] {
        try await fetch(
            path: "search",
            extraItems: [URLQueryItem(name: "q", value: query)],
            limit: limit
        )
    }

    /// What the picker shows before the user has typed anything -- GIPHY's
    /// own "what's popular right now" feed, a separate endpoint from search.
    public func trending(limit: Int = 24) async throws -> [GiphyGif] {
        try await fetch(path: "trending", extraItems: [], limit: limit)
    }

    private func fetch(path: String, extraItems: [URLQueryItem], limit: Int) async throws -> [GiphyGif] {
        guard GiphyConfig.apiKey != "YOUR_GIPHY_API_KEY", !GiphyConfig.apiKey.isEmpty else {
            throw GiphyError.noKey
        }
        var components = URLComponents(string: "https://api.giphy.com/v1/gifs/\(path)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: GiphyConfig.apiKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "rating", value: "pg-13")
        ] + extraItems
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GiphyError.requestFailed(code, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(GiphySearchResponse.self, from: data)
        return decoded.data.compactMap { item in
            guard let previewString = item.images.fixedWidth?.url ?? item.images.previewGif?.url,
                  let previewURL = URL(string: previewString),
                  let downloadString = item.images.original?.url,
                  let downloadURL = URL(string: downloadString) else { return nil }
            return GiphyGif(id: item.id, previewURL: previewURL, downloadURL: downloadURL)
        }
    }

    /// Downloads a picked GIF's full-quality bytes to a temp file, so it
    /// can be sent through the same file-attachment pipeline (ComposeBar's
    /// attachedFileURL / OmnibusStore.sendChatMessage) as any other file.
    public func downloadToTempFile(_ gif: GiphyGif) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: gif.downloadURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GiphyError.requestFailed(code, "Couldn't download that GIF.")
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("giphy-\(gif.id)")
            .appendingPathExtension("gif")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}

private struct GiphySearchResponse: Decodable {
    var data: [GiphyItemDTO]
}

private struct GiphyItemDTO: Decodable {
    var id: String
    var images: GiphyImagesDTO
}

private struct GiphyImagesDTO: Decodable {
    var fixedWidth: GiphyImageRenditionDTO?
    var previewGif: GiphyImageRenditionDTO?
    var original: GiphyImageRenditionDTO?

    enum CodingKeys: String, CodingKey {
        case fixedWidth = "fixed_width"
        case previewGif = "preview_gif"
        case original
    }
}

private struct GiphyImageRenditionDTO: Decodable {
    var url: String
}
