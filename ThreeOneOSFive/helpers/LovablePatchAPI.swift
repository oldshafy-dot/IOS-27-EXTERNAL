import Foundation

enum LovableGame: String, CaseIterable, Identifiable {
    case freeFire = "free_fire"
    case freeFireMax = "free_fire_max"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeFire:
            return "Free Fire"
        case .freeFireMax:
            return "Free Fire MAX"
        }
    }
}

struct LovablePatch: Decodable, Identifiable, Hashable {
    let version: String
    let downloadURL: URL
    let filePath: String?
    let notes: String?

    var id: String {
        "\(version)-\(downloadURL.absoluteString)"
    }

    enum CodingKeys: String, CodingKey {
        case version
        case downloadURL = "download_url"
        case filePath = "file_path"
        case notes
    }

    init(
        version: String,
        downloadURL: URL,
        filePath: String?,
        notes: String?
    ) {
        self.version = version
        self.downloadURL = downloadURL
        self.filePath = filePath
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decode(String.self, forKey: .version)

        let urlString = try container.decode(String.self, forKey: .downloadURL)

        guard
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "https"
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .downloadURL,
                in: container,
                debugDescription: "Download URL must use HTTPS."
            )
        }

        downloadURL = url
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

enum LovablePatchAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case invalidURL
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpError(let status):
            return "Server error: HTTP \(status)."
        case .invalidURL:
            return "The API URL is invalid."
        case .missingData:
            return "No active patches were found."
        }
    }
}

final class LovablePatchAPI {
    static let shared = LovablePatchAPI()

    private let baseURL =
        "https://c--46026e77-f295-431b-b24d-5d0b34c299d0-prod.lovable.cloud"

    private let publishableKey =
        "sb_publishable_w4SSt67-eYUVd-YLMKMS7A_J55PowVa"

    private init() {}

    func fetchPatches(for game: LovableGame) async throws -> [LovablePatch] {
        guard var components = URLComponents(
            string: "\(baseURL)/rest/v1/patches"
        ) else {
            throw LovablePatchAPIError.invalidURL
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
            throw LovablePatchAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LovablePatchAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LovablePatchAPIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode([LovablePatch].self, from: data)
    }
}
