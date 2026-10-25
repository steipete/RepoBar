---
summary: "RepoBar auth token storage modes: production Keychain and debug file-backed storage."
read_when:
  - Modifying auth/token storage
  - Debugging Keychain prompts during local development
  - Changing package_app.sh, compile_and_run.sh, or CLI auth behavior
  - Preparing release signing or entitlement changes
---

# Auth Storage

RepoBar has two token storage modes:

- **Keychain**: production default. OAuth tokens, client credentials, and PATs use the macOS Keychain.
- **File**: debug/autonomy mode. Tokens are stored as JSON files under `~/Library/Application Support/RepoBar/DebugAuth`.

`TokenStore.shared` chooses the backend in this order:

1. `REPOBAR_TOKEN_STORE` environment variable.
2. `RepoBarTokenStore` in the app bundle `Info.plist`.
3. Debug-build file storage fallback.
4. Release-build Keychain fallback.

Accepted file values are `file` and `disk`. Set `REPOBAR_TOKEN_STORE=keychain` to force Keychain in debug builds.

## Debug App Builds

`Scripts/package_app.sh debug` writes this into the generated app bundle:

```xml
<key>RepoBarTokenStore</key><string>file</string>
```

That means `pnpm start` and `pnpm restart` use file-backed auth and must not trigger macOS Keychain prompts during autonomous development. The debug app still signs normally, but it also strips `keychain-access-groups` when no provisioning profile is configured.

SwiftPM debug CLI/test binaries do not have the app bundle `Info.plist`, so debug builds also default to file-backed storage in code. Local `swift test`, `pnpm test`, `.build/debug/repobarcli`, and the packaged debug app therefore share the same non-Keychain backend unless explicitly overridden.

To force the same behavior for an installed release CLI/debug process:

```sh
REPOBAR_TOKEN_STORE=file repobar status
```

To force Keychain while debugging:

```sh
REPOBAR_TOKEN_STORE=keychain pnpm start
REPOBAR_TOKEN_STORE=keychain .build/debug/repobarcli status
```

## Unavailable Credentials

A failed credential read is distinct from missing credentials. When macOS denies Keychain access, RepoBar keeps loaded GitHub data and the selected repository filter, refreshes local projects only, and asks you to relaunch. Access is checked again on the next refresh, so the session recovers automatically when credentials become readable. If an update replaces the app while it is running, the menu asks you to relaunch to finish updating.

Menu sign-in opens Accounts settings when a GitHub.com personal-access-token account already exists. Update that token there; the explicit GitHub.com OAuth flow in Accounts settings remains available.

## Release Builds

Release builds do not write `RepoBarTokenStore=file`, so they use Keychain by default.

Developer ID builds currently strip `keychain-access-groups` unless `REPOBAR_SKIP_KEYCHAIN_GROUPS=0` is set for a properly provisioned build. Without a valid provisioning profile, shipping that entitlement causes AMFI launch failures on newer macOS versions.

## File Backend Notes

The file backend exists for local debug autonomy, not for shipped secrets. It stores the same data shape as Keychain:

- `default`: OAuth access/refresh tokens.
- `client`: OAuth client credentials.
- `pat`: Personal Access Token.

Files are written with `0600` permissions where supported. `TokenStore.clear()` removes the file-backed OAuth, client, and PAT entries for the configured service.

## Account-Scoped Keys (Phase 1)

In addition to the legacy fixed keys above, `TokenStore` accepts account-scoped APIs that key each item by `accountID`:

- `<accountID>:default` — OAuth access/refresh tokens for the account.
- `<accountID>:client` — OAuth client credentials for the account.
- `<accountID>:pat` — Personal Access Token for the account.

Public APIs:

- `save(tokens:accountID:)`, `loadTokens(accountID:)`
- `save(clientCredentials:accountID:)`, `loadClientCredentials(accountID:)`
- `savePAT(_:accountID:)`, `loadPAT(accountID:)`
- `clear(accountID:)` removes all three kinds for one account.
- `allAccountIDs()` returns the union of account IDs found in file storage and (best effort) Keychain.

Storage representation:

- **Keychain**: `kSecAttrAccount` is set to `"<accountID>:<kind>"`. `allAccountIDs()` enumerates entries for the configured service (across access groups) and parses out the account ID prefix, ignoring legacy fixed accounts.
- **File**: files are still named `<service>-<account>.json`. The colon separator is sanitized to a dash, so on disk you will see `…-<accountID>-default.json`, `…-<accountID>-client.json`, and `…-<accountID>-pat.json`. Because the on-disk name is sanitized (e.g., `#` → `-`), the filename is not a reliable source of the original account ID. To preserve the original string, file storage also maintains a small JSON index at `<service>-accounts-index.json` next to the token files. Each account-scoped `save…(accountID:)` call records the original `accountID` in this index, and `clear(accountID:)` removes it. `allAccountIDs()` returns the union of indexed IDs and any IDs scanned from filenames (the latter only as a fallback for entries that pre-date the index), sorted and deduplicated. Legacy non-account wrappers (`save(tokens:)`, `savePAT(_:)`, etc.) never write to the index.

The legacy `save(tokens:)`, `load()`, `save(clientCredentials:)`, `loadClientCredentials()`, `savePAT(_:)`, `loadPAT()`, `clear()`, and `clearPAT()` APIs are preserved as wrappers over the fixed `default` / `client` / `pat` keys for backwards compatibility during the multi-account transition.

## Multi-Account Wiring

Phase 2+ wires the account-scoped keys to the rest of the app:

- `AccountManager` (`Sources/RepoBar/Auth/AccountManager.swift`) owns one `GitHubClient` per `Account` and runs an `AccountScopedOAuthRefresher` that reads and writes tokens via `loadTokens(accountID:)` / `save(tokens:accountID:)`.
- On launch, `AppState.bootstrapAccounts()` calls `migrateLegacyAccountIfNeeded()` which probes `GET /user` with whichever credential currently lives under the legacy fixed keys, derives a stable `Account` (`<host>#<username>`), and copies the existing OAuth tokens / client credentials / PAT under the new account-scoped keys. The legacy entries are left in place so that downgrading to a previous build still finds them.
- After successful `repobar login` or `repobar import-gh-token`, both commands probe `GET /user`, derive an `Account`, persist tokens under `<accountID>:default` / `<accountID>:client` / `<accountID>:pat`, and append the account to `UserSettings.accounts`. The legacy fast-path entries are also written so that callers that still read `TokenStore.shared.load()` keep working.
- `HTTPResponseDiskCache.databaseURL(accountID:)` and `RepoBarPersistentCache.databaseURL(accountID:)` resolve to `~/Library/Application Support/RepoBar/Cache/<safe-account-id>.sqlite`, so each `GitHubClient` writes responses to its own SQLite database. Passing `accountID: nil` returns the legacy shared path.
