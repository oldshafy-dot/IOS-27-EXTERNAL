
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore

    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false

    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int

        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = 0
        }

        _tabNavigation = State(
            initialValue: AppTabNavigationState(
                selectedTab: initialTab
            )
        )

        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(
            initialValue: AppTabNavigationState()
        )
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil {
                tabNavigation.select(AppSection.installed.rawValue)
            }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil {
                tabNavigation.select(AppSection.installed.rawValue)
            }
        }
        .onChange(of: developerModeEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showLogs) {
            LogView()
        }
        .patchStorePresentation(patchStore)
        .repositoryStorePresentation(
            repositoryStore,
            patchStore: patchStore
        )
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(
                            language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                        .fontWeight(
                            section.rawValue == tabNavigation.selectedTab
                                ? .semibold
                                : .regular
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab
                            ? .isSelected
                            : []
                    )
                }
            }
            .navigationTitle("3105")
            .navigationSplitViewColumnWidth(
                min: 210,
                ideal: 240,
                max: 300
            )
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            GamePatchCatalogView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )

        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )

        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )

        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )

        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )

        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(
            developerModeEnabled: developerModeActive
        )
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains(
                "--simulate-developer-mode"
            )
            || ProcessInfo.processInfo.arguments.contains(
                "--simulate-files-tab"
            )
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(
            rawValue: tabNavigation.selectedTab
        )

        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .home
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct GamePatchCatalogView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var store: PackageRepositoryStore

    @State private var selectedGame: GameCatalogue = .freeFire

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    private var matchingPackages: [RepositoryPackageRecord] {
        store.packages.filter { record in
            guard record.package.kind == .patch else {
                return false
            }

            return selectedGame.matches(record)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                gameSelector

                Divider()

                if store.isRefreshing && matchingPackages.isEmpty {
                    loadingState
                } else if matchingPackages.isEmpty {
                    emptyState
                } else {
                    packageList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Online Patches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .navigationDestination(
                for: RepositoryPackageRecord.self
            ) { record in
                RepositoryPackageDetailView(record: record)
            }
            .refreshable {
                await store.refreshAllAndWait()
            }
            .onAppear {
                store.refreshAllIfNeeded()
            }
        }
    }

    private var gameSelector: some View {
        HStack(spacing: 12) {
            gameButton(.freeFire)
            gameButton(.freeFireMax)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private func gameButton(_ game: GameCatalogue) -> some View {
        let isSelected = selectedGame == game

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedGame = game
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: game.symbol)

                Text(game.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(
                isSelected ? Color.white : Color.primary
            )
            .background(
                isSelected
                    ? AppTheme.accent
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected
                        ? Color.clear
                        : Color(uiColor: .separator).opacity(0.35),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var packageList: some View {
        List {
            Section {
                ForEach(matchingPackages) { record in
                    NavigationLink(value: record) {
                        RepositoryPackageRow(record: record)
                    }
                }
            } header: {
                Text(selectedGame.title)
            } footer: {
                Text(
                    "\(matchingPackages.count) online patch(es)"
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()

            Text("Loading online patches…")
                .font(.headline)

            Text("Connecting to the configured patch repositories.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppTheme.accent)

            Text(
                store.isRefreshing
                    ? "Refreshing online patches…"
                    : "No online patches found"
            )
            .font(.headline)

            Text(
                store.sources.isEmpty
                    ? "No online repository is configured. Add a valid repository in Sources."
                    : "No published patches match this game. Pull down to refresh or check the online repository metadata."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button {
                store.refreshAll()
            } label: {
                Label(
                    "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private enum GameCatalogue: Equatable {
    case freeFire
    case freeFireMax

    var title: String {
        switch self {
        case .freeFire:
            return "Free Fire Normal"
        case .freeFireMax:
            return "Free Fire MAX"
        }
    }

    var symbol: String {
        switch self {
        case .freeFire:
            return "gamecontroller"
        case .freeFireMax:
            return "gamecontroller.fill"
        }
    }

    func matches(_ record: RepositoryPackageRecord) -> Bool {
        let package = record.package

        let metadata = (
            [
                package.identifier,
                package.name,
                package.author,
                package.summary,
                package.details ?? "",
                package.category ?? "",
                record.sourceName
            ] + package.tags
        )
        .joined(separator: " ")
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")

        let compactMetadata = metadata.filter { $0.isLetter || $0.isNumber }
        let mentionsFreeFire =
            metadata.contains("free fire")
            || compactMetadata.contains("freefire")
            || metadata.contains("ff patch")
            || metadata.contains("ff-patch")

        guard mentionsFreeFire else {
            return false
        }

        let mentionsMAX =
            metadata.contains("free fire max")
            || metadata.contains("freefire max")
            || compactMetadata.contains("freefiremax")
            || metadata.contains("ff max")

        switch self {
        case .freeFire:
            return !mentionsMAX
        case .freeFireMax:
            return mentionsMAX
        }
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 17,
                weight: .medium
            )
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }

        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}
