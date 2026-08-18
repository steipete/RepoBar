---
summary: "Design plan for moving RepoBar from one signed-in GitHub identity to multi-account auth, storage, UI, cache, and CLI support."
read_when:
  - Planning multi-account support
  - Modifying auth/token storage
  - Modifying AccountSettingsView or app session state
  - Modifying CLI auth commands
---

# Multi-Account Authentication Plan

RepoBar's current authentication code is intentionally small and clean, but it is wired around a single signed-in account. This document maps the current single-account surface and proposes a staged path to multi-account support.

## Implementation Status

The 0.6.6 cycle landed the bulk of the plan end-to-end behind a backward-compatible facade. The legacy single-account `TokenStore` keys (`default`, `client`, `pat`) and the `githubHost` / `enterpriseHost` / `loopbackPort` / `authMethod` `UserSettings` fields are still authoritative for installs that have not been re-auth'd; the new account-scoped keys, settings, caches, and clients are populated on first login (or via the legacy migration on bootstrap) without removing those legacy entries.

### Issue #101 consolidated experience

The next programme adds an optional consolidated experience on top of the existing multi-account foundations. Its accepted product contract is:

1. Consolidation is opt-in through one global **Consolidate accounts** toggle that defaults off. Existing `AccountSelection` remains the source of per-account inclusion; no second account-selection list is introduced.
2. The supported surfaces are the macOS app and bundled CLI. RepoBarCore contracts remain reusable by iOS, but iOS UI is out of scope.
3. Every existing GitHub-backed read and monitoring surface will become account-aware. New remote GitHub mutations, including assign, label, comment, review, rerun, merge, and administration actions, are out of scope.
4. Repositories and items visible through multiple accounts remain separate internally and visually, grouped and labelled by account. Repository display limits apply independently to each account.
5. Existing per-account SQLite caches remain separate, and consolidated state is an in-memory union. The programme will not use SQLite `ATTACH` or add a shared `attention.sqlite` unless later profiling justifies it.
6. When one account fails, its last-good cached rows remain visible and are marked stale or errored while healthy accounts continue. The menu-bar indicator reports the worst included-account health, while details remain per account.
7. Notifications remain separate and account-labelled when multiple accounts observe the same pull request or release.
8. The CLI adds explicit `--all-accounts`, retains `--account` and active-account defaults, and does not implicitly inherit the GUI consolidation toggle.
9. Issue Navigator content from a non-active account requires a second explicit opt-in before OpenAI summaries are allowed.
10. **Needs Attention** uses typed configurable rules for category, account, owner/repository filters, state, and priority. It does not expose arbitrary expressions or a nested AND/OR DSL. Its conservative default preset covers review requests, assignments, and failed workflows on pinned repositories.

The implementation is a sequential bottom-to-top stack:

1. `multi-account-contracts` — settings, account-scoped identities, attention-rule contracts, and Codable compatibility.
2. `multi-account-refresh` — repository snapshot loader, bounded fan-out, last-good partial failures, and active-account compatibility projection.
3. `multi-account-repo-state` — account-scoped pinned/hidden migration, cache and submenu identities, local host matching, and explicit client resolution.
4. `multi-account-cli` — shared account scope, `--all-accounts`, stable output envelopes, and account settings/cache operations.
5. `multi-account-dashboard` — Settings opt-in controls, grouped dashboard/menu, account headers, per-account limits, and account-aware submenus.
6. `multi-account-attention` — typed rule evaluation, shared collectors, the default preset, normalized `AttentionItem`, and `repobar triage`.
7. `multi-account-navigator` — Issue Navigator, Needs Attention mode, reference monitor fan-out, scopes/previews, and the AI secondary opt-in.
8. `multi-account-notifications` — account-namespaced pull request/release polling, baselines, event IDs, labels, and click context.
9. `multi-account-operations-status` — Actions & Runners, monitored owners, rate limits, contribution/global activity, and worst-health state.
10. `multi-account-integration-proof` — integration fixtures, accessibility and UI polish, redacted personal plus EMU proof, and final README, docs, CHANGELOG, and issue updates.

