import Foundation

// MARK: - Actions Billing / Usage

public struct ActionsUsageInfo: Sendable, Equatable {
    public let items: [ActionsUsageItem]
    public let fetchedAt: Date

    public init(items: [ActionsUsageItem], fetchedAt: Date) {
        self.items = items
        self.fetchedAt = fetchedAt
    }

    public var totalNetAmount: Double {
        self.items.reduce(0) { $0 + $1.netAmount }
    }

    public var totalMinutes: Double {
        self.items
            .filter { $0.unitType.lowercased() == "minutes" }
            .reduce(0) { $0 + $1.quantity }
    }

    public func minutesUsedInCurrentMonth(now: Date = Date()) -> Double {
        let monthFormatter = Self.utcMonthFormatter()
        let currentMonth = monthFormatter.string(from: now)
        return self.items
            .filter { item in
                guard item.unitType.lowercased() == "minutes" else { return false }
                guard let date = Self.date(fromUsageDate: item.date) else { return false }

                return monthFormatter.string(from: date) == currentMonth
            }
            .reduce(0) { $0 + $1.quantity }
    }

    private static func utcMonthFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }

    static func date(fromUsageDate rawDate: String) -> Date? {
        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetFormatter.date(from: rawDate) {
            return date
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = .gmt
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        return dateOnlyFormatter.date(from: rawDate)
    }

    public var minutesByOS: [String: Double] {
        var result: [String: Double] = [:]
        for item in self.items where item.unitType == "minutes" {
            let os = Self.osLabel(for: item.sku)
            result[os, default: 0] += item.quantity
        }
        return result
    }

    public var storageMB: Double {
        self.items
            .filter { $0.unitType == "gb" || $0.sku.contains("STORAGE") }
            .reduce(0) { $0 + $1.quantity * 1024 }
    }

    private static func osLabel(for sku: String) -> String {
        let upper = sku.uppercased()
        if upper.contains("MACOS") || upper.contains("MAC_OS") {
            return "macOS"
        }
        if upper.contains("WINDOWS") {
            return "Windows"
        }
        if upper.contains("LINUX") || upper.contains("UBUNTU") {
            return "Linux"
        }
        return sku
    }
}

public struct ActionsUsageItem: Sendable, Equatable, Codable {
    public let date: String
    public let product: String
    public let sku: String
    public let quantity: Double
    public let unitType: String
    public let pricePerUnit: Double
    public let grossAmount: Double
    public let netAmount: Double
    public let organizationName: String?
    public let repositoryName: String?

    public init(
        date: String,
        product: String,
        sku: String,
        quantity: Double,
        unitType: String,
        pricePerUnit: Double,
        grossAmount: Double,
        netAmount: Double,
        organizationName: String?,
        repositoryName: String?
    ) {
        self.date = date
        self.product = product
        self.sku = sku
        self.quantity = quantity
        self.unitType = unitType
        self.pricePerUnit = pricePerUnit
        self.grossAmount = grossAmount
        self.netAmount = netAmount
        self.organizationName = organizationName
        self.repositoryName = repositoryName
    }

    enum CodingKeys: String, CodingKey {
        case date, product, sku, quantity, unitType, pricePerUnit
        case grossAmount, netAmount, organizationName, repositoryName
    }
}

// MARK: - Per-Org Actions Snapshot

public struct ActionsOrgSnapshot: Sendable, Equatable, Identifiable {
    public let org: String
    public let runners: ActionsRunnerInfo?
    public let queueStatus: ActionsQueueStatus?
    public let planTier: GitHubPlanTier
    public let isOrg: Bool
    public let minutesUsed: Int?
    public let minutesIncluded: Int?
    public let cacheUsage: ActionsCacheUsage?
    public let artifactRetention: ArtifactRetentionPolicy?

    public var id: String {
        self.org
    }

    public init(
        org: String,
        runners: ActionsRunnerInfo?,
        queueStatus: ActionsQueueStatus?,
        planTier: GitHubPlanTier,
        isOrg: Bool = true,
        minutesUsed: Int? = nil,
        minutesIncluded: Int? = nil,
        cacheUsage: ActionsCacheUsage? = nil,
        artifactRetention: ArtifactRetentionPolicy? = nil
    ) {
        self.org = org
        self.runners = runners
        self.queueStatus = queueStatus
        self.planTier = planTier
        self.isOrg = isOrg
        self.minutesUsed = minutesUsed
        self.minutesIncluded = minutesIncluded
        self.cacheUsage = cacheUsage
        self.artifactRetention = artifactRetention
    }

