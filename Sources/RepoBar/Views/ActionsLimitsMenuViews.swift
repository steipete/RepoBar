import AppKit
import RepoBarCore
import SwiftUI

// MARK: - Main menu row (compact summary with submenu)

struct ActionsLimitsStatusRowView: View {
    let summary: String
    let hasRunners: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(self.hasRunners ? Color(nsColor: .systemGreen) : MenuHighlightStyle.secondary(self.isHighlighted))

            VStack(alignment: .leading, spacing: 1) {
                Text("Actions & Runners")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                Text(self.summary)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Actions and Runners, \(self.summary)")
    }
}

// MARK: - Org header row

struct ActionsOrgHeaderView: View {
    let org: String
    let isOrg: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: self.isOrg ? "building.2" : "person.fill")
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            Text(self.org)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ActionsMenuMetrics.horizontalPadding)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }
}

// MARK: - Runner status row (submenu item)

struct ActionsRunnerRowView: View {
    let runner: RunnerSummary
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(self.statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.runner.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(self.runner.os)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    if self.runner.busy {
                        Text("busy")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !self.runner.labels.isEmpty {
                        Text(self.runner.labels.prefix(3).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ActionsMenuMetrics.horizontalPadding)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch self.runner.status {
        case "online":
            self.runner.busy ? .orange : Color(nsColor: .systemGreen)
        default:
            Color(nsColor: .systemRed)
        }
    }
}

// MARK: - Queue status row

struct ActionsQueueRowView: View {
    let queueStatus: ActionsQueueStatus
    let planTier: GitHubPlanTier
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Concurrent Jobs")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(self.remainingConcurrentJobs) / \(self.planTier.concurrentJobs) remaining")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            RateLimitProgressBar(
                percent: self.remainingPercent,
                tint: Self.tint(for: self.remainingPercent),
                accessibilityLabel: "Concurrent job usage"
            )

            HStack(spacing: 10) {
                Text("\(self.queueStatus.inProgressCount) running")
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                if self.queueStatus.queuedCount > 0 {
                    Text("\(self.queueStatus.queuedCount) queued")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }

            if let repositorySampleDescription = self.queueStatus.repositorySampleDescription {
                Text(repositorySampleDescription)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ActionsMenuMetrics.horizontalPadding)
        .padding(.vertical, 4)
    }

    private var remainingPercent: Double {
        self.queueStatus.remainingConcurrentPercent(limit: self.planTier.concurrentJobs)
    }

    private var remainingConcurrentJobs: Int {
        self.queueStatus.remainingConcurrentJobs(limit: self.planTier.concurrentJobs)
    }

    private static func tint(for remainingPercent: Double) -> Color {
        if remainingPercent <= 10 {
            return Color(nsColor: .systemRed)
        }
        if remainingPercent <= 30 {
            return Color(nsColor: .systemOrange)
        }
        return Color(nsColor: .systemGreen)
    }
}

// MARK: - Runner fleet overview row

struct ActionsRunnerFleetRowView: View {
    let runners: ActionsRunnerInfo
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Runners")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(self.runners.totalCount) total")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                self.badge(count: self.runners.onlineCount, label: "online", color: Color(nsColor: .systemGreen))
                self.badge(count: self.runners.busyCount, label: "busy", color: .orange)
                self.badge(count: self.runners.offlineCount, label: "offline", color: Color(nsColor: .systemRed))
                Spacer(minLength: 0)
            }

            if let repositorySampleDescription = self.runners.repositorySampleDescription {
                Text(repositorySampleDescription)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ActionsMenuMetrics.horizontalPadding)
        .padding(.vertical, 4)
    }

    private func badge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }
}

// MARK: - Section header (reuses pattern from rate limit views)

struct ActionsSectionHeaderView: View {
    let title: String

    var body: some View {
        HStack {
            Text(self.title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ActionsMenuMetrics.horizontalPadding)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }
}

// MARK: - Cache usage row

struct ActionsCacheUsageRowView: View {
    let cacheUsage: ActionsCacheUsage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text("Cache")
                .font(.callout)
            Spacer()
            Text(Self.formatted(self.cacheUsage))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private static func formatted(_ usage: ActionsCacheUsage) -> String {
        let count = usage.totalCachesCount
        if usage.cacheSizeGB >= 1.0 {
            return String(format: "%d caches · %.1f GB", count, usage.cacheSizeGB)
        }
        return String(format: "%d caches · %.0f MB", count, usage.cacheSizeMB)
    }
}

// MARK: - Artifact retention row

struct ArtifactRetentionRowView: View {
    let retention: ArtifactRetentionPolicy

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text("Artifact retention")
                .font(.callout)
            Spacer()
            Text("\(self.retention.retentionDays) days")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

// MARK: - Billing minutes row

struct ActionsMinutesRowView: View {
    let minutesUsed: Int
    let minutesIncluded: Int
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Minutes Used")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(self.minutesUsed) / \(self.minutesIncluded)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            RateLimitProgressBar(
                percent: self.remainingPercent,
                tint: Self.tint(for: self.remainingPercent),
                accessibilityLabel: "Actions minutes usage"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ActionsMenuMetrics.horizontalPadding)
        .padding(.vertical, 4)
    }

    private var remainingPercent: Double {
        guard self.minutesIncluded > 0 else { return 100 }

        let pct = (1.0 - Double(self.minutesUsed) / Double(self.minutesIncluded)) * 100
        return min(100, max(0, pct))
    }

    private static func tint(for remainingPercent: Double) -> Color {
        if remainingPercent <= 10 {
            return Color(nsColor: .systemRed)
        }
        if remainingPercent <= 30 {
            return Color(nsColor: .systemOrange)
        }
        return Color(nsColor: .systemGreen)
    }
}

private enum ActionsMenuMetrics {
    static let horizontalPadding: CGFloat = 28
}
