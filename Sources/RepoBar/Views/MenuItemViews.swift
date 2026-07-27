import AppKit
import Kingfisher
import RepoBarCore
import SwiftUI

struct RepoMenuCardView: View {
    let repo: RepositoryDisplayModel
    let isPinned: Bool
    let showHeatmap: Bool
    let heatmapRange: HeatmapRange
    let accentTone: AccentTone
    let showDirtyFiles: Bool
    let onOpen: (() -> Void)?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: self.verticalSpacing) {
            self.header
            self.stats
            self.localStatusRow
            self.localDirtyFiles
            self.activity
            self.errorOrLimit
            self.heatmap
        }
        .padding(.horizontal, MenuStyle.cardHorizontalPadding)
        .padding(.vertical, MenuStyle.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            self.onOpen?()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(MenuCIBadge.dotColor(
                        for: self.repo.ciStatus,
                        isLightAppearance: self.isLightAppearance,
                        isHighlighted: self.isHighlighted
                    ))
                    .frame(width: 6, height: 6)
                Text(self.repo.title)
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .lineLimit(1)
                if self.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
            Spacer(minLength: 6)
            if let releaseLine = repo.releaseLine {
                Text(releaseLine)
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            ForEach(self.repo.stats) { stat in
                MenuStatBadge(label: stat.label, value: stat.value, systemImage: stat.systemImage)
            }
        }
    }

    @ViewBuilder
    private var localStatusRow: some View {
        if let local = self.repo.localStatus {
            HStack(spacing: 6) {
                Image(systemName: local.syncState.symbolName)
                    .font(.caption2)
                    .foregroundStyle(self.localSyncColor(for: local.syncState))
                Text(local.branch)
                    .font(.caption2)
                    .lineLimit(1)
                Text(local.syncDetail)
                    .font(.caption2)
            }
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    @ViewBuilder
    private var localDirtyFiles: some View {
        let dirtyFiles = self.repo.localStatus?.dirtyFiles ?? []
        if self.showDirtyFiles, dirtyFiles.isEmpty == false {
            let files = dirtyFiles.prefix(AppLimits.LocalRepo.mainMenuDirtyFileLimit)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(files), id: \.self) { file in
                    Text("- \(file)")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let activity = repo.activityLine {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(activity, systemImage: "text.bubble")
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let age = self.repo.latestActivityAge {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    @ViewBuilder
    private var errorOrLimit: some View {
        if let error = repo.error {
            if RepositoryErrorClassifier.isNonCriticalMenuWarning(error) == false {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(self.warningColor)
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                }
            }
        } else if let limit = repo.rateLimitedUntil {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(self.warningColor)
                Text("Rate limited until \(RelativeFormatter.string(from: limit, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
        }
    }

    @ViewBuilder
    private var heatmap: some View {
        if self.showHeatmap, !self.repo.heatmap.isEmpty {
            let filtered = HeatmapFilter.filter(self.repo.heatmap, range: self.heatmapRange)
            HeatmapView(cells: filtered, accentTone: self.accentTone, height: MenuStyle.heatmapInlineHeight)
                .padding(.trailing, -MenuStyle.menuItemContainerTrailingPadding)
                .padding(.bottom, -MenuStyle.heatmapInlineBottomTrim)
                .frame(maxWidth: .infinity)
        }
    }

    private var verticalSpacing: CGFloat {
        MenuStyle.cardSpacing
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    private var warningColor: Color {
        self.isLightAppearance ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
    }

    private func localSyncColor(for state: LocalSyncState) -> Color {
        if self.isHighlighted {
            return MenuHighlightStyle.selectionText
        }
        switch state {
        case .synced:
            return self.isLightAppearance
                ? Color(nsColor: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1))
                : Color(nsColor: NSColor(srgbRed: 0.23, green: 0.8, blue: 0.4, alpha: 1))
        case .behind:
            return self.isLightAppearance ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
        case .ahead:
            return self.isLightAppearance ? Color(nsColor: .systemBlue) : Color(nsColor: .systemTeal)
        case .diverged:
            return self.isLightAppearance ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
        case .dirty:
            return Color(nsColor: .systemRed)
        case .unknown:
            return MenuHighlightStyle.secondary(self.isHighlighted)
        }
    }
}

struct RepoCardSeparatorRowView: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.leading, MenuStyle.cardSeparatorInset)
            .padding(.vertical, MenuStyle.cardSeparatorVerticalPadding)
    }
}

struct MenuStatBadge: View {
    let label: String?
    let valueText: String
    let systemImage: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    private static let iconWidth: CGFloat = 12

    init(label: String?, value: Int, systemImage: String? = nil) {
        self.label = label
        self.valueText = StatValueFormatter.compact(value)
        self.systemImage = systemImage
    }

    init(label: String?, valueText: String, systemImage: String? = nil) {
        self.label = label
        self.valueText = valueText
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .frame(width: Self.iconWidth, alignment: .center)
            }
            if let label {
                Text(label)
                    .font(.caption2)
            }
            Text(self.valueText)
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}

struct MenuPaddedSeparatorView: View {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 6) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.horizontal, self.horizontalPadding)
            .padding(.vertical, self.verticalPadding)
    }
}

struct ActivityMenuItemView: View {
    let event: ActivityEvent
    let symbolName: String
    let onOpen: () -> Void
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbolName)
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            self.avatar
            Text(self.labelText)
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(2)
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { self.onOpen() }
    }

    private var labelText: String {
        let when = RelativeFormatter.string(from: self.event.date, relativeTo: Date())
        return "\(when) • \(self.event.actor): \(self.event.title)"
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = self.event.actorAvatarURL {
            KFImage(url)
                .placeholder { self.avatarPlaceholder }
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(Circle())
        } else {
            self.avatarPlaceholder
                .frame(width: 16, height: 16)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(nsColor: .separatorColor))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            )
    }
}

struct MenuCIBadge: View {
    let status: CIStatus
    let runCount: Int?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(self.color)
                .frame(width: 6, height: 6)
            if let runCount {
                Text("\(runCount)")
                    .font(.caption2).bold()
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
    }

    private var color: Color {
        Self.dotColor(for: self.status, isLightAppearance: self.isLightAppearance, isHighlighted: self.isHighlighted)
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    static func dotColor(for status: CIStatus, isLightAppearance: Bool, isHighlighted: Bool) -> Color {
        let base: NSColor = switch status {
        case .passing:
            if isLightAppearance {
                NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1)
            } else {
                NSColor(srgbRed: 0.23, green: 0.8, blue: 0.4, alpha: 1)
            }
        case .failing:
            .systemRed
        case .pending:
            if isLightAppearance {
                NSColor(srgbRed: 0.0, green: 0.45, blue: 0.9, alpha: 1)
            } else {
                NSColor(srgbRed: 0.2, green: 0.65, blue: 1.0, alpha: 1)
            }
        case .unknown:
            .tertiaryLabelColor
        }
        let alpha: CGFloat = isHighlighted ? 1.0 : (isLightAppearance ? 0.8 : 0.9)
        var adjusted = base.withAlphaComponent(alpha)
        if isHighlighted {
            adjusted = adjusted.ensuringContrast(
                on: .selectedContentBackgroundColor,
                minRatio: 3.0,
                appearance: NSApp.effectiveAppearance
            )
        }
        return Color(nsColor: adjusted)
    }
}
