---
summary: "RepoBar product/tech spec: goals, UX, auth flow, data sources, and platform details."
read_when:
  - Planning or scoping RepoBar features
  - Modifying GitHub auth/PKCE flow or data-fetching behavior
  - Modifying auth/token storage
  - Updating UI/refresh intervals or repository selection logic
---

# RepoBar Specification & Implementation Plan

_Last updated: 2025-11-24_

## Goals
- macOS menubar-only app (Swift 6.2, Xcode 26) showing selected GitHub repositories with CI state, issues/PR counts, latest release, recent activity, traffic uniques, and a custom blocky commit/activity heatmap.
- Left-click opens rich window; right-click shows classic menu. Uses MenuBarExtraAccess pattern similar to VibeTunnel.
- Login via browser-based OAuth web application flow + PKCE; release tokens are stored in Keychain, while debug builds use file-backed auth storage to avoid local Keychain prompts. Supports GitHub.com and GitHub Enterprise (trusted TLS only). Architecture ready for multi-account but UI surfaces one account.
- Default repo selection: last 5 active repos for the user; user can pin/unpin repos and configure how many show. Refresh interval configurable (1/2/5/15 min, default 5). Launch at login toggle. Sparkle updates.
- No Dock icon; single-instance only.

## User Experience
- **Menubar icon**: uses menubarextraaccess to differentiate left/right click; by default shows a compact GitHub REST/GraphQL rate-limit meter when data is available, with login/CI aggregate status as fallback/overlay.
- **Left-click window**: grid of repo cards. Each card includes:
  - Repo name + owner, tap to open repo.
  - CI status dot (green/red/yellow) with click-through to Checks/Actions page.
  - Counts: open issues, open PRs.
  - Latest release name + published date (click opens release page).
  - Latest activity line (recent issue/PR comment/review).
  - Unique visitors & unique cloners (last 14 days).
  - Custom blocky heatmap (weekly/day cell style) showing commit/push activity over the last ~180–365 days; uses GitHub-like green scale.
  - Context/"…" menu to unpin.
- **Repo submenu**: open actions, local state, recent lists, heatmap, commits/activity, and inline changelog preview (CHANGELOG.md or CHANGELOG).
- **Header (optional)**: GitHub contribution image (`https://ghchart.rshah.org/<user>`) scaled to window width; toggle default ON.
- **Add repo**: "+" button with autocomplete (user/org repos). Pins repo; reorder by activity recency or pin order TBD (start with pin order, recently-added).
- **Right-click menu**: login state, Log out, Refresh now, Preferences, Check for Updates (Sparkle), Quit. Shows account (GitHub.com or GHE host).
- **Settings (Trimmy-style tabs)**:
  - General: number of repos, refresh interval, show contribution image, launch at login, default scope (user vs org?), heatmap on/off (optional).
  - Accounts: login state, reconnect, logout; GitHub.com client ID/secret entry; GHE base URL/client ID/secret; loopback port; PEM key import for the GitHub App private key.
  - Appearance: card density (compact/comfortable), accent tone (macOS default + GitHub greens for heatmap only).
  - Advanced: rate-limit info, cache reset, diagnostics toggle (verbose logging), show ETag/backoff status, local projects folder (auto-sync + terminal picker).

## Platform & App Identity
- Info.plist:
  - `LSUIElement` = true (no Dock icon)
  - `LSMultipleInstancesProhibited` = true (single instance)
  - Custom URL type: `repobar` scheme, host `oauth-callback` (AppAuth fallback/deep link)
- Bundle identifiers aligned with Trimmy conventions; shared App Group not needed initially.

## Auth Flow (GitHub App, browser-based PKCE)
- GitHub App values (provided): App ID 2344358, Client ID Iv23liGm2arUyotWSjwJ, private key at `/Users/steipete/Library/CloudStorage/Dropbox/Backup/RepoBar/repobar.2025-11-23.private-key.pem`.
- Redirect URI registered in GitHub App: `http://127.0.0.1:53682/callback` (loopback).
- AppAuth flow:
  1) Generate PKCE (S256) + state.
  2) Open default browser to GitHub authorize URL (web application flow for GitHub Apps) with client_id, redirect_uri, state, code_challenge.
  3) Local loopback listener on chosen port (default 53682) captures `code` and `state`; validate state.
  4) Exchange code + code_verifier + client_secret for access + refresh tokens (user-to-server flow per GitHub App docs).
  5) Store access/refresh tokens and installation ID via `TokenStore`; release builds use Keychain, debug builds use file storage. Cache ETag tokens in a bounded in-memory cache.
- Token refresh: use refresh_token grant; handle 401/403 by retry + reauth prompt.
- GHE: same flow, user provides base URL; trusted certs required (no ATS exceptions).

## Data Sources
- GitHub GraphQL v4 via Apollo for primary data:
  - Repo basics, issues/PR counts, statusCheckRollup, latest release (first:1), recent timeline items (comments/reviews).