    public var hasRunners: Bool {
        self.runners.map { $0.totalCount > 0 } ?? false
    }

    public var hasActiveJobs: Bool {
        self.queueStatus.map { $0.totalActiveCount > 0 } ?? false
    }
}

// MARK: - Runner Info

public struct ActionsRunnerInfo: Sendable, Equatable {
    public let totalCount: Int
    public let runners: [RunnerSummary]
    public let fetchedAt: Date
    public let scannedRepositoryCount: Int
    public let totalRepositoryCount: Int

    public init(
        totalCount: Int,
        runners: [RunnerSummary],
        fetchedAt: Date,
        scannedRepositoryCount: Int = 0,
        totalRepositoryCount: Int = 0
    ) {
        self.totalCount = totalCount
        self.runners = runners
        self.fetchedAt = fetchedAt
        self.scannedRepositoryCount = scannedRepositoryCount
        self.totalRepositoryCount = totalRepositoryCount
    }

    public var onlineCount: Int {
        self.runners.count(where: { $0.status == "online" })
    }

    public var offlineCount: Int {
        self.runners.count(where: { $0.status == "offline" })
    }

    public var busyCount: Int {
        self.runners.count(where: { $0.busy })
    }

    public var idleCount: Int {
        self.runners.count(where: { $0.status == "online" && !$0.busy })
    }

    public var isRepositorySampled: Bool {
        self.totalRepositoryCount > self.scannedRepositoryCount && self.scannedRepositoryCount > 0
    }

    public var repositorySampleDescription: String? {
        guard self.isRepositorySampled else { return nil }

        return "Sampled \(self.scannedRepositoryCount) of \(self.totalRepositoryCount) repos"
    }
}

public struct RunnerSummary: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let os: String
    public let status: String
    public let busy: Bool
    public let labels: [String]

    public init(id: Int, name: String, os: String, status: String, busy: Bool, labels: [String]) {
        self.id = id
        self.name = name
        self.os = os
        self.status = status
        self.busy = busy
        self.labels = labels
    }
}

// MARK: - Actions Plan Limits (hardcoded per GitHub docs — no API exposes these)

public enum GitHubPlanTier: String, CaseIterable, Equatable, Codable, Sendable {
    case free = "Free"
    case pro = "Pro"
    case team = "Team"
    case enterprise = "Enterprise"

    public var includedMinutesPerMonth: Int {
        switch self {
        case .free: 2000
        case .pro: 3000
        case .team: 3000
        case .enterprise: 50000
        }
    }

    public var includedStorageGB: Double {
        switch self {
        case .free: 0.5
        case .pro: 1.0
        case .team: 2.0
        case .enterprise: 50.0
        }
    }

    public var concurrentJobs: Int {
        switch self {
        case .free: 20
        case .pro: 40
        case .team: 60
        case .enterprise: 500
        }
    }

    public var concurrentMacOSJobs: Int {
        switch self {
        case .free: 5
        case .pro: 5
        case .team: 5
        case .enterprise: 50
        }
    }

    public var maxJobExecutionHours: Int {
        6
    }

    public var maxWorkflowRunHours: Int {
        35
    }

    public var maxWorkflowRunDaysQueued: Int {
        35
    }

    public var jobMatrixMax: Int {
        switch self {
        case .free: 256
        case .pro, .team, .enterprise: 256
        }
    }

    public var label: String {
        self.rawValue
    }
}

// MARK: - OS Minute Multipliers (GitHub bills macOS/Windows at higher rates)

public enum ActionsMinuteMultiplier {
    public static let linux: Double = 1.0
    public static let windows: Double = 2.0
    public static let macOS: Double = 10.0

    public static func multiplier(for os: String) -> Double {
        let lower = os.lowercased()
        if lower.contains("macos") || lower.contains("mac") {
            return self.macOS
        }
        if lower.contains("windows") || lower.contains("win") {
            return self.windows
        }
        return self.linux
    }
}

// MARK: - Queued / In-Progress Workflow Runs

