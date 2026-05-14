import Foundation
import RepoBarCore

actor LocalSyncNotifier {
    static let shared = LocalSyncNotifier()

    func notifySync(for status: LocalRepoStatus) async {
        await RepoBarNotifier.shared.notify(RepoBarNotification(
            identifier: UUID().uuidString,
            body: "Synced \(status.displayName) (\(status.branch))"
        ))
    }
}
