import Foundation
@testable import RepoBarCore
import Testing

struct MultiAccountSettingsContractTests {
    @Test
    func `legacy settings decode with consolidated features disabled`() throws {
        let legacyJSON = """
        {
            "githubHost": "https://github.com",
            "aiSummaries": {
                "enabled": true,
                "model": "gpt-5.5"
            }
        }
        """

        let settings = try JSONDecoder().decode(
            UserSettings.self,
            from: #require(legacyJSON.data(using: .utf8))
        )

        #expect(settings.consolidateAccounts == false)
        #expect(settings.aiSummaries.allowNonActiveAccountContent == false)
        #expect(settings.attentionRules.isEmpty)
    }

    @Test
    func `new settings round trip without changing account selection`() throws {
        var settings = UserSettings()
        settings.consolidateAccounts = true
        settings.accountSelection = .only(["github.com#alice"])
        settings.aiSummaries.allowNonActiveAccountContent = true
        settings.attentionRules = [
            AttentionRule(
                id: AttentionRuleID(rawValue: "custom.review"),
                category: .reviewRequests,
                accountSelection: .only(["github.com#alice"]),
                ownerFilters: ["example"],
                repositoryFilters: ["example/repo"],
                itemStates: [.open],
                priority: .high
            )
        ]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)

        #expect(decoded == settings)
        #expect(decoded.accountSelection == .only(["github.com#alice"]))
    }

    @Test
    func `default settings omit new contracts`() throws {
        let data = try JSONEncoder().encode(UserSettings())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aiSummaries = try #require(object["aiSummaries"] as? [String: Any])

        #expect(object["consolidateAccounts"] == nil)
        #expect(object["attentionRules"] == nil)
        #expect(aiSummaries["allowNonActiveAccountContent"] == nil)
    }
}

struct AttentionRuleContractTests {
    @Test
    func `unknown category is preserved and safely disabled`() throws {
        let json = """
        {
            "attentionRules": [
                {
                    "id": "future.rule",
                    "enabled": true,
                    "category": "futureCategory",
                    "repositoryFilters": ["example/repo"]
                }
            ]
        }
        """

        let settings = try JSONDecoder().decode(
            UserSettings.self,
            from: #require(json.data(using: .utf8))
        )
        let rule = try #require(settings.attentionRules.first)

        #expect(rule.category.rawValue == "futureCategory")
        #expect(rule.category.isKnown == false)
        #expect(rule.enabled)
        #expect(rule.isEffectivelyEnabled == false)
        #expect(rule.repositoryFilters == ["example/repo"])

        let encoded = try JSONEncoder().encode(settings)
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedRules = try #require(encodedObject["attentionRules"] as? [[String: Any]])
        #expect(encodedRules.first?["enabled"] as? Bool == true)

        let roundTrip = try JSONDecoder().decode(
            UserSettings.self,
            from: encoded
        )
        #expect(roundTrip.attentionRules.first?.category.rawValue == "futureCategory")
        #expect(roundTrip.attentionRules.first?.enabled == true)
        #expect(roundTrip.attentionRules.first?.isEffectivelyEnabled == false)
    }

    @Test
    func `missing optional rule fields use compatibility defaults`() throws {
        let json = """
        {
            "id": "minimal.rule",
            "category": "mentions"
        }
        """

        let rule = try JSONDecoder().decode(
            AttentionRule.self,
            from: #require(json.data(using: .utf8))
        )

        #expect(rule.enabled)
        #expect(rule.accountSelection == .all)
        #expect(rule.ownerFilters.isEmpty)
        #expect(rule.repositoryFilters.isEmpty)
        #expect(rule.itemStates.isEmpty)
        #expect(rule.priority == .normal)

        let encoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any]
        )
        #expect(encoded["accountSelection"] == nil)
        #expect(encoded["ownerFilters"] == nil)
        #expect(encoded["repositoryFilters"] == nil)
        #expect(encoded["itemStates"] == nil)
        #expect(encoded["priority"] == nil)
    }

    @Test
    func `first version categories are complete and stable`() {
        #expect(AttentionRuleCategory.knownCategories == [
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
        ])
    }

    @Test
    func `conservative preset is deterministic and pinned only`() {
        let selection = AccountSelection.only(["github.com#alice"])
        let first = AttentionRulePresets.conservativeDefault(
            pinnedRepositories: [" Example/Zeta ", "example/alpha", "EXAMPLE/ZETA", ""],
            accountSelection: selection
        )
        let second = AttentionRulePresets.conservativeDefault(
            pinnedRepositories: ["example/alpha", "example/zeta"],
            accountSelection: selection
        )

        #expect(first == second)
        #expect(first.map(\.id.rawValue) == [
            "default.review-requests",
            "default.assigned-issues",
            "default.assigned-pull-requests",
            "default.failed-workflows"
        ])
        #expect(first.map(\.category) == [
            .reviewRequests,
            .assignedIssues,
            .assignedPullRequests,
            .failedWorkflows
        ])
        for rule in first {
            #expect(rule.enabled)
        }
        #expect(first.allSatisfy { $0.accountSelection == selection })
        #expect(first.allSatisfy { $0.repositoryFilters == ["example/alpha", "example/zeta"] })
        #expect(AttentionRulePresets.conservativeDefault(pinnedRepositories: []).isEmpty)
    }
}

struct AccountScopedIdentityTests {
    @Test
    func `same repository is distinct across account sources`() {
        let personal = AccountScopedRepositoryIdentity(
            accountID: "github.com#alice",
            repositoryID: "R_123"
        )
        let work = AccountScopedRepositoryIdentity(
            accountID: "github.com#alice-work",
            repositoryID: "R_123"
        )

        #expect(personal != work)
        #expect(Set([personal, work]).count == 2)
    }

    @Test
    func `same URL is distinct across account sources and codable`() throws {
        let url = try #require(URL(string: "https://github.com/example/repo/pull/1"))
        let personal = AccountScopedURLIdentity(accountID: "github.com#alice", url: url)
        let work = AccountScopedURLIdentity(accountID: "github.com#alice-work", url: url)

        #expect(personal != work)
        #expect(Set([personal, work]).count == 2)

        let decoded = try JSONDecoder().decode(
            AccountScopedURLIdentity.self,
            from: JSONEncoder().encode(personal)
        )
        #expect(decoded == personal)
    }

    @Test
    func `event and cache identities include account source`() {
        let personalEvent = AccountScopedEventIdentity(
            accountID: "github.com#alice",
            namespace: "pull-request",
            eventID: "42"
        )
        let workEvent = AccountScopedEventIdentity(
            accountID: "github.com#alice-work",
            namespace: "pull-request",
            eventID: "42"
        )
        let personalCache = AccountScopedCacheKey(accountID: "github.com#alice", key: "repos")
        let workCache = AccountScopedCacheKey(accountID: "github.com#alice-work", key: "repos")

        #expect(personalEvent != workEvent)
        #expect(personalCache != workCache)
    }
}
