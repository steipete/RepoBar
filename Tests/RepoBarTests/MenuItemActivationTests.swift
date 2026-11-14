import AppKit
@testable import RepoBar
import SwiftUI
import Testing

struct MenuItemActivationTests {
    @MainActor
    @Test
    func `activation sends the menu item action with the item as sender`() {
        let recorder = MenuActionRecorder()
        let menu = NSMenu()
        menu.addItem(withTitle: "Other", action: nil, keyEquivalent: "")
        let item = Self.makeItem(recorder: recorder)
        menu.addItem(item)
        let activation = MenuItemActivation()
        activation.item = item

        activation.perform()

        #expect(recorder.senders.count == 1)
        #expect(recorder.senders.first === item)
    }

    @MainActor
    @Test
    func `activation ignores disabled items`() {
        let recorder = MenuActionRecorder()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = Self.makeItem(recorder: recorder)
        item.isEnabled = false
        menu.addItem(item)
        let activation = MenuItemActivation()
        activation.item = item

        activation.perform()

        #expect(recorder.senders.isEmpty)
    }

    @MainActor
    @Test
    func `activation ignores items that are no longer in a menu`() {
        let recorder = MenuActionRecorder()
        let menu = NSMenu()
        let item = Self.makeItem(recorder: recorder)
        menu.addItem(item)
        menu.removeItem(item)
        let activation = MenuItemActivation()
        activation.item = item

        activation.perform()

        #expect(recorder.senders.isEmpty)
    }

    @MainActor
    private static func makeItem(recorder: MenuActionRecorder) -> NSMenuItem {
        let item = MenuItemViewFactory().makeItem(for: EmptyRow(), enabled: true, highlightable: true)
        item.target = recorder
        item.action = #selector(MenuActionRecorder.record(_:))
        return item
    }
}

@MainActor
private final class MenuActionRecorder: NSObject {
    private(set) var senders: [NSMenuItem] = []

    @objc func record(_ sender: NSMenuItem) {
        self.senders.append(sender)
    }
}

private struct EmptyRow: View {
    var body: some View {
        Text("Row")
    }
}
