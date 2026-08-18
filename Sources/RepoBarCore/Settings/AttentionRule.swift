import Foundation

public struct AttentionRuleID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// Extensible category value. Unknown raw values survive decoding so a newer rule
/// does not invalidate the complete settings payload.
public struct AttentionRuleCategory: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public static let reviewRequests = Self(rawValue: "reviewRequests")
    public static let assignedIssues = Self(rawValue: "assignedIssues")
    public static let assignedPullRequests = Self(rawValue: "assignedPullRequests")
    public static let mentions = Self(rawValue: "mentions")
    public static let subscribedUpdates = Self(rawValue: "subscribedUpdates")
    public static let authoredItems = Self(rawValue: "authoredItems")
    public static let failedWorkflows = Self(rawValue: "failedWorkflows")
    public static let runnerHealth = Self(rawValue: "runnerHealth")
    public static let queuePressure = Self(rawValue: "queuePressure")
    public static let criticalAPIHealth = Self(rawValue: "criticalAPIHealth")

    public static let knownCategories: Set<Self> = [
        .reviewRequests,
        .assignedIssues,
        .assignedPullRequests,
        .mentions,
        .subscribedUpdates,
        .authoredItems,
        .failedWorkflows,
        .runnerHealth,
        .queuePressure,
        .criticalAPIHealth
    ]

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var isKnown: Bool {
        Self.knownCategories.contains(self)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

public enum AttentionItemState: String, Codable, Equatable, Hashable, Sendable {
    case open
    case closed
    case merged
    case pending
    case failing
    case unhealthy
}

public enum AttentionPriority: String, Codable, Equatable, Hashable, Sendable {
    case low
    case normal
    case high
    case critical
}

public struct AttentionRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: AttentionRuleID
    public var enabled: Bool
    public var category: AttentionRuleCategory
    public var accountSelection: AccountSelection
    public var ownerFilters: [String]
    public var repositoryFilters: [String]
    public var itemStates: [AttentionItemState]
    public var priority: AttentionPriority

    public init(
        id: AttentionRuleID,
        enabled: Bool = true,
        category: AttentionRuleCategory,
        accountSelection: AccountSelection = .all,
        ownerFilters: [String] = [],
        repositoryFilters: [String] = [],
        itemStates: [AttentionItemState] = [],
        priority: AttentionPriority = .normal
    ) {
        self.id = id
        self.enabled = enabled
        self.category = category
        self.accountSelection = accountSelection
        self.ownerFilters = ownerFilters
        self.repositoryFilters = repositoryFilters
        self.itemStates = itemStates
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case category
        case accountSelection
        case ownerFilters
        case repositoryFilters
        case itemStates
        case priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(AttentionRuleID.self, forKey: .id)
        self.category = try container.decode(AttentionRuleCategory.self, forKey: .category)
        let decodedEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.enabled = self.category.isKnown ? decodedEnabled : false
        self.accountSelection = try container.decodeIfPresent(
            AccountSelection.self,
            forKey: .accountSelection
        ) ?? .all
        self.ownerFilters = try container.decodeIfPresent([String].self, forKey: .ownerFilters) ?? []
        self.repositoryFilters = try container.decodeIfPresent(
            [String].self,
            forKey: .repositoryFilters
        ) ?? []
        self.itemStates = try container.decodeIfPresent([AttentionItemState].self, forKey: .itemStates) ?? []
        self.priority = try container.decodeIfPresent(AttentionPriority.self, forKey: .priority) ?? .normal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encode(self.category, forKey: .category)
        if case .all = self.accountSelection {
            // Default account inclusion is represented by omission.
        } else {
            try container.encode(self.accountSelection, forKey: .accountSelection)
        }
        if self.ownerFilters.isEmpty == false {
            try container.encode(self.ownerFilters, forKey: .ownerFilters)
        }
        if self.repositoryFilters.isEmpty == false {
            try container.encode(self.repositoryFilters, forKey: .repositoryFilters)
        }
        if self.itemStates.isEmpty == false {
            try container.encode(self.itemStates, forKey: .itemStates)
        }
        if self.priority != .normal {
            try container.encode(self.priority, forKey: .priority)
        }
    }
}

public enum AttentionRulePresets {
    public static func conservativeDefault(
        pinnedRepositories: [String],
        accountSelection: AccountSelection = .all
    ) -> [AttentionRule] {
        let repositories = self.normalizeRepositories(pinnedRepositories)
        guard repositories.isEmpty == false else { return [] }

        return [
            AttentionRule(
                id: AttentionRuleID(rawValue: "default.review-requests"),
                category: .reviewRequests,
                accountSelection: accountSelection,
                repositoryFilters: repositories,
                priority: .high
            ),
            AttentionRule(
                id: AttentionRuleID(rawValue: "default.assigned-issues"),
                category: .assignedIssues,
                accountSelection: accountSelection,
                repositoryFilters: repositories,
                itemStates: [.open],
                priority: .high
            ),
            AttentionRule(
                id: AttentionRuleID(rawValue: "default.assigned-pull-requests"),
                category: .assignedPullRequests,
                accountSelection: accountSelection,
                repositoryFilters: repositories,
                itemStates: [.open],
                priority: .high
            ),
            AttentionRule(
                id: AttentionRuleID(rawValue: "default.failed-workflows"),
                category: .failedWorkflows,
                accountSelection: accountSelection,
                repositoryFilters: repositories,
                itemStates: [.failing],
                priority: .critical
            )
        ]
    }

    private static func normalizeRepositories(_ repositories: [String]) -> [String] {
        var seen: Set<String> = []
        return repositories
            .compactMap { repository -> String? in
                let trimmed = repository.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else { return nil }

                let normalized = trimmed.lowercased()
                guard seen.insert(normalized).inserted else { return nil }

                return normalized
            }
            .sorted()
    }
}
