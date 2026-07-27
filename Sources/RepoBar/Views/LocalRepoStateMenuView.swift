import AppKit
import RepoBarCore
import SwiftUI

struct LocalRepoStateMenuView: View {
    let status: LocalRepoStatus
    let onSync: () -> Void
    let onRebase: () -> Void
    let onReset: () -> Void

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalRepoHeaderRow(status: self.status, isHighlighted: self.isHighlighted)
            if self.detailsLine.isEmpty == false {
                LocalRepoDetailsRow(text: self.detailsLine, isHighlighted: self.isHighlighted)
            }
            if self.status.dirtyFiles.isEmpty == false {
                LocalRepoDirtyFilesView(files: self.visibleDirtyFiles, isHighlighted: self.isHighlighted)
            }
            LocalRepoActionButtonsRow(
                syncEnabled: self.syncEnabled,
                rebaseEnabled: self.rebaseEnabled,
                resetEnabled: self.resetEnabled,
                isHighlighted: self.isHighlighted,
                onSync: self.onSync,
                onRebase: self.onRebase,
                onReset: self.onReset
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var detailsLine: String {
        var parts: [String] = []
        if let upstream = self.status.upstreamBranch {
            parts.append("Upstream \(upstream)")
        }
        if let dirty = self.status.dirtyCounts, dirty.isEmpty == false {
            parts.append("Dirty \(dirty.summary)")
        }
        if let fetch = self.status.lastFetchAt {
            let age = RelativeFormatter.string(from: fetch, relativeTo: Date())
            parts.append("Fetched \(age)")
        }
        return parts.joined(separator: " · ")
    }

    private var visibleDirtyFiles: [String] {
        Array(self.status.dirtyFiles.prefix(AppLimits.LocalRepo.submenuDirtyFileLimit))
    }

    private var syncEnabled: Bool {
        self.status.upstreamBranch != nil && self.status.isClean
    }

    private var rebaseEnabled: Bool {
        self.status.upstreamBranch != nil && self.status.isClean
    }

    private var resetEnabled: Bool {
        self.status.upstreamBranch != nil
    }
}

private struct LocalRepoHeaderRow: View {
    let status: LocalRepoStatus
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MenuStyle.submenuIconSpacing) {
            SubmenuIconColumnView {
                Image(systemName: self.status.syncState.symbolName)
                    .font(.caption2)
                    .foregroundStyle(self.syncColor)
            }
            Text(self.status.branch)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(self.status.syncDetail)
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            if let worktreeName = self.status.worktreeName {
                Text("Worktree \(worktreeName)")
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            Spacer(minLength: 8)
        }
    }

    private var syncColor: Color {
        if self.isHighlighted {
            return MenuHighlightStyle.selectionText
        }
        let isLightAppearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        switch self.status.syncState {
        case .synced:
            return isLightAppearance
                ? Color(nsColor: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1))
                : Color(nsColor: NSColor(srgbRed: 0.23, green: 0.8, blue: 0.4, alpha: 1))
        case .behind:
            return isLightAppearance ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
        case .ahead:
            return isLightAppearance ? Color(nsColor: .systemBlue) : Color(nsColor: .systemTeal)
        case .diverged:
            return isLightAppearance ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
        case .dirty:
            return Color(nsColor: .systemRed)
        case .unknown:
            return MenuHighlightStyle.secondary(self.isHighlighted)
        }
    }
}

private struct LocalRepoDetailsRow: View {
    let text: String
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MenuStyle.submenuIconSpacing) {
            SubmenuIconPlaceholderView(font: .caption2)

            Text(self.text)
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))

            Spacer(minLength: 0)
        }
    }
}

private struct LocalRepoDirtyFilesView: View {
    let files: [String]
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: MenuStyle.submenuIconSpacing) {
            SubmenuIconPlaceholderView(font: .caption2)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(self.files, id: \.self) { file in
                    Text("- \(file)")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct LocalRepoActionButtonsRow: View {
    let syncEnabled: Bool
    let rebaseEnabled: Bool
    let resetEnabled: Bool
    let isHighlighted: Bool
    let onSync: () -> Void
    let onRebase: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            self.actionButton(
                title: "Sync",
                systemImage: "arrow.triangle.2.circlepath",
                enabled: self.syncEnabled,
                isDestructive: false,
                action: self.onSync
            )
            self.actionButton(
                title: "Rebase",
                systemImage: "arrow.triangle.branch",
                enabled: self.rebaseEnabled,
                isDestructive: false,
                action: self.onRebase
            )
            self.actionButton(
                title: "Reset",
                systemImage: "arrow.counterclockwise",
                enabled: self.resetEnabled,
                isDestructive: true,
                action: self.onReset
            )
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        enabled: Bool,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        LocalRepoActionButton(
            title: title,
            systemImage: systemImage,
            enabled: enabled,
            isDestructive: isDestructive,
            isHighlighted: self.isHighlighted,
            action: action
        )
    }
}

private struct LocalRepoActionButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let isDestructive: Bool
    let isHighlighted: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            Label(self.title, systemImage: self.systemImage)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(self.enabled ? MenuHighlightStyle.primary(self.isHighlighted) : .secondary)
        .background(self.hoverBackground, in: Capsule(style: .continuous))
        .opacity(self.enabled ? 1 : 0.5)
        .disabled(!self.enabled)
        .onHover { self.isHovered = $0 }
    }

    private var hoverBackground: Color {
        guard self.isHovered else { return .clear }

        if self.isHighlighted {
            return MenuHighlightStyle.selectionText.opacity(0.18)
        }
        return Color(nsColor: .controlAccentColor).opacity(0.12)
    }
}