public struct ActiveWorkflowRun: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let repoFullName: String
    public let headBranch: String
    public let status: String
    public let event: String
    public let actor: String
    public let htmlURL: URL?
    public let startedAt: Date?

    public init(id: Int, name: String, repoFullName: String, headBranch: String, status: String, event: String, actor: String, htmlURL: URL?, startedAt: Date?) {
        self.id = id
        self.name = name
        self.repoFullName = repoFullName
        self.headBranch = headBranch
        self.status = status
        self.event = event
        self.actor = actor
        self.htmlURL = htmlURL
        self.startedAt = startedAt
    }

    public var isQueued: Bool {
        self.status == "queued" || self.status == "waiting" || self.status == "pending"
    }

    public var isRunning: Bool {
        self.status == "in_progress"
    }

    public var repoName: String {
        self.repoFullName.components(separatedBy: "/").last ?? self.repoFullName
    }
}

public struct ActionsQueueStatus: Sendable, Equatable {
    public let inProgressCount: Int
    public let queuedCount: Int
    public let runs: [ActiveWorkflowRun]
    public let fetchedAt: Date
    public let scannedRepositoryCount: Int
    public let totalRepositoryCount: Int

    public init(
        inProgressCount: Int,
        queuedCount: Int,
        runs: [ActiveWorkflowRun] = [],
        fetchedAt: Date,
        scannedRepositoryCount: Int = 0,
        totalRepositoryCount: Int = 0
    ) {
        self.inProgressCount = inProgressCount
        self.queuedCount = queuedCount
        self.runs = runs
        self.fetchedAt = fetchedAt
        self.scannedRepositoryCount = scannedRepositoryCount
        self.totalRepositoryCount = totalRepositoryCount
    }

    public var totalActiveCount: Int {
        self.inProgressCount + self.queuedCount
    }

    public func remainingConcurrentJobs(limit: Int) -> Int {
        max(0, limit - self.inProgressCount)
    }

    public func remainingConcurrentPercent(limit: Int) -> Double {
        guard limit > 0 else { return 100 }

        let pct = (1.0 - Double(self.inProgressCount) / Double(limit)) * 100
        return min(100, max(0, pct))
    }

    public var isRepositorySampled: Bool {
        self.totalRepositoryCount > self.scannedRepositoryCount && self.scannedRepositoryCount > 0
    }

    public var repositorySampleDescription: String? {
        guard self.isRepositorySampled else { return nil }

        return "Sampled \(self.scannedRepositoryCount) of \(self.totalRepositoryCount) repos"
    }
}

// MARK: - Actions Cache Usage

public struct ActionsCacheUsage: Sendable, Equatable {
    public let totalCachesCount: Int
    public let totalCachesSizeBytes: Int

    public init(totalCachesCount: Int, totalCachesSizeBytes: Int) {
        self.totalCachesCount = totalCachesCount
        self.totalCachesSizeBytes = totalCachesSizeBytes
    }

    public var cacheSizeMB: Double {
        Double(self.totalCachesSizeBytes) / (1024 * 1024)
    }

    public var cacheSizeGB: Double {
        Double(self.totalCachesSizeBytes) / (1024 * 1024 * 1024)
    }
}

// MARK: - Artifact Retention Policy

public struct ArtifactRetentionPolicy: Sendable, Equatable {
    public let retentionDays: Int
    public let maxAllowedDays: Int

    public init(retentionDays: Int, maxAllowedDays: Int) {
        self.retentionDays = retentionDays
        self.maxAllowedDays = maxAllowedDays
    }
}

// MARK: - Hosted Runner Limits

public struct HostedRunnerLimits: Sendable, Equatable {
    public let publicIPs: ResourceLimit?
    public let fetchedAt: Date

    public init(publicIPs: ResourceLimit?, fetchedAt: Date) {
        self.publicIPs = publicIPs
        self.fetchedAt = fetchedAt
    }

    public struct ResourceLimit: Sendable, Equatable {
        public let maximum: Int
        public let currentUsage: Int

        public init(maximum: Int, currentUsage: Int) {
            self.maximum = maximum
            self.currentUsage = currentUsage
        }

        public var remaining: Int {
            max(0, self.maximum - self.currentUsage)
        }

        public var usagePercent: Double {
            guard self.maximum > 0 else { return 0 }

            return Double(self.currentUsage) / Double(self.maximum) * 100
        }
    }
}