- REST fallbacks via URLSession:
  - Actions runs / checks if GraphQL status missing: `GET /repos/{owner}/{repo}/actions/runs?per_page=1`.
  - Traffic: `GET /repos/{owner}/{repo}/traffic/views` and `/traffic/clones` (requires Administration: Read permission).
  - Commit activity for heatmap: `GET /repos/{owner}/{repo}/stats/commit_activity` (weekly counts) and/or recent commits with since parameter to build finer day-resolution grid. (These endpoints may cache for minutes; handle 202/empty with backoff.)
- Contribution image: simple URL fetch; cache and scale.

### GitHub boundary (keep drift out)
- All GitHub REST/GraphQL fetching lives in `RepoBarCore` (primarily `GitHubClient` + models).
- App/UI code should not add new GitHub network calls directly; instead add a `RepoBarCore` API and consume it from the app/CLI.

## Permissions to request in GitHub App
- GitHub.com OAuth: do not request OAuth scopes. GitHub App user access tokens are limited by the app's installed repository permissions and the signed-in user's access.
- Repository: Metadata (implicit), Contents: Read, Issues: Read, Pull requests: Read, Actions: Read, Checks: Read, Administration: Read (for traffic clones/views), Environments: Read (optional, for richer CI), Commit statuses.
- Organization: none required beyond installation scope; install on orgs to reach private repos.
- Account: none.
- Events: none (polling only).
- Private organization repositories are visible only when the RepoBar GitHub App installation includes that organization/repository, or when the user signs in with a PAT that has `repo` + `read:org`.
- GitHub Enterprise custom OAuth apps still request `repo read:org` because classic GitHub OAuth has no read-only private repository scope.

## Refresh Strategy
- Global refresh interval configurable (1/2/5/15 min; default 5).
- Per-repo throttling with ETag/If-None-Match; exponential backoff on 403 (rate limit) and 202 for stats endpoints.
- Manual "Refresh now" in right-click menu.

## Repo Selection
- Default view: last 5 active repos (recent pushes/issues/PRs) for the authenticated user (across orgs user can access).
- Settings > Repositories: searchable browser of repositories the authenticated account can access. Search includes repository names, descriptions, languages, and topics. Double-clicking a row opens the repository on the configured GitHub host, while the browser shows visibility state per repo and lets the user switch each repo between Visible, Pinned, and Hidden.
- Pinning: stored per account. Unpin via card overflow menu or set the repo back to Visible in Settings.
- Display limit configurable in Settings.

## UI/Rendering Notes
- Heatmap: custom SwiftUI grid (rows = weekdays, cols = weeks) using computed intensity buckets from commit counts; GitHub green palette. Keep rendering <500 LOC by extracting helpers.
- CI dot: green/yellow/red/gray (unknown). Click opens checks/actions page.
- Layout: adaptive columns (min card width ~260–300). Use macOS-friendly typography (SF) and system spacing; accent only for heatmap.

## Background Services
- Small loopback HTTP listener for OAuth callback (bound to 127.0.0.1, ephemeral during login only).
- Refresh scheduler using `Task` + `Timer` on main actor for UI updates.
- Launch at login via `SMAppService.mainApp`.

## Storage
- Secure release storage: Keychain for access/refresh tokens, client secret, private key.
- Debug storage: debug app bundles set `RepoBarTokenStore=file`, and SwiftPM debug CLI/test binaries fall back to file storage in code. `TokenStore.shared` stores auth JSON under `~/Library/Application Support/RepoBar/DebugAuth` instead of touching Keychain unless `REPOBAR_TOKEN_STORE=keychain` is explicitly set. See `docs/auth-storage.md`.
- UserDefaults/AppStorage for settings (interval, repo list, show contribution image, launch at login, GHE base URL, port).
- Persistent SQLite cache for ETags, response bodies, recent lists, repo details, and rate-limit state. RepoBar owns GitHub archive source configuration; it must not read gitcrawl config. Git-backed backup archives should follow the Discrawl-style snapshot/import workflow described in `docs/cache.md`.

## Dependencies
- menubarextraaccess (left/right click support for MenuBarExtra)
- AppAuth (PKCE + browser OAuth helper; custom user agent/loopback)
- Apollo iOS (GraphQL client/codegen) + swift-algorithms
- Sparkle (updates)
- No SwiftUICharts; heatmap is custom.

## Project Structure (to mirror Trimmy)
- `Package.swift` with targets: App, Tests.
- `Sources/RepoBar/` main app, divided roughly:
  - `App/` (entry, app/scene, Info helpers)
  - `StatusBar/` (controller, menu manager, icon controller, custom window)
  - `Auth/` (PKCE helper, OAuthCoordinator, TokenStore)
  - `API/` (GitHubClient, GraphQL queries, REST endpoints, mappers)
  - `Models/` (Repo, Release, CIStatus, Activity, Traffic, HeatmapCell)
  - `Views/` (Menu window, repo card, heatmap, settings panes)
  - `Settings/` (tab views, storage)
  - `Support/` (RefreshScheduler, ImageCache, Logging)
