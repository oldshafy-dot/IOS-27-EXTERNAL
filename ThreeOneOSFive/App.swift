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
            ContentView()
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
