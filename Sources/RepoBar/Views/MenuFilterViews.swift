import AppKit
import RepoBarCore
import SwiftUI

struct MenuRepoFiltersView: View {
    @Bindable var session: Session

    private var availableFilters: [MenuRepoSelection] {
        if self.session.account.isLoggedIn {
            return MenuRepoSelection.allCases
        }
        // Only local filter when logged out (All/Pinned/Work require GitHub)
        return [.local]
    }

    private var filterSelection: Binding<MenuRepoSelection> {
        Binding(
            get: {
                if self.session.account.isLoggedIn {
                    return self.session.menuRepoSelection
                }
                return .local
            },
            set: { newValue in
                if self.session.account.isLoggedIn {
                    self.session.menuRepoSelection = newValue
                } else {
                    self.session.menuRepoSelection = .local
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(self.availableFilters.enumerated()), id: \.element) { index, selection in
                    MenuFilterBarButton(
                        isSelected: self.filterSelection.wrappedValue == selection,
                        fixedWidth: selection.menuBarWidth
                    ) {
                        self.filterSelection.wrappedValue = selection
                    } label: {
                        Text(selection.label)
                            .fontWeight(self.filterSelection.wrappedValue == selection ? .semibold : .medium)
                    }
                    .accessibilityLabel(selection.label)

                    if index < self.availableFilters.count - 1 {
                        MenuFilterBarDivider()
                    }
                }
            }
            .padding(2)
            .background(MenuFilterBarBackground())
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)

            MenuFilterBarButton(isSelected: true, fixedWidth: 42) {
                self.cycleSortKey()
            } label: {
                Image(systemName: self.session.settings.repoList.menuSortKey.menuSymbolName)
                    .font(.system(size: 15, weight: .medium))
            }
            .accessibilityLabel("Sort by \(self.session.settings.repoList.menuSortKey.menuLabel)")
            .help("Sort by \(self.session.settings.repoList.menuSortKey.menuLabel). Click to cycle.")
            .padding(2)
            .background(MenuFilterBarBackground())
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.subheadline)
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, MenuStyle.filterVerticalPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.menuRepoSelection) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
    }

    private func cycleSortKey() {
        let cases = RepositorySortKey.menuCases
        guard let index = cases.firstIndex(of: self.session.settings.repoList.menuSortKey) else {
            self.session.settings.repoList.menuSortKey = cases[0]
            return
        }

        self.session.settings.repoList.menuSortKey = cases[(index + 1) % cases.count]
    }
}

private struct MenuFilterBarButton<Label: View>: View {
    let isSelected: Bool
    var fixedWidth: CGFloat?
    let action: () -> Void
    private let label: Label

    init(
        isSelected: Bool,
        fixedWidth: CGFloat? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.isSelected = isSelected
        self.fixedWidth = fixedWidth
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: self.action) {
            self.label
                .foregroundStyle(self.isSelected ? Color.primary : Color.secondary)
                .frame(width: self.fixedWidth, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if self.isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.16))
            }
        }
    }
}

private struct MenuFilterBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.45))
            .frame(width: 1, height: 14)
    }
}

private struct MenuFilterBarBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            }
    }
}

private extension MenuRepoSelection {
    var menuBarWidth: CGFloat {
        switch self {
        case .all: 42
        case .pinned: 66
        case .local: 56
        case .work: 56
        }
    }
}

struct RecentPullRequestFiltersView: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 6) {
            Picker("Scope", selection: self.$session.recentPullRequestScope) {
                ForEach(RecentPullRequestScope.allCases, id: \.self) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .labelsHidden()
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: 2)

            Picker("Engagement", selection: self.$session.recentPullRequestEngagement) {
                ForEach(RecentPullRequestEngagement.allCases, id: \.self) { engagement in
                    Label(engagement.label, systemImage: engagement.systemImage)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(engagement.label)
                        .tag(engagement)
                }
            }
            .labelsHidden()
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, MenuStyle.filterHorizontalPadding)
        .padding(.vertical, MenuStyle.filterVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.recentPullRequestScope) { _, _ in
            NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.recentPullRequestEngagement) { _, _ in
            NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
        }
    }
}
