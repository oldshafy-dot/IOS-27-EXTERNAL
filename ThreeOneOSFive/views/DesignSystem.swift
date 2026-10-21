// MARK: - Key authentication configuration

enum KeyAuthConfiguration {
    static let enabled = true
    static let demoMode = false

    static let baseURL = URL(
        string: "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"
    )!

    static let publishableKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    static let verificationURL = baseURL
        .appendingPathComponent("rest")
        .appendingPathComponent("v1")
        .appendingPathComponent("rpc")
        .appendingPathComponent("verify_key")
}

// MARK: - Key authentication manager

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
        // Do not trust a previous local session without server validation.
        isAuthorized = false
    }

    func verify(key: String) async {
        let trimmedKey = key.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedKey.isEmpty else {
            errorMessage = "Please enter your access key."
            return
        }

        guard KeyAuthConfiguration.enabled else {
            errorMessage = "Key verification is disabled."
            return
        }

        isLoading = true
        errorMessage = nil
        isAuthorized = false

        defer {
            isLoading = false
        }

        var request = URLRequest(
            url: KeyAuthConfiguration.verificationURL
        )

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
                withJSONObject: [
                    "check_key": trimmedKey
                ]
            )

            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "The server returned an invalid response."
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                errorMessage = "Server verification failed (HTTP \(httpResponse.statusCode))."
                return
            }

            let result = try JSONDecoder().decode(
                VerificationResponse.self,
                from: data
            )

            if result.valid {
                isAuthorized = true
                errorMessage = nil
            } else {
                isAuthorized = false
                errorMessage = result.error ?? "Invalid or expired key."
            }

        } catch let decodingError as DecodingError {
            isAuthorized = false
            errorMessage = "Unexpected verification response. Check the API response format."
            print("Key verification decoding error: \(decodingError)")

        } catch {
            isAuthorized = false
            errorMessage = "Could not connect to the verification server. Please try again."
            print("Key verification request failed: \(error)")
        }
    }
}
