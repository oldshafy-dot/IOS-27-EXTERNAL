import CryptoKit
import Foundation

enum PackageRepositoryError: Error, Equatable {
    case insecureURL
    case unsupportedSchema
    case invalidManifest
    case invalidPackage
    case duplicatePackage
    case sourceAlreadyExists
    case sourceUnavailable
    case checksumMismatch
    case packageIdentityMismatch
    case incompatiblePackage
    case importUnavailable
}

extension PackageRepositoryError: LocalizedError {
    var localizationKey: String {
        switch self {
        case .insecureURL: return "repository.error.insecure_url"
        case .unsupportedSchema: return "repository.error.unsupported_schema"
        case .invalidManifest: return "repository.error.invalid_manifest"
        case .invalidPackage: return "repository.error.invalid_package"
        case .duplicatePackage: return "repository.error.duplicate_package"
        case .sourceAlreadyExists: return "repository.error.source_exists"
        case .sourceUnavailable: return "repository.error.source_unavailable"
        case .checksumMismatch: return "repository.error.checksum"
        case .packageIdentityMismatch: return "repository.error.identity"
        case .incompatiblePackage: return "repository.error.incompatible"
        case .importUnavailable: return "repository.error.import_unavailable"
        }
    }

    var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

struct PackageRepositoryDocument: Decodable {
    let schemaVersion: Int
    let identifier: String
    let name: String
    let description: String?
    let icon: String?
    let packages: [PackageRepositoryPackageDocument]
}

struct PackageRepositoryCatalogDocument: Decodable {
    let schemaVersion: Int
    let sources: [String]
}

struct PackageRepositoryPackageDocument: Decodable {
    let identifier: String
    let kind: RepositoryPackageKind?
    let name: String
    let author: String
    let version: String
    let summary: String
    let description: String?
    let category: String?
    let tags: [String]?
    let publishedAt: String?
    let icon: String?
    let banner: String?
    let screenshots: [String]?
    let download: String
    let sha256: String?
    let size: UInt64?
    let supportedOS: [PackageOSRange]
    let changelog: String?
    let featured: Bool?
    let isPrivate: Bool?
    let password: String?
}

enum RepositoryPackageKind: String, Codable, Hashable {
    case patch
    case wallpaper
}

struct PackageOSRange: Codable, Hashable {
    let minimum: String
    let maximum: String
    let builds: [String]?
}

struct PackageRepository: Identifiable, Hashable {
    let identifier: String
    let name: String
    let summary: String?
    let iconURL: URL?
    let sourceURL: URL
    let packages: [RepositoryPackage]

    var id: String {
        identifier
    }
}

struct RepositoryPackage: Identifiable, Hashable {
    let identifier: String
    let kind: RepositoryPackageKind
    let name: String
    let author: String
    let version: String
    let summary: String
    let details: String?
    let category: String?
    let tags: [String]
    let publishedAt: Date?
    let iconURL: URL?
    let bannerURL: URL?
    let screenshotURLs: [URL]
    let downloadURL: URL
    let sha256: String?
    let expectedSize: UInt64?
    let supportedOS: [PackageOSRange]
    let changelog: String?
    let isFeatured: Bool
    let isPrivate: Bool
    let sharedPassword: String?

    var id: String {
        identifier
    }
}

struct RepositoryPackageRecord: Identifiable, Hashable {
    let sourceID: UUID
    let sourceName: String
    let sourceURL: URL
    let package: RepositoryPackage

    var id: String {
        "\(sourceID.uuidString)|\(package.identifier)"
    }

    var repositoryIdentity: String {
        "\(sourceURL.absoluteString)|\(package.identifier)"
    }
}

struct RepositoryPackageResolutionIndex: Codable, Equatable {
    var values: [String: UUID] = [:]

    func packageID(
        for repositoryIdentity: String
    ) -> UUID? {
        values[repositoryIdentity]
    }

    mutating func set(
        packageID: UUID,
        for repositoryIdentity: String
    ) {
        values[repositoryIdentity] = packageID
    }