- `Scripts/` copied/adapted from Trimmy: `compile_and_run.sh`, `package_app.sh`, `sign-and-notarize.sh`, lint/format wrappers.
- `Tests/RepoBarTests/` for Swift Testing suites.
- Tooling: `.swiftformat`, `.swiftlint.yml`, and pnpm scripts (`pnpm format`, `pnpm lint`, `pnpm check`, `pnpm test`, `pnpm build`, `pnpm start`, `pnpm restart`, `pnpm stop`).

## Testing Plan (Swift Testing)
- PKCE helper (code verifier/challenge correctness).
- Loopback server parsing (query params, state validation, port binding fallback).
- RefreshScheduler intervals and backoff behavior.
- Heatmap binning/color bucketing from weekly/daily stats.
- Mapping of GraphQL release/CI status to UI model.
- Basic integration: mocked GitHub client returning staged responses populates repo card view models.

## Security & Privacy
- Release tokens and secrets use Keychain; debug auth can use file-backed storage. Never log tokens or secrets.
- Debug builds intentionally avoid Keychain via file-backed storage so local autonomous runs do not show macOS Keychain prompts.
- App + CLI share tokens via Keychain access group only when a release build is properly provisioned for that entitlement.
- TLS required (no ATS exceptions); reject self-signed for GHE.
- Minimal scopes; per-installation tokens only.
- Single-instance enforced via Info.plist.

## Setup Guide (for you)
1) In GitHub App settings:
   - Callback URL: `http://127.0.0.1:53682/callback`
   - Repo permissions: Metadata (default), Contents: Read, Issues: Read, Pull requests: Read, Actions: Read, Checks: Read, Administration: Read (traffic), Environments: Read (optional).
   - Expire user tokens: ON. Device Flow: ON, so GitHub.com sign-in can run without a client secret. Events: none. Distribution: Any account.
   - Save, note Client ID (Iv23liGm2arUyotWSjwJ), Client Secret (not stored in this repository), App ID (2344358), and private key path.
2) In the app (Settings > Accounts): paste Client ID/Secret; import PEM key; leave GHE URL empty unless needed; confirm loopback port 53682.
3) Install the App on each org where you need private repos, selecting “All repositories” (or specific ones) so Administration: Read covers traffic endpoints.
4) First launch: sign in. With no client secret, GitHub shows a device code in the menu and at github.com/login/device. With a client secret, the browser returns to the loopback port. Tokens are stored via `TokenStore` (Keychain in release, file store in debug), with the client id that issued them.

## Implementation Plan
Done
1) Scaffold project: Package.swift deps (Sparkle, MenuBarExtraAccess, AppAuth, Apollo client stub, swift-algorithms); Info.plist flags; Trimmy-style scripts.
2) Menubar shell: status bar controller/menu manager/custom window & icon; left/right menus, Sparkle, logout, refresh.
3) Auth: custom PKCE + loopback server; Keychain TokenStore; refresh-token flow; host remembered for refresh.
4) API client: REST for user/search/full repo (release/CI/activity/traffic/heatmap); ETag + rate-limit tracking; per-repo rate-limit/error surfaced to models/cards.
5) Models/views: Repository + RepositoryViewModel; cards show CI/issues/PRs/release/activity/traffic/heatmap, per-repo error/rate-limit; contribution header; empty/error/rate-limit banners; settings panes; add-repo sheet; drag-reorder scaffold for pins.
6) Refresh: scheduler with interval/force refresh; settings persistence; pins persisted and ordered.
7) Launch/update: launch-at-login helper; Sparkle menu; single-instance enforced.
8) Tests: PKCE + heatmap reshape + backoff/refresh/cert error mapping + loopback parser (Swift Testing).
9) Error-handling: per-endpoint rate-limit/backoff propagation to cards, repo error/rate-limit copy preserved on reorder; GraphQL enrichment merged with REST.
10) UX polish: drag-reorder hints, context-menu move up/down actions, login host surfaced in menus; enterprise host validation + TLS trust messaging; diagnostics section in Advanced settings; custom colored menubar glyph; logged-out state styling and menu container background refined.
11) Tooling: swiftformat/swiftlint aligned with Trimmy; pnpm scripts for format/lint/check/test/build/start/restart/stop. Apollo codegen config remains optional; manual GraphQL client is the current default.
12) Additional tests: repo view model mapping, heatmap padding, grid reorder helpers.

TODO
- Additional tests (repo model mapping from API, contribution image/heatmap sizing).
- Accessibility: keyboard focus order in menu window, announce rate-limit banners, check card a11y labels.
- Logging/diagnostics toggle and cache reset UI polish.
- Decide whether to re-enable Apollo codegen; regenerate schema/types once a working token for fetch-schema is available.
