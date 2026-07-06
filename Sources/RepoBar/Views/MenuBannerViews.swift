import AppKit
import RepoBarCore
import SwiftUI

struct MenuLoggedOutView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclam")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Sign in to see your repositories")
                .font(.headline)
            Text("Connect your GitHub account to load pins and activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

struct MenuEmptyStateView: View {
    let title: String
    let subtitle: String

    init(
        title: String = "No repositories yet",
        subtitle: String = "Pin a repository to see activity here."
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(self.title)
                .font(.headline)
            Text(self.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct RateLimitBanner: View {
    let reset: Date
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
            Text("Rate limit resets \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate limit reset: \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
    }
}

struct ErrorBanner: View {
    let message: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(self.message)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(self.message)")
    }
}

struct RateLimitStatusRowView: View {
    let summary: String
    let isLimited: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(self.isLimited ? .orange : MenuHighlightStyle.secondary(self.isHighlighted))

            VStack(alignment: .leading, spacing: 1) {
                Text("GitHub API Status")
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
        .accessibilityLabel("GitHub API Status, \(self.summary)")
    }
}

struct MenuInfoTextRowView: View {
    let text: String
    let lineLimit: Int
    private let iconColumnWidth: CGFloat = 18
    private let iconSpacing: CGFloat = 8

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: self.iconSpacing) {
            SubmenuIconPlaceholderView(font: .caption)

            Text(self.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(self.lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MenuStyle.cardHorizontalPadding)
        .padding(.vertical, MenuStyle.cardVerticalPadding)
    }
}

struct RateLimitSectionHeaderView: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(self.title.uppercased())
                .font(.caption2.weight(.semibold))

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RateLimitMenuMetrics.horizontalPadding)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }
}

struct RateLimitResourceRowView: View {
    let row: RateLimitDisplayRow
    let showsReset: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if self.row.resource != nil || self.row.quotaText != nil {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(self.row.resource ?? self.row.text)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    if let quota = self.row.quotaText {
                        Text(quota)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }
                }

                if let percent = self.row.percentRemaining {
                    RateLimitProgressBar(
                        percent: percent,
                        tint: Self.tint(for: percent),
                        accessibilityLabel: self.row.resource ?? "GitHub rate limit"
                    )
                }

                if self.showsReset, let reset = self.row.resetText {
                    Text(reset)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }

                if let detail = self.nonSampledDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(self.row.text)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RateLimitMenuMetrics.horizontalPadding)
        .padding(.vertical, 4)
    }

    private var nonSampledDetail: String? {
        guard let detail = self.row.detailText,
              detail.isEmpty == false,
              detail.hasPrefix("sampled ") == false
        else { return nil }

        if let reset = self.row.resetText {
            let repeatedSuffix = " · \(reset)"
            if detail.hasSuffix(repeatedSuffix) {
                return String(detail.dropLast(repeatedSuffix.count))
            }
        }
        return detail
    }

    private static func tint(for percent: Double) -> Color {
        if percent <= 10 {
            return Color(nsColor: .systemRed)
        }
        if percent <= 30 {
            return Color(nsColor: .systemOrange)
        }
        return Color(nsColor: .systemGreen)
    }
}

struct RateLimitUpdatedRowView: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RateLimitMenuMetrics.horizontalPadding)
            .padding(.vertical, 5)
    }
}

private enum RateLimitMenuMetrics {
    static let horizontalPadding: CGFloat = 28
}

struct RateLimitProgressBar: View {
    let percent: Double
    let tint: Color
    let accessibilityLabel: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * self.clamped / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                Capsule()
                    .fill(MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint))
                    .frame(width: fillWidth)
            }
            .clipped()
        }
        .frame(height: 6)
        .accessibilityLabel(self.accessibilityLabel)
        .accessibilityValue("\(Int(self.clamped)) percent remaining")
    }
}

struct MenuLoadingRowView: View {
    let text: String

    init(text: String = "Loading repositories…") {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 12) {
            RepoBarLoadingGridView()
                .frame(height: 44)
            Text(self.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.text)
    }
}