    mutating func remove(
        repositoryIdentity: String
    ) {
        values.removeValue(forKey: repositoryIdentity)
    }
}

struct RepositorySource: Codable, Identifiable, Hashable {
    let id: UUID
    var manifestURL: URL
    var isEnabled: Bool
    let addedAt: Date

    init(
        id: UUID = UUID(),
        manifestURL: URL,
        isEnabled: Bool = true,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.manifestURL = manifestURL
        self.isEnabled = isEnabled
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(
            UUID.self,
            forKey: .id
        )

        manifestURL = try container.decode(
            URL.self,
            forKey: .manifestURL
        )

        isEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? true

        addedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .addedAt
        ) ?? Date()
    }
}

enum RepositorySourceState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum PackageCompatibility: Equatable {
    case compatible
    case incompatible
    case unknown
}

enum PackageRepositoryLimits {
    static let maximumPackagesPerRepository = 500
    static let maximumSources = 20
    static let maximumManifestBytes = 2_000_000
    static let maximumPackageBytes = 250_000_000
}

enum PackageRepositoryDefaults {
    static let primarySourceURL = URL(
        string:
            "https://raw.githubusercontent.com/YangJiiii/3105-repo/main/sources.json"
    )!
}

enum PackageRepositoryURLPolicy {
    static func validate(_ url: URL) throws -> URL {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "https"
        else {
            throw PackageRepositoryError.insecureURL
        }

        guard url.host != nil else {
            throw PackageRepositoryError.insecureURL
        }

        return url
    }

    static func resolve(
        _ rawValue: String,
        relativeTo baseURL: URL
    ) throws -> URL {
        guard
            let url = URL(
                string: rawValue,
                relativeTo: baseURL
            )?.absoluteURL
        else {
            throw PackageRepositoryError.insecureURL
        }

        return try validate(url)
    }
}

enum PackageRepositoryValidator {
    static func decode(
        _ data: Data,
        sourceURL: URL
    ) throws -> PackageRepository {
        guard data.count <= PackageRepositoryLimits.maximumManifestBytes else {
            throw PackageRepositoryError.invalidManifest
        }

        let decoder = JSONDecoder()

        let document: PackageRepositoryDocument

        do {
            document = try decoder.decode(
                PackageRepositoryDocument.self,
                from: data
            )
        } catch {
            throw PackageRepositoryError.invalidManifest
        }

        guard
            document.schemaVersion >= 1,
            document.schemaVersion <= 3
        else {
            throw PackageRepositoryError.unsupportedSchema
        }

        guard
            !document.identifier.isEmpty,
            !document.name.isEmpty
        else {
            throw PackageRepositoryError.invalidManifest
        }

        guard
            document.packages.count
                <= PackageRepositoryLimits.maximumPackagesPerRepository
        else {
            throw PackageRepositoryError.invalidManifest
        }

        var identifiers = Set<String>()
        var packages: [RepositoryPackage] = []

        for item in document.packages {
            guard
                !item.identifier.isEmpty,
                identifiers.insert(item.identifier).inserted,
                !item.name.isEmpty,
                !item.author.isEmpty,
                !item.version.isEmpty,
                !item.download.isEmpty
            else {
                throw PackageRepositoryError.invalidPackage
            }

            let kind = item.kind ?? .patch

            let downloadURL = try PackageRepositoryURLPolicy.resolve(
                item.download,
                relativeTo: sourceURL
            )

            let iconURL = try item.icon.map {
                try PackageRepositoryURLPolicy.resolve(
                    $0,
                    relativeTo: sourceURL
                )
            }

            let bannerURL = try item.banner.map {
                try PackageRepositoryURLPolicy.resolve(
                    $0,
                    relativeTo: sourceURL
                )
            }

            let screenshotURLs = try (item.screenshots ?? []).map {
                try PackageRepositoryURLPolicy.resolve(
                    $0,
                    relativeTo: sourceURL
                )
            }

            if kind == .patch {
                guard
                    downloadURL.pathExtension.lowercased() == "robo"
                else {
                    throw PackageRepositoryError.invalidPackage
                }
            }

            if let size = item.size {
                guard
                    size <= PackageRepositoryLimits.maximumPackageBytes
                else {
                    throw PackageRepositoryError.invalidPackage
                }
            }

            packages.append(
                RepositoryPackage(
                    identifier: item.identifier,
                    kind: kind,
                    name: item.name,
                    author: item.author,
                    version: item.version,
                    summary: item.summary,
                    details: item.description,
                    category: item.category,
                    tags: item.tags ?? [],
                    publishedAt: parseDate(item.publishedAt),
                    iconURL: iconURL,
                    bannerURL: bannerURL,
                    screenshotURLs: screenshotURLs,
                    downloadURL: downloadURL,
                    sha256: normalizeSHA256(item.sha256),
                    expectedSize: item.size,
                    supportedOS: item.supportedOS,
                    changelog: item.changelog,
                    isFeatured: item.featured ?? false,
                    isPrivate: item.isPrivate ?? false,
                    sharedPassword: item.password
                )
            )
        }

        return PackageRepository(
            identifier: document.identifier,
            name: document.name,
            summary: document.description,
            iconURL: try document.icon.map {
                try PackageRepositoryURLPolicy.resolve(
                    $0,
                    relativeTo: sourceURL
                )
            },
            sourceURL: sourceURL,
            packages: packages
        )
    }

