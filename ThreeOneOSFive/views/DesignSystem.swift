
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

// MARK: - Production key authentication

enum KeyAuthConfiguration {
    static let demoMode = false
    static let enabled = true

    static let baseURL =
        "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"

    static let publishableAPIKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    static let verificationURL = URL(
        string: "\(baseURL)/rest/v1/rpc/verify_key"
    )
}

enum DeviceBindingIdentity {
    private static let service =
        "com.apple.mobile.MobileHouseArrest.key-auth"
    private static let account = "installation-id"

    static var fingerprint: String {
        let installationID = loadOrCreateInstallationID()
        let digest = SHA256.hash(data: Data(installationID.utf8))
        return digest.map {
            String(format: "%02x", $0)
        }.joined()
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

private struct LicenseVerificationResponse: Decodable {
    let valid: Bool
    let error: String?
    let expires_at: String?
}

@MainActor
final class KeyAuthManager: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func restoreSession() {
        // Do not bypass server verification by trusting a local Boolean.
        isAuthorized = false
    }

    func verify(key: String) async {
        let trimmedKey = key.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedKey.isEmpty else {
            errorMessage = "Enter your license key."
            return
        }

        guard KeyAuthConfiguration.enabled else {
            errorMessage = "License verification is disabled."
            return
        }

        guard !KeyAuthConfiguration.demoMode else {
            errorMessage = "Demo authentication must not be used."
            return
        }

        guard let endpoint = KeyAuthConfiguration.verificationURL else {
            errorMessage = "The verification endpoint is invalid."
            return
        }

        isLoading = true
        errorMessage = nil
        isAuthorized = false

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
            KeyAuthConfiguration.publishableAPIKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: [
                    "check_key": trimmedKey
                ]
            )

            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from the server."
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    errorMessage =
                        "The API rejected this request. Check API permissions."
                } else if http.statusCode == 404 {
                    errorMessage =
                        "The verification endpoint or database function was not found."
                } else {
                    errorMessage =
                        "Verification server error (HTTP \(http.statusCode))."
                }
                return
            }

            let result = try JSONDecoder().decode(
                LicenseVerificationResponse.self,
                from: data
            )

            if result.valid {
                isAuthorized = true
                errorMessage = nil
            } else {
                isAuthorized = false

                switch result.error {
                case "License expired":
                    errorMessage = "Your license has expired."
                case "Invalid license key":
                    errorMessage = "Invalid license key."
                default:
                    errorMessage = result.error ?? "License verification failed."
                }
            }
        } catch let error as DecodingError {
            isAuthorized = false
            errorMessage =
                "Unexpected verification response. Check the backend response format. (\(error.localizedDescription))"
        } catch {
            isAuthorized = false
            errorMessage =
                "Could not connect to the verification server. Check your connection and try again."
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
                                    ProgressView().tint(.white)
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
                        "Your license is checked by the verification server."
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
