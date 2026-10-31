import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    var body: some Scene {
        WindowGroup {
            StartupGateView()
        }
    }
}

struct StartupGateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var authCompleted = !KeyAuthConfiguration.enabled
    @State private var showOnboarding = OnboardingStore.shouldShow()

    var body: some View {
        ZStack {
            if authCompleted {
                MainAppView(showOnboarding: $showOnboarding)
            } else {
                KeyAuthView {
                    withAnimation(
                        reduceMotion ? nil : .easeInOut(duration: 0.2)
                    ) {
                        authCompleted = true
                    }
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.98))
                )
            }
        }
    }
}

struct MainAppView: View {
    @Binding var showOnboarding: Bool

    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var keyAuthManager = KeyAuthManager()
    @StateObject private var patchUpdateManager = RequiredPatchUpdateManager()

    @AppStorage(AppLanguage.storageKey)
    private var languageCode = AppLanguage.english.rawValue

    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else {
                return
            }

            await MainActor.run {
                updateOffer = offer
            }
        }
    }

    var body: some View {
        ZStack {
            Group {
                if patchUpdateManager.isBlocking {
                    RequiredPatchUpdateView(manager: patchUpdateManager)
                } else {
                    ContentView()
                }
            }
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(fileOperationCoordinator)
                .environmentObject(patchStore)
                .environmentObject(repositoryStore)
                .environmentObject(keyAuthManager)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .opacity(showOnboarding ? 0 : 1)
                .allowsHitTesting(!showOnboarding)

            if showOnboarding {
                OnboardingView {
                    OnboardingStore.markCompleted()

                    withAnimation(
                        reduceMotion ? nil : .easeInOut(duration: 0.24)
                    ) {
                        showOnboarding = false
                    }

                    appState.detectSupport()
                    checkForUpdate()
                }
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.98))
                )
                .zIndex(1)
            }
        }
        .displayIdentityAttribution(
            isPresented: $showAttribution,
            enabled: !showOnboarding
        )
        .sheet(isPresented: $showAttribution) {
            DisplayAttributionSheet()
        }
        .alert(item: $updateOffer) { offer in
            Alert(
                title: Text(language.text("update.title")),
                message: Text(
                    language.text("update.message", offer.version)
                ),
                primaryButton: .default(
                    Text(language.text("update.agree"))
                ) {
                    UIApplication.shared.open(offer.url)
                },
                secondaryButton: .cancel(
                    Text(language.text("update.dismiss"))
                ) {
                    AppUpdateChecker.dismiss(
                        version: offer.version
                    )
                }
            )
        }
        .onAppear {
            appState.detectSupport()
            checkForUpdate()
            Task { await patchUpdateManager.check(patchStore: patchStore) }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else {
                return
            }

            appState.detectSupport()
        }
        .onOpenURL { url in
            patchDraftCoordinator.presentImport(url)
        }
    }
}

/*
 Safe AppState:
 - Keeps the environment object required by SettingsView.
 - Does NOT automatically start any kernel/exploit routine.
 - Only checks the app's supported iOS range.
 */
final class AppState: ObservableObject {
    @Published private(set) var isSupported = true

    func detectSupport() {
        let version = AppInfo.versionTuple

        isSupported = ExploitSupportPolicy.isSupported(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            build: AppInfo.osBuild
        )
    }
}


@MainActor
final class RequiredPatchUpdateManager: ObservableObject {
    struct PackageInfo: Decodable {
        let success: Bool
        let available: Bool
        let version: String
        let requiredUpdate: Bool
        let message: String
        let fileName: String
        let fileSize: Int64
        let publishedAt: String?
        let downloadURL: URL
        let downloadURLExpiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case success, available, version, message
            case requiredUpdate = "required_update"
            case fileName = "file_name"
            case fileSize = "file_size"
            case publishedAt = "published_at"
            case downloadURL = "download_url"
            case downloadURLExpiresIn = "download_url_expires_in"
        }
    }

    @Published private(set) var isBlocking = false
    @Published private(set) var isWorking = false
    @Published private(set) var version = ""
    @Published private(set) var message = "A required patch update is available."
    @Published private(set) var errorMessage: String?

    private let endpoint = URL(string: "https://shafaykeyauthadmin.lovable.app/api/public/v1/patch/latest")!
    private let installedVersionKey = "robo.requiredPatch.installedVersion"

    func check(patchStore: PatchProjectStore) async {
        guard !isWorking else { return }
        do {
            let info = try await fetchPackage()
            guard info.success, info.available, info.requiredUpdate else {
                isBlocking = false
                return
            }

            let installed = UserDefaults.standard.string(forKey: installedVersionKey)
            guard installed != info.version else {
                isBlocking = false
                return
            }

            version = info.version
            message = info.message
            errorMessage = nil
            isBlocking = true
        } catch {
            // Do not block the user when the update service is temporarily unreachable.
            isBlocking = false
        }
    }

    func install(patchStore: PatchProjectStore) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let info = try await fetchPackage()
            guard info.success, info.available, info.requiredUpdate else {
                isBlocking = false
                return
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }

            let (temporaryURL, response) = try await session.download(from: info.downloadURL)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw UpdateError.downloadFailed
            }

            try await patchStore.installDownloadedPatchArchive(at: temporaryURL)
            UserDefaults.standard.set(info.version, forKey: installedVersionKey)
            version = info.version
            isBlocking = false
        } catch {
            errorMessage = "Download or installation failed. Please try again."
        }
    }

    private func fetchPackage() async throws -> PackageInfo {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw UpdateError.requestFailed
        }
        return try JSONDecoder().decode(PackageInfo.self, from: data)
    }

    enum UpdateError: Error {
        case requestFailed
        case downloadFailed
    }
}

struct RequiredPatchUpdateView: View {
    @ObservedObject var manager: RequiredPatchUpdateManager
    @EnvironmentObject private var patchStore: PatchProjectStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(Color(red: 0.20, green: 0.68, blue: 1.0))

                Text("Required Update")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text(manager.version.isEmpty ? "A new patch package is required." : "Version \(manager.version) is required to continue.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)

                if !manager.message.isEmpty {
                    Text(manager.message)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                }

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await manager.install(patchStore: patchStore) }
                } label: {
                    HStack(spacing: 10) {
                        if manager.isWorking {
                            ProgressView().tint(.white)
                        }
                        Text(manager.isWorking ? "Installing..." : "Download & Install")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.12, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(manager.isWorking)
            }
            .padding(28)
        }
    }
}
