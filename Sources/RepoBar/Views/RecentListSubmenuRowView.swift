import SwiftUI

struct RecentListSubmenuRowView: View {
    let title: String
    let systemImage: String
    let badgePrefixText: String?
    let badgeText: String?
    let badgeAccessibilityLabel: String?
    let detailText: String?
    let onOpen: (() -> Void)?

    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        systemImage: String,
        badgePrefixText: String? = nil,
        badgeText: String? = nil,
        badgeAccessibilityLabel: String? = nil,
        detailText: String? = nil,
        onOpen: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgePrefixText = badgePrefixText
        self.badgeText = badgeText
        self.badgeAccessibilityLabel = badgeAccessibilityLabel
        self.detailText = detailText
        self.onOpen = onOpen
    }

    var body: some View {
        if let onOpen {
            self.row
                .contentShape(Rectangle())
                .onTapGesture { onOpen() }
        } else {
            self.row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: MenuStyle.submenuIconSpacing) {
            SubmenuIconColumnView {
                Image(systemName: self.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }

            Text(self.title)
                .font(.system(size: 14))
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let detailText, detailText.isEmpty == false {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }

            if self.hasBadge {
                HStack(spacing: 6) {
                    if let badgePrefixText, badgePrefixText.isEmpty == false {
                        Text(badgePrefixText)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let badgeText {
                        Text(badgeText)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .layoutPriority(1)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(self.badgeForeground)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(self.badgeBackground, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(self.badgeBorder, lineWidth: 1)
                }
                .padding(.trailing, 16)
                .accessibilityLabel(Text(self.computedBadgeAccessibilityLabel))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var hasBadge: Bool {
        if let badgePrefixText, badgePrefixText.isEmpty == false {
            return true
        }
        return self.badgeText != nil
    }

    private var computedBadgeAccessibilityLabel: String {
        if let badgeAccessibilityLabel {
            return badgeAccessibilityLabel
        }
        if let badgePrefixText, badgePrefixText.isEmpty == false, let badgeText {
            return "Badge \(badgePrefixText), \(badgeText)"
        }
        if let badgePrefixText, badgePrefixText.isEmpty == false {
            return "Badge \(badgePrefixText)"
        }
        if let badgeText {
            return "Count \(badgeText)"
        }
        return "Badge"
    }

    private var badgeBackground: Color {
        if self.isHighlighted {
            return Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.18)
        }
        if self.colorScheme == .dark {
            return Color.white.opacity(0.08)
        }
        return Color.black.opacity(0.12)
    }

    private var badgeBorder: Color {
        if self.isHighlighted {
            return Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.28)
        }
        if self.colorScheme == .dark {
            return Color.white.opacity(0.10)
        }
        return Color.black.opacity(0.18)
    }

    private var badgeForeground: Color {
        self.isHighlighted ? MenuHighlightStyle.selectionText : MenuHighlightStyle.primary(false)
    }
}
