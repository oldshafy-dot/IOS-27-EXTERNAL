
import SwiftUI
import SafariServices

@MainActor
final class LovablePatchCatalogViewModel: ObservableObject {
    @Published var selectedGame: LovableGame = .freeFire
    @Published private(set) var patches: [LovablePatch] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var requestID = UUID()

    func loadPatches() async {
        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        errorMessage = nil

        defer {
            if requestID == currentRequestID {
                isLoading = false
            }
        }

        do {
            let results = try await LovablePatchAPI.shared.fetchPatches(
                for: selectedGame
            )

            guard requestID == currentRequestID else {
                return
            }

            patches = results
        } catch {
            guard requestID == currentRequestID else {
                return
            }

            patches = []
            errorMessage = error.localizedDescription
        }
    }

    func select(_ game: LovableGame) {
        guard selectedGame != game else {
            return
        }

        selectedGame = game
        patches = []
        errorMessage = nil
    }
}

struct LovablePatchCatalogView: View {
    @StateObject private var model = LovablePatchCatalogViewModel()
    @State private var selectedDownload: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                gameSelector

                Divider()

                content
            }
            .navigationTitle("Online Patches")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: model.selectedGame) {
                await model.loadPatches()
            }
            .sheet(item: downloadBinding) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var gameSelector: some View {
        HStack(spacing: 12) {
            ForEach(LovableGame.allCases) { game in
                Button {
                    model.select(game)
                } label: {
                    Text(game.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(
                            model.selectedGame == game
                                ? Color.white
                                : Color.primary
                        )
                        .background(
                            model.selectedGame == game
                                ? Color.accentColor
                                : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.patches.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading online patches…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Connection Failed", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task {
                        await model.loadPatches()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.patches.isEmpty {
            ContentUnavailableView(
                "No Active Patches",
                systemImage: "shippingbox",
                description: Text(
                    "No active patches were returned for \(model.selectedGame.title)."
                )
            )
        } else {
            List(model.patches) { patch in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Version \(patch.version)")
                            .font(.headline)

                        Spacer()

                        Button {
                            selectedDownload = patch.downloadURL
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text(patch.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if let notes = patch.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 6)
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await model.loadPatches()
            }
        }
    }

    private var downloadBinding: Binding<DownloadSheetItem?> {
        Binding(
            get: {
                selectedDownload.map { DownloadSheetItem(url: $0) }
            },
            set: { newValue in
                selectedDownload = newValue?.url
            }
        )
    }
}

private struct DownloadSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(
        _ controller: SFSafariViewController,
        context: Context
    ) {}
}
