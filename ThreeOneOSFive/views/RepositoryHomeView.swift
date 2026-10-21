import SwiftUI
import Foundation

struct RepositoryHomeView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: PackageRepositoryStore

    @State private var feed: [RepositoryPackageRecord] = []
    @State private var selectedOnlineGame = "free_fire"
    @State private var onlinePatches: [HomeOnlinePatch] = []
    @State private var isLoadingOnlinePatches = false
    @State private var onlinePatchError: String?

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    private let apiBaseURL =
        "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"

    private let publishableKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    onlinePatchCatalogue

                    if feed.isEmpty {
                        emptyContent
                    } else {
                        featuredFeed
                        recentPackages
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.contentCardInset)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable {
                await store.refreshAllAndWait()
                rebuildFeed()
                await loadOnlinePatches()
            }
            .navigationTitle("3105")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .navigationDestination(for: RepositoryPackageRecord.self) { record in
                RepositoryPackageDetailView(record: record)
            }
            .onAppear {
                store.refreshAllIfNeeded()

                if feed.isEmpty {
                    rebuildFeed()
                }

                Task {
                    await loadOnlinePatches()
                }
            }
            .onChange(of: store.packages) { _ in
                rebuildFeed()
            }
        }
    }

    private var onlinePatchCatalogue: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Free Fire Patches")
                .font(.title3.weight(.bold))

            Picker("Game", selection: $selectedOnlineGame) {
                Text("Free Fire").tag("free_fire")
                Text("Free Fire MAX").tag("free_fire_max")
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedOnlineGame) { _ in
                Task {
                    await loadOnlinePatches()
                }
            }

            if isLoadingOnlinePatches {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading online patches…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    Color(uiColor: .systemBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            } else if let error = onlinePatchError {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Try Again") {
                        Task {
                            await loadOnlinePatches()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    Color(uiColor: .systemBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            } else if onlinePatches.isEmpty {
                Text("No active patches are available for this game.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        Color(uiColor: .systemBackground),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(onlinePatches) { patch in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(
                                        patch.version.isEmpty
                                            ? "Patch"
                                            : patch.version
                                    )
                                    .font(.headline)

                                    if let notes = patch.notes,
                                       !notes.isEmpty {
                                        Text(notes)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let path = patch.filePath,
                                       !path.isEmpty {
                                        Text(path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: 4)

                                Link(destination: patch.downloadURL) {
                                    Label(
                                        "Download",
                                        systemImage: "arrow.down.circle.fill"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(14)

                        if patch.id != onlinePatches.last?.id {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(
                    Color(uiColor: .systemBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }
            }
        }
    }

    @MainActor
    private func loadOnlinePatches() async {
        isLoadingOnlinePatches = true
        onlinePatchError = nil

        defer {
            isLoadingOnlinePatches = false
        }

        guard var components = URLComponents(
            string: "\(apiBaseURL)/rest/v1/patches"
        ) else {
            onlinePatches = []
            onlinePatchError = "The patch service URL is invalid."
            return
        }

        components.queryItems = [
            URLQueryItem(
                name: "game",
                value: "eq.\(selectedOnlineGame)"
            ),
            URLQueryItem(
                name: "active",
                value: "eq.true"
            ),
            URLQueryItem(
                name: "select",
                value: "version,download_url,file_path,notes"
            )
        ]

        guard let url = components.url else {
            onlinePatches = []
            onlinePatchError = "Could not build the patch request."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(
            publishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        do {
            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                onlinePatches = []
                onlinePatchError = "Invalid response from patch service."
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                onlinePatches = []
                onlinePatchError =
                    "Patch service returned HTTP \(http.statusCode)."
                return
            }

            onlinePatches = try JSONDecoder().decode(
                [HomeOnlinePatch].self,
                from: data
            )

            if onlinePatches.isEmpty {
                onlinePatchError =
                    "No active patches are available for this game."
            }
        } catch {
            onlinePatches = []
            onlinePatchError =
                "Could not load patches. Check your connection and try again."
        }
    }

    private var emptyContent: some View {
        marketplaceEmpty(
            systemImage: store.sources.isEmpty
                ? "shippingbox.and.arrow.backward"
                : "shippingbox",
            titleKey: store.sources.isEmpty
                ? "repository.no_sources_title"
                : "repository.no_packages_title",
            messageKey: store.sources.isEmpty
                ? "repository.home_no_sources_message"
                : "repository.no_packages_message"
        )
    }

    private var featuredFeed: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("repository.for_you")

            GeometryReader { proxy in
                let cardWidth = featuredCardWidth(
                    availableWidth: proxy.size.width
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(
                        alignment: .top,
                        spacing: featuredCardSpacing
                    ) {
                        ForEach(
                            Array(feed.prefix(featuredPackageCount))
                        ) { record in
                            NavigationLink(value: record) {
                                RepositoryFeaturedCard(
                                    record: record,
                                    width: cardWidth,
                                    height: featuredCardHeight
                                )
                            }
                            .buttonStyle(RepositoryCardButtonStyle())
                        }
                    }
                }
            }
            .frame(height: featuredCardHeight)
        }
    }

    @ViewBuilder
    private var recentPackages: some View {
        let remaining = Array(feed.dropFirst(featuredPackageCount))

        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("repository.more_patches")

                VStack(spacing: 0) {
                    ForEach(
                        Array(remaining.enumerated()),
                        id: \.element.id
                    ) { index, record in
                        NavigationLink(value: record) {
                            HStack(spacing: 12) {
                                RepositoryPackageRow(record: record)

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(
                                .horizontal,
                                AppTheme.contentCardPadding
                            )
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RepositoryCardButtonStyle())

                        if index < remaining.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .background(
                    Color(uiColor: .systemBackground),
                    in: RoundedRectangle(
                        cornerRadius: AppTheme.contentCardCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    AppCardBorder()
                }
            }
        }
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(language.text(key))
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private func marketplaceEmpty(
        systemImage: String,
        titleKey: String,
        messageKey: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: AppTheme.emptyIconSize,
                        weight: .light
                    )
                )
                .foregroundStyle(AppTheme.accent)

            Text(language.text(titleKey))
                .font(.headline)

            Text(language.text(messageKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 48)
        .background(
            Color(uiColor: .systemBackground),
            in: RoundedRectangle(
                cornerRadius: AppTheme.contentCardCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            AppCardBorder()
        }
    }

    private func rebuildFeed() {
        feed = PackageRepositoryFeedPolicy.home(store.packages)
    }

    private var featuredPackageCount: Int {
        min(feed.count, 3)
    }

    private var featuredCardSpacing: CGFloat {
        10
    }

    private var featuredCardHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 180
        }

        if dynamicTypeSize >= .xxLarge {
            return 140
        }

        return 112
    }

    private func featuredCardWidth(
        availableWidth: CGFloat
    ) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return min(320, max(260, availableWidth * 0.82))
        }

        if dynamicTypeSize >= .xxLarge {
            return min(
                260,
                max(200, (availableWidth - featuredCardSpacing) / 1.45)
            )
        }

        return min(
            240,
            max(140, (availableWidth - featuredCardSpacing) / 2)
        )
    }
}

private struct HomeOnlinePatch: Decodable, Identifiable {
    let version: String
    let downloadURL: URL
    let filePath: String?
    let notes: String?

    var id: String {
        "\(version)|\(downloadURL.absoluteString)"
    }

    enum CodingKeys: String, CodingKey {
        case version
        case downloadURL = "download_url"
        case filePath = "file_path"
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        version = try container.decodeIfPresent(
            String.self,
            forKey: .version
        ) ?? ""

        filePath = try container.decodeIfPresent(
            String.self,
            forKey: .filePath
        )

        notes = try container.decodeIfPresent(
            String.self,
            forKey: .notes
        )

        let rawURL = try container.decode(
            String.self,
            forKey: .downloadURL
        )

        guard
            let parsedURL = URL(string: rawURL),
            parsedURL.scheme?.lowercased() == "https"
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .downloadURL,
                in: container,
                debugDescription: "Patch URL must use HTTPS."
            )
        }

        downloadURL = parsedURL
    }
}
