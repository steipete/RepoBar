import Foundation

public struct UserIdentity: Equatable, Sendable {
    public let username: String
    public let host: URL
    public let planName: String?

    public init(username: String, host: URL, planName: String? = nil) {
        self.username = username
        self.host = host
        self.planName = planName
    }

    public var detectedPlanTier: GitHubPlanTier? {
        Self.planTier(from: self.planName)
    }

    public static func planTier(from name: String?) -> GitHubPlanTier? {
        guard let name = name?.lowercased() else { return nil }

        if name.contains("enterprise") {
            return .enterprise
        }
        if name.contains("team") {
            return .team
        }
        if name.contains("pro") || name.contains("developer") {
            return .pro
        }
        if name.contains("free") {
            return .free
        }
        return nil
    }
}