Layers 1 through 3 are implemented. `multi-account-refresh` adds account-scoped repository snapshot loading, bounded selected-account fan-out, cached-first hydration, last-good partial-failure handling, and the active-account compatibility projection. `multi-account-repo-state` makes repository preferences account-scoped, isolates repository caches and submenu identities, resolves clients explicitly, and matches local checkouts by GitHub host. Layers 4 through 10 remain deferred; repository grouping, CLI scope changes, attention and navigator collectors, notifications, Actions, and other user-visible fan-out are unchanged.

Landed:

- Phase 0/1 — `Account`, `AccountSelection`, and `AccountScopedRepositoryLists` live in `RepoBarCore`; `UserSettings` decodes/encodes the new fields with safe defaults and omits them when empty so legacy reads stay clean.
- Phase 1 — `TokenStore` exposes `save/load/clear(tokens:|clientCredentials:|PAT:_:accountID:)` plus an account index that lets callers enumerate accounts on the Keychain or file backend.
- Phase 2 — `AccountManager` (`Sources/RepoBar/Auth/AccountManager.swift`) owns one `GitHubClient` and an account-scoped OAuth refresher per `Account`; `AppState` bootstraps it and `tokenRefreshTask` now drives `refreshAllIfNeeded()`.
- Phase 2 — `AppState+Accounts.swift` performs a one-shot migration that probes `GET /user` with whichever credential currently exists, records the resulting `Account`, and copies tokens under the account-scoped keys.
- Phase 3 — `Session` exposes `accountSessions` / `activeAccountID` / `aggregatedRepositories`, and `TaggedRepo` provides a collision-safe wrapper for the menu fan-out path. Single-account `repositories` and `accessibleRepositories` continue to drive existing UI.
- Phase 4 — `HTTPResponseDiskCache` and `RepoBarPersistentCache` accept an `accountID:` parameter and resolve to `~/Library/Application Support/RepoBar/Cache/<account>.sqlite` (legacy path used when `accountID` is `nil`). `GraphQLResponseDiskCache.scoped(accountID:)` follows the same pattern.
- Phase 5 — `AccountSettingsView` shows an account list (use / visibility / verify / remove) above the legacy single-account form, which is now labelled "Add Account".
- Phase 6 — CLI gains `repobar accounts list/use/remove`, plus `--account`/`--all` on `logout`, `--account` on `status`, and `--label` on `login`/`import-gh-token`. After successful auth both commands fetch `GET /user`, derive a stable `Account`, and persist tokens under the account-scoped keys in addition to the legacy fast-path entries.
- Issue #101 Layer 2 — `AppState` resolves the included account/client pairs once, hydrates each scoped repository cache independently, refreshes through a bounded task group, retains per-account last-good state on failures, and rebuilds `Session.accountSessions` / `aggregatedRepositories` in settings order. Existing menu, activity, notification, and Actions surfaces remain projected from the active account.
- Issue #101 Layer 3 — pinned and hidden repository lists migrate to explicit account entries without losing deliberate emptiness, active-account mutations retain legacy compatibility mirrors, recent/changelog/display caches use account-scoped repository identities, local checkout matching rejects cross-host collisions, and consolidated request paths resolve the owning account's client explicitly. Existing menu and repository Settings presentation remains active-account-only.

Deferred:

- Notification / reference monitor fan-out across accounts. The model currently lives on the active account only; `Session.aggregatedRepositories` is populated but not yet consumed by the menu builders or background pollers.
- Per-account rate-limit display in the menu and Settings (Account list shows a single status today).
- Removing the legacy fixed `TokenStore` keys after migration. The migration helper writes the account-scoped copies; the legacy entries remain in place for now so a downgrade keeps working.

## Current Auth Model

The auth surface is hardwired around one account in these places:

- `TokenStore` (`Sources/RepoBarCore/Auth/TokenStore.swift`) is the only persistence layer. It keys items by `kSecAttrService = "com.steipete.repobar.auth"` and three fixed accounts: `"default"` for OAuth tokens, `"client"` for OAuth client credentials, and `"pat"` for Personal Access Tokens. `TokenStore.shared` is used as a singleton everywhere. The file-backed fallback mirrors the same shape under `~/Library/Application Support/RepoBar/DebugAuth/`.
- `OAuthLoginFlow` (`Sources/RepoBarCore/Auth/OAuthLoginFlow.swift`) runs the PKCE and loopback exchange, using port `53682` by default, and writes tokens into the fixed keys.
- `OAuthTokenRefresher` (`Sources/RepoBarCore/Auth/OAuthTokenRefresher.swift`) loads and saves the same single OAuth token record.
- `OAuthCoordinator` (`Sources/RepoBar/Auth/OAuthCoordinator.swift`) and `PATAuthenticator` (`Sources/RepoBar/Auth/PATAuthenticator.swift`) cache one token set in memory and one `lastHost`.
- `GitHubClient` (`Sources/RepoBarCore/API/GitHubClient.swift`) is an actor with one `apiHost`, one `tokenProvider`, and an embedded `GraphQLClient` actor with one endpoint.
- `Session` (`Sources/RepoBar/App/Session.swift`) holds one `AccountState` and one `accessibleRepositories` / `repositories` list.
- `UserSettings` (`Sources/RepoBarCore/Settings/UserSettings.swift`) carries single `githubHost`, `enterpriseHost`, `authMethod`, and `loopbackPort` fields.
- `AppState` (`Sources/RepoBar/App/AppState.swift`) owns one `OAuthCoordinator`, one `PATAuthenticator`, one `GitHubClient`, and a token-refresh task that assumes "the" account.
- The persistent cache (`Sources/RepoBarCore/Support/RepoBarCacheDatabase.swift`) is exposed through `RepoBarPersistentCache.standardDatabaseURL` and backed internally by `HTTPResponseDiskCache.standardDatabaseURL`; both currently resolve to one `~/Library/Application Support/RepoBar/Cache.sqlite` path that is not partitioned by account.
- The CLI auth commands (`Sources/repobarcli/Commands.swift`) for `login`, `logout`, `status`, and `import-gh-token` reach for `TokenStore.shared` directly.

The existing spec already notes that the architecture should be ready for multi-account while the UI surfaces one account. The useful part is that `OAuthLoginFlow`, `OAuthTokenRefresher`, and `PATAuthenticator` are already injectable with a `TokenStore` parameter, and `GitHubClient` is per-instance state, so spinning up clients per account is straightforward.

The main work is replacing singleton assumptions, scoping persisted data, and making repository identity collision-safe.

## Target Shape

Add a typed `Account` record, an account-aware persistence layer, an `AccountManager` that owns per-account `GitHubClient` actors, and a `Session` that aggregates per-account state. The UI grows an account list, while the data layer unions repositories across accounts and tags every repository with its source account.

## Phase 0: Data Model

Add an `Account` model to `RepoBarCore`:

```swift
public struct Account: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var displayName: String
    public var username: String
    public var host: URL
    public var apiHost: URL
    public var authMethod: AuthMethod
    public var loopbackPort: Int
    public var clientID: String?
    public var addedAt: Date
}
```

Suggested account ID formula:

```swift
"\(host.host!.lowercased())#\(username.lowercased())"
```

That keeps re-login stable for the same user and host while allowing `displayName` to change without breaking references.

Extend `UserSettings` with:

- `accounts: [Account] = []`
- `activeAccountID: String?`
- `accountSelection: AccountSelection = .all`, where selection is `.all` or `.only(Set<String>)`

Keep the existing `githubHost`, `enterpriseHost`, `authMethod`, and `loopbackPort` fields as compatibility shims for one release. Treat them as derived from `activeAccountID`, then remove them later.

## Phase 1: Account-Scoped TokenStore

Keep existing call sites working by adding account-scoped methods and preserving old methods as wrappers around `accountID = "default"`:

```swift
public extension TokenStore {
    func save(tokens: OAuthTokens, accountID: String) throws
    func loadTokens(accountID: String) throws -> OAuthTokens?
    func save(clientCredentials: OAuthClientCredentials, accountID: String) throws
    func loadClientCredentials(accountID: String) throws -> OAuthClientCredentials?
    func savePAT(_ token: String, accountID: String) throws
    func loadPAT(accountID: String) throws -> String?
    func clear(accountID: String)
    func allAccountIDs() throws -> [String]
}
```

Implementation detail:

