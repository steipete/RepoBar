import AppKit
import RepoBarCore
import SwiftUI

struct ContributionHeaderView: View {
    let username: String
    let displayName: String
    @Bindable var session: Session
    let appState: AppState
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.caption.weight(.semibold))
                Text("\(self.displayName) · Contributions · \(self.session.settings.heatmap.span.label)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: self.username) {
            await self.appState.loadContributionHeatmapIfNeeded(for: self.username)
        }
    }

    @ViewBuilder
    private var content: some View {
        let filtered = HeatmapFilter.filter(self.session.contributionHeatmap, range: self.session.heatmapRange)
        let hasHeatmap = self.hasCachedHeatmap
        let showProgress = self.session.contributionIsLoading && !hasHeatmap

        if hasHeatmap {
            VStack(spacing: 4) {
                HeatmapView(
                    cells: filtered,
                    accentTone: self.session.settings.appearance.accentTone,
                    height: Self.graphHeight
                )
                HeatmapAxisLabelsView(
                    range: self.session.heatmapRange,
                    foregroundStyle: MenuHighlightStyle.secondary(self.isHighlighted)
                )
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Contribution graph for \(self.username)")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
                if showProgress {
                    RepoBarLoadingGridView()
                        .frame(height: Self.graphHeight - 8)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.loadingHeight)
            .accessibilityLabel("Contribution graph loading")
        }
    }

    private var hasCachedHeatmap: Bool {
        self.session.contributionUser == self.username && !self.session.contributionHeatmap.isEmpty
    }

    private static let graphHeight: CGFloat = 48
    private static let loadingHeight: CGFloat = graphHeight
}
