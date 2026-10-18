import Foundation

struct RepoDetailCache: Codable, Sendable {
    var openPulls: Int?
    var openPullsFetchedAt: Date?
    var ciDetails: CIStatusDetails?
    var ciFetchedAt: Date?
    var latestActivity: ActivityEvent?
    var activityEvents: [ActivityEvent]?
    var activityFetchedAt: Date?
    var traffic: TrafficStats?
    var trafficFetchedAt: Date?
    var heatmap: [HeatmapCell]?
    var heatmapFetchedAt: Date?
    var latestRelease: Release?
    var releaseFetchedAt: Date?
    var discussionsEnabled: Bool?
    var discussionsCheckedAt: Date?
}

struct RepoDetailCacheStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL?
    private let write: @Sendable (Data, URL) throws -> Void
    private var lastWrittenData: Data?
    private var prepared = false

    init(
        fileManager: FileManager = .default,
        baseURL: URL? = nil,
        write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.baseURL = baseURL ?? Self.defaultBaseURL(fileManager: fileManager)
        self.write = write
    }

    mutating func load() -> [String: RepoDetailCache] {
        self.prepare()
        guard let url = self.cacheFileURL, let data = try? Data(contentsOf: url) else { return [:] }

        do {
            let cache = try self.decoder.decode([String: RepoDetailCache].self, from: data)
            self.lastWrittenData = data
            return cache
        } catch {
            try? self.fileManager.removeItem(at: url)
            return [:]
        }
    }

    /// Returns success for an unchanged snapshot as well as a completed write.
    mutating func save(_ cache: [String: RepoDetailCache]) -> Bool {
        self.prepare()
        guard let url = self.cacheFileURL else { return false }

        do {
            let data = try self.encoder.encode(cache)
            guard data != self.lastWrittenData else { return true }

            try self.fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try self.write(data, url)
            self.lastWrittenData = data
            return true
        } catch {
            return false
        }
    }

    mutating func clear() {
        self.prepare()
        if let url = self.cacheFileURL {
            try? self.fileManager.removeItem(at: url)
        }
        self.lastWrittenData = nil
    }

    private var cacheFileURL: URL? {
        self.baseURL?.appendingPathExtension("json")
    }

    private mutating func prepare() {
        guard !self.prepared else { return }

        self.prepared = true
        // The old per-repository directory is disposable; the snapshot lives beside it.
        if let baseURL {
            try? self.fileManager.removeItem(at: baseURL)
        }
    }

    private static func defaultBaseURL(fileManager: FileManager) -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "RepoBar"
        return support
            .appending(path: bundleID)
            .appending(path: "RepoDetailCache")
    }
}
