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

// MARK: - Startup Gate

struct StartupGateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var authCompleted = !KeyAuthConfiguration.enabled
    @State private var showOnboarding = OnboardingStore.shouldShow()

    var body: some View {
        ZStack {
            if authCompleted {
                MainAppView(
                    showOnboarding: $showOnboarding
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.98))
                )
            } else {
                KeyAuthView {
                    withAnimation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.2)
                    ) {
                        authCompleted = true
                    }
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.98))
                )
                .zIndex(2)
            }
        }
    }
}

// MARK: - Main App

struct MainAppView: View {
    @Binding var showOnboarding: Bool

    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var keyAuthManager = KeyAuthManager()

    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?

    @AppStorage(AppLanguage.storageKey)
    private var languageCode = AppLanguage.english.rawValue

    @Environment(\.scenePhase)
    private var scenePhase

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
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
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.24)
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
                title: Text(
                    language.text("update.title")
                ),
                message: Text(
                    language.text(
                        "update.message",
                        offer.version
                    )
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
            setupLogCapture()

            if !showOnboarding {
                appState.detectSupport()
                checkForUpdate()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            guard !showOnboarding else { return }

            appState.detectSupport()
        }
        .onOpenURL { url in
            patchDraftCoordinator.presentImport(url)
        }
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check()
            else {
                return
            }

            await MainActor.run {
                updateOffer = offer
            }
        }
    }
}
