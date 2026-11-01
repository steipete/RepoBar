import AppKit
import SwiftUI

struct RecentIssueFiltersView: View {
    @Bindable var session: Session
    let labels: [RecentIssueLabelOption]

    var body: some View {
        HStack(spacing: 8) {
            Picker("Scope", selection: self.$session.recentIssueScope) {
                ForEach(RecentIssueScope.allCases, id: \.self) { scope in
                    Text(AppLocalizer().string(scope.label)).tag(scope)
                }
            }
            .labelsHidden()
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                IssueLabelFilterChipsView(
                    selection: self.$session.recentIssueLabelSelection,
                    labels: self.labels
                )
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, MenuStyle.filterVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.recentIssueScope) { _, _ in
            NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.recentIssueLabelSelection) { _, _ in
            NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
        }
    }
}

private struct IssueLabelFilterChipsView: View {
    @Binding var selection: Set<String>
    let labels: [RecentIssueLabelOption]

    var body: some View {
        HStack(spacing: 6) {
            IssueLabelFilterChip(
                title: AppLocalizer().string("All"),
                colorHex: nil,
                isSelected: self.selection.isEmpty
            ) {
                self.selection.removeAll()
            }

            ForEach(self.labels, id: \.self) { label in
                IssueLabelFilterChip(
                    title: label.name,
                    colorHex: label.colorHex,
                    isSelected: self.selection.contains(label.name)
                ) {
                    self.toggle(label.name)
                }
            }
        }
    }

    private func toggle(_ name: String) {
        if self.selection.contains(name) {
            self.selection.remove(name)
        } else {
            self.selection.insert(name)
        }
    }
}

private struct IssueLabelFilterChip: View {
    let title: String
    let colorHex: String?
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = MenuLabelFilterColor.nsColor(from: self.colorHex) ?? .separatorColor
        let baseColor = Color(nsColor: base)
        let usesColor = self.colorHex?.isEmpty == false

        let fillOpacity: CGFloat = self.colorScheme == .dark ? 0.16 : 0.14
        let strokeOpacity: CGFloat = self.colorScheme == .dark ? 0.50 : 0.70
        let fill = self.isSelected ? baseColor.opacity(0.28) : baseColor.opacity(fillOpacity)
        let stroke = self.isSelected ? baseColor.opacity(0.90) : baseColor.opacity(strokeOpacity)
        let text = Color(nsColor: .labelColor)

        Button(action: self.onTap) {
            HStack(spacing: 5) {
                if usesColor {
                    Circle()
                        .fill(baseColor)
                        .frame(width: 6, height: 6)
                }
                Text(self.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(self.title))
    }
}

private enum MenuLabelFilterColor {
    static func nsColor(from hex: String?) -> NSColor? {
        guard let hex, hex.isEmpty == false else { return nil }

        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}
