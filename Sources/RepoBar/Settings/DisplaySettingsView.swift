import RepoBarCore
import SwiftUI

struct DisplaySettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Customize the menu layout and repo submenu items.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { self.resetToDefaults() } label: {
                    Text("Reset to Defaults")
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 16) {
                self.mainMenuList()
                self.repoSubmenuList()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear { self.normalizeCustomization() }
    }

    private var mainMenuItems: [MainMenuItemID] {
        self.session.settings.menuCustomization.mainMenuOrder
    }

    private var repoSubmenuItems: [RepoSubmenuItemID] {
        self.session.settings.menuCustomization.repoSubmenuOrder
    }

    private func mainMenuList() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Main Menu")
                .font(.headline)
            List {
                ForEach(self.mainMenuItems, id: \.self) { item in
                    self.menuRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        isRequired: item.isRequired,
                        isVisible: self.mainMenuVisibility(for: item)
                    )
                }
                .onMove(perform: self.moveMainMenuItems)
            }
            .frame(minWidth: 230, maxWidth: .infinity, minHeight: 360)
        }
    }

    private func repoSubmenuList() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repo Submenu")
                .font(.headline)
            List {
                ForEach(self.repoSubmenuItems, id: \.self) { item in
                    self.menuRow(
                        title: item.title,
                        subtitle: item.subtitle,
                        isRequired: false,
                        isVisible: self.repoSubmenuVisibility(for: item)
                    )
                }
                .onMove(perform: self.moveRepoSubmenuItems)
            }
            .frame(minWidth: 230, maxWidth: .infinity, minHeight: 360)
        }
    }

    private func menuRow(
        title: String,
        subtitle: String?,
        isRequired: Bool,
        isVisible: Binding<Bool>
    ) -> some View {
        let effectiveSubtitle: String? = {
            if isRequired {
                if let subtitle, subtitle.isEmpty == false {
                    return "Required · \(subtitle)"
                }
                return "Required"
            }
            return subtitle
        }()

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isVisible.wrappedValue ? .primary : .secondary)
                Text(effectiveSubtitle ?? " ")
                    .font(.caption)
                    .foregroundStyle(effectiveSubtitle == nil ? .clear : .secondary)
            }
            Spacer()
            Toggle("Visible", isOn: isVisible)
                .labelsHidden()
                .disabled(isRequired)
        }
        .padding(.vertical, 3)
    }

    private func moveMainMenuItems(from offsets: IndexSet, to destination: Int) {
        var customization = self.session.settings.menuCustomization
        customization.mainMenuOrder.move(fromOffsets: offsets, toOffset: destination)
        self.updateCustomization(customization)
    }

    private func moveRepoSubmenuItems(from offsets: IndexSet, to destination: Int) {
        var customization = self.session.settings.menuCustomization
        customization.repoSubmenuOrder.move(fromOffsets: offsets, toOffset: destination)
        self.updateCustomization(customization)
    }

    private func mainMenuVisibility(for item: MainMenuItemID) -> Binding<Bool> {
        Binding(
            get: {
                if item.isRequired {
                    return true
                }
                return !self.session.settings.menuCustomization.hiddenMainMenuItems.contains(item)
            },
            set: { isVisible in
                guard item.isRequired == false else { return }

                var customization = self.session.settings.menuCustomization
                if isVisible {
                    customization.hiddenMainMenuItems.remove(item)
                } else {
                    customization.hiddenMainMenuItems.insert(item)
                }
                self.updateCustomization(customization)
            }
        )
    }

    private func repoSubmenuVisibility(for item: RepoSubmenuItemID) -> Binding<Bool> {
        Binding(
            get: {
                !self.session.settings.menuCustomization.hiddenRepoSubmenuItems.contains(item)
            },
            set: { isVisible in
                var customization = self.session.settings.menuCustomization
                if isVisible {
                    customization.hiddenRepoSubmenuItems.remove(item)
                } else {
                    customization.hiddenRepoSubmenuItems.insert(item)
                }
                self.updateCustomization(customization)
            }
        )
    }

    private func updateCustomization(_ customization: MenuCustomization) {
        self.session.settings.menuCustomization = customization
        self.session.settings.actions.showActionsInMenu = !customization.hiddenMainMenuItems.contains(.actionsLimits)
        if customization.hiddenMainMenuItems.contains(.actionsLimits) {
            self.session.actionsOrgSnapshots = []
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
        }
        self.appState.persistSettings()
        self.appState.requestRefresh()
    }

    private func resetToDefaults() {
        self.updateCustomization(MenuCustomization())
    }

    private func normalizeCustomization() {
        var customization = self.session.settings.menuCustomization
        customization.normalize()
        if customization != self.session.settings.menuCustomization {
            self.updateCustomization(customization)
        }
    }
}
