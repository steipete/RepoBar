import Foundation
@testable import RepoBar
import Testing

struct ChangelogMenuCoordinatorTests {
    @MainActor
    @Test
    func `removed account changelog request cannot repopulate cache after readd`() async {
        let gate = ChangelogResponseGate()
        let appState = AppState()
        let manager = StatusBarMenuManager(appState: appState)
        let builder = StatusBarMenuBuilder(appState: appState, target: manager)
        let coordinator = ChangelogMenuCoordinator(
            appState: appState,
            menuBuilder: builder,
            menuItemFactory: MenuItemViewFactory(),
            fetchOverride: { _, _, _ in
                await gate.fetch()
            }
        )

        let first = Task { @MainActor in
            await coordinator.loadChangelogForTesting(accountID: "alice", fullName: "owner/repo")
        }
        await gate.waitUntilFirstRequestStarts()
        coordinator.removeCachedState(accountID: "alice")
        await gate.releaseFirstRequest()

        #expect(await first.value == false)
        #expect(coordinator.hasCachedStateForTesting(accountID: "alice", fullName: "owner/repo") == false)

        #expect(await coordinator.loadChangelogForTesting(accountID: "alice", fullName: "owner/repo"))
        #expect(coordinator.hasCachedStateForTesting(accountID: "alice", fullName: "owner/repo"))
    }
}

private actor ChangelogResponseGate {
    private var requestCount = 0
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func fetch() async -> ChangelogFetchResult {
        self.requestCount += 1
        if self.requestCount == 1 {
            let waiters = self.startWaiters
            self.startWaiters = []
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                self.firstRequestContinuation = continuation
            }
        }
        return ChangelogFetchResult(result: .missing, parsed: nil)
    }

    func waitUntilFirstRequestStarts() async {
        guard self.requestCount == 0 else { return }

        await withCheckedContinuation { continuation in
            self.startWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() {
        self.firstRequestContinuation?.resume()
        self.firstRequestContinuation = nil
    }
}