- Keychain: change `kSecAttrAccount` from `"default"`, `"client"`, and `"pat"` to `"\(accountID):default"`, `"\(accountID):client"`, and `"\(accountID):pat"`.
- File backend: use the same account-key strings in filenames. The existing file backend already maps account-like names to files, so this remains a small change.

Migration:

1. On first launch with the new build, if `UserSettings.accounts` is empty and either a legacy `default` OAuth token or a legacy `pat` token exists, call `GET /user` once with whichever credential is available. Prefer OAuth tokens when both exist so refresh metadata is preserved, but do not skip PAT-only users.
2. Build an `Account` from the returned login and configured host.
3. Copy OAuth tokens, client credentials, and/or PAT values under the new account ID.
4. Delete the legacy fixed keys.
5. Persist the new account list and `activeAccountID`.

Update `docs/auth-storage.md` to document the new schema.

## Phase 2: AccountManager Owns Auth And Clients

Promote the single-account coordination into a manager at `Sources/RepoBar/Auth/AccountManager.swift`:

```swift
@MainActor
final class AccountManager {
    private(set) var accounts: [Account] = []
    private var clients: [String: GitHubClient] = [:]
    private var refreshers: [String: OAuthTokenRefresher] = [:]
    private let tokenStore = TokenStore.shared

    func bootstrap(from settings: UserSettings) async
    func addOAuthAccount(host: URL, clientID: String, clientSecret: String, port: Int) async throws -> Account
    func addPATAccount(host: URL, pat: String) async throws -> Account
    func remove(accountID: String) async
    func client(for accountID: String) -> GitHubClient?
    func refreshIfNeeded(accountID: String, force: Bool = false) async throws -> OAuthTokens?
    func refreshAllIfNeeded() async
}
```

Each `GitHubClient` gets its own `apiHost` and a `tokenProvider` closure that reads account-scoped tokens. `GraphQLClient.setEndpoint` already supports GitHub Enterprise, so the client should not need major changes.

`OAuthCoordinator` and `PATAuthenticator` can remain as internal helpers used by `AccountManager`, or they can be folded in later. The lowest-risk path is to instantiate them per account and wire their token access through the new `TokenStore` methods.

## Phase 3: Multi-Account Session And Refresh

Change `Session` to represent multiple account sessions and a tagged aggregate repository list:

```swift
@Observable
final class Session {
    var accounts: [AccountSession] = []
    var activeAccountID: String?
    var aggregatedRepositories: [TaggedRepo] = []
}

struct AccountSession: Identifiable {
    let id: String
    var account: Account
    var state: AccountState
    var repositories: [Repository]
    var accessibleRepositories: [Repository]
    var rateLimitReset: Date?
    var lastError: String?
}

struct TaggedRepo: Identifiable {
    var repo: Repository
    let accountID: String
    var id: String { "\(accountID)|\(repo.id)" }
}
```

`AppState+Refresh` becomes a fan-out:

1. Iterate `session.accounts`.
2. Fetch each account with its account-specific client, preferably in parallel.
3. Merge into `aggregatedRepositories`.
4. Honor `settings.accountSelection` so users can hide accounts from the menu without removing them.

Pinned and hidden repository settings should move from a single `owner/name` list to an account-scoped form such as `accountID:owner/name`. For migration, treat legacy entries as belonging to the migrated account.

Rate-limit display remains per-account. For the menu-bar meter, choose one clear rule, such as worst-of visible accounts, while the diagnostics view exposes all account buckets.

## Phase 4: Cache Partitioning

Make persistent caches account-scoped:

- `RepoBarPersistentCache.standardDatabaseURL` and the internal `HTTPResponseDiskCache.standardDatabaseURL` path derivation become account-scoped, resolving to `~/Library/Application Support/RepoBar/Cache/<accountID>.sqlite`.
- Keep a separate shared database only for data that is not account-bound, such as local git state.
- On migration, rename the existing `Cache.sqlite` into the migrated account's cache location.
- Partition `GraphQLResponseDiskCache` similarly, passing an account-scoped directory through `GitHubClient` initialization.

This prevents stale or private data from one account from being served under another account and avoids repository ID collisions across GitHub.com and GitHub Enterprise.

## Phase 5: UI

Rewrite `AccountSettingsView` (`Sources/RepoBar/Settings/AccountSettingsView.swift`) into two regions.

Accounts list:

