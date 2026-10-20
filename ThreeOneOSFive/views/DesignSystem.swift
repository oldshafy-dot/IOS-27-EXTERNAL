import SwiftUI
import Foundation
import CryptoKit
import Security

enum AppTheme {
    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.24, green: 0.52, blue: 1.00, alpha: 1.00)
                : UIColor(red: 0.08, green: 0.38, blue: 0.90, alpha: 1.00)
        }
    )
    static let pageBackground = Color(uiColor: .systemBackground)
    static let consoleBackground = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 20
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            Color(uiColor: .separator).opacity(0.22),
            lineWidth: 0.5
        )
        .accessibilityHidden(true)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}


// MARK: - Key authentication template

/// Set this to `true` when the real key-verification backend is ready.
/// The current project keeps the screen and integration point ready without
/// forcing authentication until the backend is supplied.
enum KeyAuthConfiguration {
    /// Temporary local/demo mode: any non-empty key opens the app.
    /// Set this to false when the real API is ready.
    static let demoMode = true

    /// Keep the startup auth flow enabled so the key screen is always shown.
    static let enabled = true

    /// Replace with the production verification endpoint later.
    static let verificationURL = URL(string: "https://YOUR-AUTH-ENDPOINT.example/verify")
}

enum DeviceBindingIdentity {
    private static let service = "com.apple.mobile.MobileHouseArrest.key-auth"
    private static let account = "installation-id"

    static var fingerprint: String {
        let installationID = loadOrCreateInstallationID()
        let digest = SHA256.hash(data: Data(installationID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadOrCreateInstallationID() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        let value = UUID().uuidString
        let data = Data(value.utf8)
        var item = query
        item[kSecValueData as String] = data
        item.removeValue(forKey: kSecReturnData as String)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
        return value
    }
}

enum KeyAuthResult {
    case authorized
    case invalidKey
    case alreadyBound
    case unavailable
    case notConfigured
}

@MainActor
final class KeyAuthManager: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func restoreSession() {
        // The real backend should return a signed/opaque session token here.
        // This template intentionally does not auto-authorize without a backend.
        isAuthorized = false
    }

    func verify(key: String) async {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "Enter a valid key."
            return
        }

        guard KeyAuthConfiguration.enabled else {
            errorMessage = "Key verification is disabled."
            return
        }

        // Temporary development mode: any non-empty key is accepted.
        // The network-backed verification path below is preserved for the
        // production API and one-key/one-device binding.
        if KeyAuthConfiguration.demoMode {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            try? await Task.sleep(nanoseconds: 220_000_000)
            isAuthorized = true
            return
        }

        guard let endpoint = KeyAuthConfiguration.verificationURL else {
            errorMessage = "Key verification endpoint is not configured yet."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": trimmedKey,
            "device": DeviceBindingIdentity.fingerprint
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Verification failed."
                return
            }

            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let authorized = payload?["authorized"] as? Bool ?? false
            let reason = payload?["reason"] as? String

            if authorized {
                isAuthorized = true
            } else if reason == "already_bound" {
                errorMessage = "This key is already linked to another device."
            } else {
                errorMessage = "Invalid key."
            }
        } catch {
            errorMessage = "Could not connect to the verification server."
        }
    }
}

struct KeyAuthView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var authManager = KeyAuthManager()
    @State private var key = ""
    var onAuthorized: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 36)

                    Image(systemName: "key.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    VStack(spacing: 7) {
                        Text("Key Verification")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("Enter your access key to continue.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField("Enter key", text: $key)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.accent.opacity(0.18), lineWidth: 1)
                            }

                        Button {
                            Task {
                                await authManager.verify(key: key)
                                if authManager.isAuthorized {
                                    onAuthorized()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if authManager.isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text(authManager.isLoading ? "Verifying…" : "Verify Key")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(authManager.isLoading)
                    }
                    .padding(.horizontal, 24)

                    if let message = authManager.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    Text("One key can be bound to one device by the verification server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Spacer(minLength: 30)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .task {
            authManager.restoreSession()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authManager.errorMessage)
    }
}