    private static func parseDate(
        _ value: String?
    ) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = ISO8601DateFormatter()

        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        return formatter.date(from: value)
    }

    private static func normalizeSHA256(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        guard normalized.count == 64 else {
            return nil
        }

        guard normalized.allSatisfy({
            $0.isHexDigit
        }) else {
            return nil
        }

        return normalized
    }
}

enum PackageRepositoryPinnedWallpaperURLPolicy {
    static func validate(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "https",
            let host = url.host?.lowercased()
        else {
            return false
        }

        return !host.isEmpty
    }
}

enum PackageRepositoryCatalogValidator {
    static func decode(
        _ data: Data,
        catalogURL: URL
    ) throws -> [URL] {
        guard data.count <= PackageRepositoryLimits.maximumManifestBytes else {
            throw PackageRepositoryError.invalidManifest
        }

        let document: PackageRepositoryCatalogDocument

        do {
            document = try JSONDecoder().decode(
                PackageRepositoryCatalogDocument.self,
                from: data
            )
        } catch {
            throw PackageRepositoryError.invalidManifest
        }

        guard
            document.schemaVersion >= 1,
            document.schemaVersion <= 3,
            document.sources.count
                <= PackageRepositoryLimits.maximumSources
        else {
            throw PackageRepositoryError.unsupportedSchema
        }

        var result: [URL] = []
        var seen = Set<String>()

        for rawValue in document.sources {
            let url = try PackageRepositoryURLPolicy.resolve(
                rawValue,
                relativeTo: catalogURL
            )

            guard
                seen.insert(url.absoluteString).inserted
            else {
                continue
            }

            result.append(url)
        }

        return result
    }
}

enum RepositorySourceMergePolicy {
    static func merge(
        existing: [RepositorySource],
        incoming: [RepositorySource]
    ) -> [RepositorySource] {
        var result = existing

        for source in incoming {
            if let index = result.firstIndex(
                where: {
                    $0.manifestURL.absoluteString
                        .caseInsensitiveCompare(
                            source.manifestURL.absoluteString
                        ) == .orderedSame
                }
            ) {
                result[index] = source
            } else {
                result.append(source)
            }
        }

        return Array(
            result.prefix(
                PackageRepositoryLimits.maximumSources
            )
        )
    }
}

private extension PackageRepositoryPackageDocument {
    var expectedSizeIsValid: Bool {
        guard let size else {
            return true
        }

        return size <= PackageRepositoryLimits.maximumPackageBytes
    }
}

struct PackageSystemVersion: Comparable, Hashable {
    let major: Int
    let minor: Int
    let patch: Int

