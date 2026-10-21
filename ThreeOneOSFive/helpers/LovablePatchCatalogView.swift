import SwiftUI

@MainActor
final class LovablePatchCatalogModel: ObservableObject {
    @Published var selectedGame: LovableGame = .freeFire
    @Published private(set) var patches: [LovablePatch] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        patches = []

        defer {
            isLoading = false
        }

        do {
            patches = try await LovablePatchAPI.shared.fetchPatches(
                for: selectedGame
            )

            if patches.isEmpty {
                errorMessage = "No active patches are available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LovablePatchCatalogView: View {
    @StateObject private var model = LovablePatchCatalogModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Online Patches")
                        .font(.title2.bold())

                    Text("Latest available versions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task {
                            await model.load()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline)
                    }
                    .accessibilityLabel("Refresh patches")
                }
            }

            Picker("Game", selection: $model.selectedGame) {
                ForEach(LovableGame.allCases) { game in
                    Text(game.title).tag(game)
                }
            }
            .pickerStyle(.segmented)

            if model.isLoading && model.patches.isEmpty {
                ProgressView("Loading patches…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let error = model.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)

                    Text(error)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        Task {
                            await model.load()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                ForEach(model.patches) { patch in
                    patchRow(patch)
                }
            }
        }
        .padding()
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .task {
            await model.load()
        }
        .onChange(of: model.selectedGame) { _ in
            Task {
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func patchRow(_ patch: LovablePatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Version \(patch.version)")
                        .font(.headline)

                    if let notes = patch.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let path = patch.filePath, !path.isEmpty {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Link(destination: patch.downloadURL) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()
        }
    }
}

#Preview {
    LovablePatchCatalogView()
}
