import SwiftUI

/// Search-and-pick GIF sheet opened from ComposeBar's attach menu ("GIFs").
/// Picking a result downloads it to a temp file and hands that back to the
/// caller, which attaches it exactly like a file chosen from Finder.
struct GifPickerView: View {
    var onPick: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GiphyGif] = []
    @State private var isSearching = false
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GIFs")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            TextField("Search GIPHY…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onChange(of: query) { _, newValue in
                    scheduleSearch(for: newValue)
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(results) { gif in
                        Button {
                            pick(gif)
                        } label: {
                            AsyncImage(url: gif.previewURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(Color.secondary.opacity(0.1))
                                }
                            }
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloading)
                    }
                }
                .padding()
            }
            .overlay {
                if isSearching && results.isEmpty {
                    ProgressView()
                } else if !isSearching && results.isEmpty {
                    Text(query.isEmpty ? "Nothing trending right now." : "No GIFs found.")
                        .foregroundStyle(.secondary)
                }
            }

            if isDownloading {
                ProgressView("Downloading…")
                    .padding()
            }
        }
        .frame(width: 420, height: 460)
        .task {
            await runTrending()
        }
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                await runTrending()
            } else {
                await runSearch(text)
            }
        }
    }

    private func runSearch(_ text: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await GiphyClient.shared.search(text)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func runTrending() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await GiphyClient.shared.trending()
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func pick(_ gif: GiphyGif) {
        isDownloading = true
        errorMessage = nil
        Task {
            defer { isDownloading = false }
            do {
                let fileURL = try await GiphyClient.shared.downloadToTempFile(gif)
                onPick(fileURL)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
