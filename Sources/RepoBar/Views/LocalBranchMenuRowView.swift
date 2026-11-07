import SwiftUI

struct LocalBranchMenuRowView: View {
    let model: LocalRefMenuRowViewModel

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            self.headerRow
            self.metadataRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: MenuStyle.submenuIconSpacing) {
            Image(systemName: self.model.isCurrent ? "checkmark" : "circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(width: MenuStyle.submenuIconColumnWidth, alignment: .center)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + MenuStyle.submenuIconBaselineOffset
                }

            Text(self.model.title)
                .font(.system(size: 13, weight: self.model.isCurrent ? .semibold : .regular))
                .lineLimit(1)

            if self.model.isDetached {
                Text(AppLocalizer().string("Detached"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .separatorColor).opacity(0.4), in: Capsule(style: .continuous))
            }

            Spacer(minLength: 8)

            if let dirtySummary = self.model.dirtySummary, !dirtySummary.isEmpty {
                Text("\(AppLocalizer().string("Dirty")) \(dirtySummary)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
    }

    private var metadataRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: MenuStyle.submenuIconSpacing) {
            Text(" ")
                .font(.caption2)
                .frame(width: MenuStyle.submenuIconColumnWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let upstream = self.model.upstream {
                    Text("\(AppLocalizer().string("Tracking")) \(upstream)")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }

                if let commitLine = self.model.commitLine {
                    Text(commitLine)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            let syncLabel = self.model.syncLabel
            if syncLabel.isEmpty == false {
                Text(AppLocalizer().string(syncLabel))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
    }
}
