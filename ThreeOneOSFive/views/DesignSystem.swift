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
                ?? Bundle.main.path(
                    forResource: "AppIcon60x60@2x",
                    ofType: "png"
                ).flatMap(UIImage.init(contentsOfFile:))
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
        .clipShape(
            RoundedRectangle(
                cornerRadius: size * 0.22,
                style: .continuous
            )
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Key Authentication

enum KeyAuthConfiguration {
    static let enabled = true

    // Real server verification is enabled.
    static let demoMode = false

    static let baseURL =
        "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"

    static let publishableKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    static let verificationURL = URL(
        string: "\(baseURL)/rest/v1/rpc/verify_key"
    )
}

// MARK: - Device Identity

enum DeviceBindingIdentity {
    private static let service =
        "com.apple.mobile.MobileHouseArrest.key-auth"

    private static let account = "installation-id"

    static var fingerprint: String {
        let installationID = loadOrCreateInstallationID()
        let digest = SHA256.hash(data: Data(installationID.utf8))

        return digest
            .map { String(format: "%02x", $0) }
            .joined()
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

        if SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess,
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

        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

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

// MARK: - Key Authentication Manager

@MainActor
final class KeyAuthManager: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private struct VerificationResponse: Decodable {
        let valid: Bool
        let error: String?
        let expires_at: String?
    }

    func restoreSession() {
        // Verify the key with the server instead of trusting local state.
        isAuthorized = false
    }

    func verify(key: String) async {
        let cleanedKey = key.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedKey.isEmpty else {
            errorMessage = "Enter a valid key."
            return
        }

        guard KeyAuthConfiguration.enabled else {
            errorMessage = "Key verification is disabled."
            return
        }

        if KeyAuthConfiguration.demoMode {
            isAuthorized = true
            errorMessage = nil
            return
        }

        guard let endpoint = KeyAuthConfiguration.verificationURL else {
            errorMessage = "Key verification endpoint is not configured."
            return
        }

        isLoading = true
        isAuthorized = false
        errorMessage = nil

        defer {
            isLoading = false
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.setValue(
            KeyAuthConfiguration.publishableKey,
            forHTTPHeaderField: "apikey"
        )

        request.setValue(
            "Bearer \(KeyAuthConfiguration.publishableKey)",
            forHTTPHeaderField: "Authorization"
        )

        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "check_key": cleanedKey
            ]
        )

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                errorMessage =
                    "The verification server returned an invalid response."
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                if let payload = try? JSONDecoder().decode(
                    VerificationResponse.self,
                    from: data
                ) {
                    errorMessage =
                        payload.error ?? "Invalid or expired key."
                } else {
                    errorMessage =
                        "Verification failed (HTTP \(http.statusCode))."
                }

                return
            }

            let result: VerificationResponse?

            if let object = try? JSONDecoder().decode(
                VerificationResponse.self,
                from: data
            ) {
                result = object
            } else if let array = try? JSONDecoder().decode(
                [VerificationResponse].self,
                from: data
            ) {
                result = array.first
            } else {
                result = nil
            }

            guard let result else {
                errorMessage =
                    "The server response could not be read."
                return
            }

            if result.valid {
                isAuthorized = true
                errorMessage = nil
            } else {
                isAuthorized = false
                errorMessage =
                    result.error ?? "Invalid or expired key."
            }

        } catch {
            errorMessage =
                "Could not connect to the verification server. Check your internet connection."
        }
    }
}

// MARK: - Key Verification Screen

struct KeyAuthView: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

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
                        .background(
                            AppTheme.accent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 20)
                        )

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
                            .background(
                                Color(.systemGray6),
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                                .stroke(
                                    AppTheme.accent.opacity(0.18),
                                    lineWidth: 1
                                )
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
                                    ProgressView()
                                        .tint(.white)
                                }

                                Text(
                                    authManager.isLoading
                                        ? "Verifying…"
                                        : "Verify Key"
                                )
                                .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(
                                AppTheme.accent,
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
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

                    Text(
                        "One key can be bound to one device by the verification server."
                    )
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
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: authManager.errorMessage
        )
    }
}
