
import Foundation
import CryptoKit
import Security

enum KeyAuthConfiguration {
    static let enabled = true
    static let demoMode = false

    static let baseURL =
        "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"

    static let publishableKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    static let verificationURL = URL(
        string: "\(baseURL)/rest/v1/rpc/verify_key"
    )
}

@MainActor
final class KeyAuthManager: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private struct Response: Decodable {
        let valid: Bool
        let error: String?
        let expires_at: String?
    }

    func restoreSession() {
        isAuthorized = false
    }

    func verify(key: String) async {
        let cleanedKey = key.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedKey.isEmpty else {
            errorMessage = "Enter your access key."
            return
        }

        guard let url = KeyAuthConfiguration.verificationURL else {
            errorMessage = "Verification service is not configured."
            return
        }

        isLoading = true
        isAuthorized = false
        errorMessage = nil
        defer { isLoading = false }

        var request = URLRequest(url: url)
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

        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["check_key": cleanedKey]
            )

            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Invalid server response."
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                errorMessage = "Verification server error: HTTP \(http.statusCode)."
                return
            }

            let result = try JSONDecoder().decode(Response.self, from: data)

            if result.valid {
                isAuthorized = true
                errorMessage = nil
            } else {
                errorMessage = result.error ?? "Invalid or expired key."
            }
        } catch {
            errorMessage = "Could not verify the key. Please try again."
        }
    }
}