    init(
        major: Int,
        minor: Int,
        patch: Int
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ rawValue: String) {
        let values = rawValue
            .split(separator: ".")
            .prefix(3)
            .compactMap {
                Int($0)
            }

        guard !values.isEmpty else {
            return nil
        }

        major = values.indices.contains(0)
            ? values[0]
            : 0

        minor = values.indices.contains(1)
            ? values[1]
            : 0

        patch = values.indices.contains(2)
            ? values[2]
            : 0
    }

    static func < (
        lhs: PackageSystemVersion,
        rhs: PackageSystemVersion
    ) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }

        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }

        return lhs.patch < rhs.patch
    }
}

enum PackageCompatibilityEvaluator {
    static func evaluate(
        package: RepositoryPackage,
        systemVersion: String
    ) -> PackageCompatibility {
        guard
            let current = PackageSystemVersion(systemVersion)
        else {
            return .unknown
        }

        guard !package.supportedOS.isEmpty else {
            return .unknown
        }

        for range in package.supportedOS {
            guard
                let minimum = PackageSystemVersion(
                    range.minimum
                ),
                let maximum = PackageSystemVersion(
                    range.maximum
                )
            else {
                continue
            }

            if current >= minimum && current <= maximum {
                if let builds = range.builds,
                   !builds.isEmpty {
                    return builds.contains(
                        systemVersion
                    )
                    ? .compatible
                    : .incompatible
                }

                return .compatible
            }
        }

        return .incompatible
    }
}

struct RepositoryTagGroup: Identifiable, Hashable {
    let name: String
    let packages: [RepositoryPackage]

    var id: String {
        name
    }
}

enum PackageRepositoryTagIndex {
    static func groups(
        for packages: [RepositoryPackage]
    ) -> [RepositoryTagGroup] {
        var grouped: [String: [RepositoryPackage]] = [:]

        for package in packages {
            for tag in package.tags {
                let normalized = tag
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                guard !normalized.isEmpty else {
                    continue
                }

                grouped[normalized, default: []]
                    .append(package)
            }
        }

        return grouped.keys.sorted(
            by: {
                $0.localizedCaseInsensitiveCompare($1)
                    == .orderedAscending
            }
        ).map {
            RepositoryTagGroup(
                name: $0,
                packages: grouped[$0] ?? []
            )
        }
    }
}

enum PackageRepositoryNewIndex {
    static func sorted(
        _ packages: [RepositoryPackage]
    ) -> [RepositoryPackage] {
        packages.sorted {
            if $0.isFeatured != $1.isFeatured {
                return $0.isFeatured
            }

            if let lhs = $0.publishedAt,
               let rhs = $1.publishedAt,
               lhs != rhs {
                return lhs > rhs
            }

            return $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    static func sorted(
        _ records: [RepositoryPackageRecord]
    ) -> [RepositoryPackageRecord] {
        records.sorted {
            if $0.package.isFeatured
                != $1.package.isFeatured {
                return $0.package.isFeatured
            }

            if let lhs = $0.package.publishedAt,
               let rhs = $1.package.publishedAt,
               lhs != rhs {
                return lhs > rhs
            }

            return $0.package.name.localizedCaseInsensitiveCompare(
                $1.package.name
            ) == .orderedAscending
        }
    }
}

enum PackageRepositoryFeedPolicy {
    static func home(
        packages: [RepositoryPackage]
    ) -> [RepositoryPackage] {
        PackageRepositoryNewIndex.sorted(packages)
    }

    static func newest(
        packages: [RepositoryPackage]
    ) -> [RepositoryPackage] {
        PackageRepositoryNewIndex.sorted(packages)
    }

    static func parse(
        _ rawValue: String
    ) -> Date? {
        let formatter = ISO8601DateFormatter()

        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        return formatter.date(from: rawValue)
    }
}

enum PackageDigest {
    static func sha256Hex(
        _ data: Data
    ) -> String {
        SHA256.hash(data: data)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    static func sha256Hex(
        fileURL: URL
    ) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return sha256Hex(data)
    }
}