- Row with avatar, `username @ host`, auth method badge, and status.
- Per-row actions: `Check token`, `Refresh token`, and `Remove`.
- Drag-to-reorder support.
- Default account selection.

Add account section:

- Reuse the existing host picker for GitHub.com vs Enterprise.
- Reuse the existing authentication picker for OAuth vs PAT.
- Additions always create another account instead of replacing the current account.

Menu changes:

- In `StatusBarMenuBuilder`, group repositories by account when more than one account is signed in.
- Add account headers that show username, host, and a rate-limit indicator.
- Add an `Accounts` submenu with quick toggles for which accounts appear in the menu.

## Phase 6: CLI

Extend `Sources/repobarcli/Commands.swift` with account-aware commands:

```text
repobar accounts list [--json|--plain]
repobar accounts use <accountID|username@host>
repobar accounts remove <accountID|username@host>
repobar login --host ... [--label "Work"]
repobar logout [--account <id>] [--all]
repobar status [--account <id>] [--all]
repobar repos [--account <id>] [--all]
```

Parse `--account` once in a shared option group so every command can honor it. Default behavior when `--account` is omitted:

1. Use `activeAccountID`, if present.
2. Fall back to the only configured account, if exactly one exists.
3. Otherwise show a friendly error asking the user to choose an account.

`import-gh-token` should learn `--account` and `--label` so multiple `gh` hostnames can map to distinct RepoBar accounts.

## Phase 7: Tests

Add suites around the new account boundary:

- `TokenStoreAccountScopingTests`: saving under account A does not load under account B, and legacy `default` keys are not visible after migration.
- `AccountMigrationTests`: legacy keychain or file-backed tokens plus empty `accounts` settles into one account with a derived ID.
- `AccountManagerTests`: add/remove behavior, refresh isolation, and two accounts on the same host storing distinct credentials.
- `MultiAccountRepoMergeTests`: pinned/hidden filtering by `accountID:owner/name`, plus repository dedupe behavior.
- `CLIAccountFlagTests`: `--account` resolution and the no-accounts friendly error path.

Existing tests under `Tests/RepoBarTests/` and `Tests/repobarcliTests/` should not require behavior changes if Phase 1 preserves the single-account wrappers.

## Edge Cases To Decide Up Front

### Two accounts on the same host

The proposed account ID formula handles `github.com#personal` and `github.com#work`, but OAuth uses one client ID/secret and one loopback port. Decide whether each account can override `clientID`, `clientSecret`, and `loopbackPort`.

Loopback port collisions across simultaneous logins should be serialized. The cheapest safe rule is one in-flight login at a time.

### Repository collisions

The same repository can appear under multiple accounts. `TaggedRepo.id` keeps Swift collection identity collision-safe. The menu may still dedupe visually by `fullName` when both accounts have access, preferring write access and then the account with the healthier API state.

### PR notifications and reference monitor

`GitHubPullRequestNotificationRunner` and `GitHubReferenceMonitor` need to know which account produced a notification or match so deep links and cached metadata remain correct. Add `accountID` to the relevant snapshot and store types.

### Monitored owners and actions billing

Today `monitoredOwners` is one flat list. Move it to `[accountID: [String]]` or resolve the same flat owner list against each account's accessible organizations. The flat-list option is simpler, but it needs clear diagnostics when an owner only exists for some accounts.

### Token refresh task

The current five-minute single-account loop becomes one shared timer that fans out through `AccountManager.refreshAllIfNeeded()`.

## Suggested PR Order

1. Add `Account`, extend `TokenStore` additively, and cover it with tests.
2. Add migration on launch. Let `Session` and `UserSettings` carry `accounts` and `activeAccountID`, while the rest of the app still reads through the active account. This should be a no-visible-change release.
3. Add `AccountManager` and per-account `GitHubClient`, then refactor `AppState` refresh to fan out while keeping the UI effectively single-account.
4. Add the user-visible multi-account UI: account list, add account, remove account, and menu grouping.
5. Add cache partitioning, CLI `--account`, and notification/reference-monitor `accountID` propagation.

This sequence keeps each PR reviewable, preserves the existing single-account contract through the transition, and reduces the risk of mixing storage migration, UI, and cache invalidation in one large change.
