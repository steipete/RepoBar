import AppKit
import RepoBarCore
import SwiftUI

struct WorkflowRunMenuItemView: View {
    let summary: RepoWorkflowRunSummary
    let onOpen: () -> Void
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        RecentItemRowView(alignment: .top, onOpen: self.onOpen) {
            Circle()
                .fill(self.statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.summary.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(2)

                if let workflowName = self.summary.workflowName, workflowName.isEmpty == false {
                    Text(workflowName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let branch = self.summary.branch, branch.isEmpty == false {
                        Text(branch)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }

                    if let event = self.summary.event, event.isEmpty == false {
                        Text(event)
                            .font(.caption)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }

                    if let actor = self.summary.actorLogin, actor.isEmpty == false {
                        Text(actor)
                            .font(.caption)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Text(RelativeFormatter.string(from: self.summary.updatedAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusColor: Color {
        MenuCIBadge.dotColor(for: self.summary.status, isLightAppearance: self.isLightAppearance, isHighlighted: self.isHighlighted)
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}
