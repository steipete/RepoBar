import AppKit

/// Sends a view-backed menu item's action when its custom view is clicked.
///
/// AppKit does not dispatch `target`/`action` for clicks on an `NSMenuItem` that has a custom `view`,
/// so rows that rely on the item's action forward their taps here. The menu is dismissed first,
/// matching how a standard menu item behaves when chosen.
@MainActor
final class MenuItemActivation {
    weak var item: NSMenuItem?

    func perform() {
        guard let item, item.isEnabled, let menu = item.menu else { return }

        let index = menu.index(of: item)
        guard index >= 0 else { return }

        menu.cancelTracking()
        menu.performActionForItem(at: index)
    }
}
