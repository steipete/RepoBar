import Foundation
import RepoBarCore

extension AppState {
    func refreshActionsLimitsState() async {
        let settings = self.session.settings.actions
        let menuCustomization = self.session.settings.menuCustomization.normalized()
        guard !menuCustomization.hiddenMainMenuItems.contains(.actionsLimits) else { return }
        guard case let .loggedIn(user) = self.session.account else { return }

        let github = self.github
        let repos = Self.actionsRepositories(
            repositories: self.session.repositories,
            menuSnapshot: self.session.menuSnapshot
        )

        let userTier = user.detectedPlanTier ?? settings.planTier
        await MainActor.run { self.session.actionsPlanTier = userTier }

        let owners = Self.actionsOwners(
            username: user.username,
            repositories: repos,
            monitoredOwners: self.session.settings.monitoredOwners
        )
        if Task.isCancelled {
            return
        }

        await self.publishActionsOwnerPlaceholders(owners: owners, planTier: userTier)

        var snapshots: [ActionsOrgSnapshot] = []
        for owner in owners {
            if Task.isCancelled {
                return
            }

            let ownerRepos = repos.filter { $0.owner.lowercased() == owner.name.lowercased() }
            let runners = await Self.fetchRunners(github: github, owner: owner.name, repos: ownerRepos)
            let queue = await Self.fetchQueueStatus(github: github, repos: ownerRepos)

            var ownerTier = userTier
            if let detected = await Self.detectedPlanTier(for: owner, github: github) {
                ownerTier = detected
            }

            let billingUsage = try? await github.actionsBillingUsage(owner: owner.name, isOrg: owner.isOrg)
            let minutesUsed = billingUsage.map { Int($0.minutesUsedInCurrentMonth().rounded()) }
            let minutesIncluded = ownerTier.includedMinutesPerMonth
            let cacheUsage = await owner.isOrg ? (try? github.actionsCacheUsage(org: owner.name)) : nil
            let artifactRetention = await owner.isOrg ? (try? github.artifactRetentionPolicy(org: owner.name)) : nil

            snapshots.append(ActionsOrgSnapshot(
                org: owner.name,
                runners: runners,
                queueStatus: queue,
                planTier: ownerTier,
                isOrg: owner.isOrg,
                minutesUsed: minutesUsed,
                minutesIncluded: minutesIncluded,
                cacheUsage: cacheUsage,
                artifactRetention: artifactRetention
            ))
        }

        await MainActor.run {
            self.session.actionsOrgSnapshots = snapshots
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
    }

    static func actionsRepositories(repositories: [Repository], menuSnapshot: MenuSnapshot?) -> [Repository] {
        if repositories.isEmpty == false {
            return repositories
        }

        return menuSnapshot?.repositories ?? []
    }

    private func publishActionsOwnerPlaceholders(
        owners: [(name: String, isOrg: Bool)],
        planTier: GitHubPlanTier
    ) async {
        let snapshots = owners.map { owner in
            ActionsOrgSnapshot(
                org: owner.name,
                runners: nil,
                queueStatus: nil,
                planTier: planTier,
                isOrg: owner.isOrg,
                minutesIncluded: planTier.includedMinutesPerMonth
            )
        }

        await MainActor.run {
            guard self.session.actionsOrgSnapshots != snapshots else { return }

            self.session.actionsOrgSnapshots = snapshots
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
    }

    private static func detectedPlanTier(
        for owner: (name: String, isOrg: Bool),
        github: GitHubClient
    ) async -> GitHubPlanTier? {
        guard owner.isOrg,
              let orgPlanName = try? await github.organizationPlan(org: owner.name)
        else { return nil }

        return UserIdentity.planTier(from: orgPlanName)
    }

    static func actionsOwners(
        username: String,
        repositories repos: [Repository],
        monitoredOwners: [String]
    ) -> [(name: String, isOrg: Bool)] {
        let usernameKey = username.lowercased()
        let filteredOwners = OwnerFilter.normalize(monitoredOwners)
        if !filteredOwners.isEmpty {
            return filteredOwners.map { owner in
                (name: owner, isOrg: owner.lowercased() != usernameKey)
            }
        }

        var owners: [(name: String, isOrg: Bool)] = [(name: username, isOrg: false)]
        owners.append(contentsOf: Self.repoOwners(from: repos, excludingUsername: username).map { (name: $0, isOrg: true) })
        return owners
    }

    private static func repoOwners(from repos: [Repository], excludingUsername username: String) -> [String] {
        var seen = Set<String>([username.lowercased()])
        var result: [String] = []
        for repo in repos where seen.insert(repo.owner.lowercased()).inserted {
            result.append(repo.owner)
        }
        return result
    }

    private static func fetchRunners(
        github: GitHubClient,
        owner: String,
        repos: [Repository]
    ) async -> ActionsRunnerInfo? {
        let orgRunners = try? await github.selfHostedRunners(owner: owner)
        if !Self.shouldScanRepositoryRunners(after: orgRunners, repos: repos) {
            return orgRunners
        }

        let sample = Array(repos.prefix(5))
        var repositoryRunners: [ActionsRunnerInfo] = []
        let now = Date()

        for repo in sample {
            guard let info = try? await github.selfHostedRunners(owner: repo.owner, repo: repo.name) else {
                continue
            }

            repositoryRunners.append(info)
        }

        return Self.combinedRunnerInfo(
            orgRunners: orgRunners,
            repositoryRunners: repositoryRunners,
            scannedRepositoryCount: sample.count,
            totalRepositoryCount: repos.count,
            fetchedAt: now
        )
    }

    static func shouldScanRepositoryRunners(after _: ActionsRunnerInfo?, repos: [Repository]) -> Bool {
        guard !repos.isEmpty else { return false }

        return true
    }

    static func combinedRunnerInfo(
        orgRunners: ActionsRunnerInfo?,
        repositoryRunners: [ActionsRunnerInfo],
        scannedRepositoryCount: Int,
        totalRepositoryCount: Int,
        fetchedAt: Date
    ) -> ActionsRunnerInfo? {
        var seenRunnerIDs: Set<Int> = []
        let runners = ((orgRunners?.runners ?? []) + repositoryRunners.flatMap(\.runners)).filter { runner in
            seenRunnerIDs.insert(runner.id).inserted
        }
        let totalCount = runners.count
        let isSampled = totalRepositoryCount > scannedRepositoryCount && scannedRepositoryCount > 0
        guard totalCount > 0 || isSampled else { return nil }

        return ActionsRunnerInfo(
            totalCount: totalCount,
            runners: runners,
            fetchedAt: fetchedAt,
            scannedRepositoryCount: scannedRepositoryCount,
            totalRepositoryCount: totalRepositoryCount
        )
    }

    private static func fetchQueueStatus(
        github: GitHubClient,
        repos: [Repository]
    ) async -> ActionsQueueStatus? {
        guard !repos.isEmpty else { return nil }

        var totalInProgress = 0
        var totalQueued = 0
        var allRuns: [ActiveWorkflowRun] = []
        let now = Date()

        let sample = Array(repos.prefix(5))
        for repo in sample {
            guard let status = try? await github.actionsQueueStatus(owner: repo.owner, name: repo.name) else {
                continue
            }

            totalInProgress += status.inProgressCount
            totalQueued += status.queuedCount
            allRuns.append(contentsOf: status.runs)
        }

        let isSampled = repos.count > sample.count
        guard totalInProgress > 0 || totalQueued > 0 || isSampled else { return nil }

        return ActionsQueueStatus(
            inProgressCount: totalInProgress,
            queuedCount: totalQueued,
            runs: allRuns,
            fetchedAt: now,
            scannedRepositoryCount: sample.count,
            totalRepositoryCount: repos.count
        )
    }
}
