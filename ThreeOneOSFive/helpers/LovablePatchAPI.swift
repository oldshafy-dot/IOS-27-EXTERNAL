
import Foundation

enum LovableGame: String, CaseIterable, Identifiable {
    case freeFire = "free_fire"
    case freeFireMax = "free_fire_max"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeFire:
            return "Free Fire Normal"
        case .freeFireMax:
            return "Free Fire MAX"
        }
    }
}

struct LovablePatch: Decodable, Identifiable, Hashable {
    let version: String
    let downloadURL: URL
    let filePath: String
    let notes: String?

    var id: String {
        "\(filePath)|\(version)"
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

        version = try container.decode(
            String.self,
            forKey: .version
        )

        let rawURL = try container.decode(
            String.self,
            forKey: .downloadURL
        )

        guard let parsedURL = URL(string: rawURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "https",
              parsedURL.host != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .downloadURL,
                in: container,
                debugDescription: "Invalid HTTPS patch download URL."
            )
        }

        downloadURL = parsedURL

        filePath = try container.decode(
            String.self,
            forKey: .filePath
        )

        notes = try container.decodeIfPresent(
            String.self,
            forKey: .notes
        )
    }
}

enum LovablePatchAPIError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case serverError(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The patch API configuration is invalid."
        case .invalidResponse:
            return "The patch API returned an invalid response."
        case .serverError(let status):
            return "The patch API returned HTTP \(status)."
        case .invalidData:
            return "The patch catalogue contains invalid data."
        }
    }
}

final class LovablePatchAPI {
    static let shared = LovablePatchAPI()

    private let baseURL =
        "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"

    private let publishableKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPatches(
        for game: LovableGame
    ) async throws -> [LovablePatch] {
        guard let endpoint = URL(
            string: "\(baseURL)/rest/v1/patches"
        ),
        var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw LovablePatchAPIError.invalidConfiguration
        }

        components.queryItems = [
            URLQueryItem(name: "game", value: "eq.\(game.rawValue)"),
            URLQueryItem(name: "active", value: "eq.true"),
            URLQueryItem(
                name: "select",
                value: "version,download_url,file_path,notes"
            )
        ]

        guard let url = components.url else {
            throw LovablePatchAPIError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25

        request.setValue(
            publishableKey,
            forHTTPHeaderField: "apikey"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(
            for: request
        )

        guard let http = response as? HTTPURLResponse else {
            throw LovablePatchAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw LovablePatchAPIError.serverError(
                http.statusCode
            )
        }

        do {
            return try JSONDecoder().decode(
                [LovablePatch].self,
                from: data
            )
        } catch {
            throw LovablePatchAPIError.invalidData
        }
    }
}
