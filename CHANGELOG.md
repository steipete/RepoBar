# Changelog

## 0.7.1 - Unreleased

- Add optional OpenAI-powered PR summaries to the Issue Navigator sidebar using Tachikoma `chat-latest`, with settings for model and API key storage.
- Give AI PR summaries more Issue Navigator sidebar room and tune generated summary length to the visible row budget.
- Keep the separate Issue Navigator window from auto-scrolling embedded GitHub issue previews while preserving the menu dropdown preview scroll offset.
- Keep Issue Navigator reference clicks from being overwritten by clipboard seeding, and show unresolved GitHub metadata as the reference label instead of "preview unavailable."
- Keep the Repositories settings table from rendering duplicate rows when the same repository is both pinned and hidden (thanks @devYRPauli). (#73)

## 0.7.0 - 2026-05-31

- Add copyable update diagnostics in About so Sparkle install-location failures include bundle path, resolved path, signing, Homebrew, translocation, and quarantine signals. (#70)
- Keep copied repository-scoped PR and issue references like `owner/repo PR #123` resolving to the named repository instead of a newer same-number reference elsewhere.
- Recognize numbered repository triage lists whose issue/PR count summary is on the next indented line.
- Add a design plan for staged multi-account authentication, storage, UI, cache, and CLI support (thanks @felipeorlando).
- Store OAuth, client-credential, and PAT material under stable per-account Keychain keys derived from `host#username`, with a Keychain/file index so multiple accounts can be enumerated without colliding on legacy fixed entries.
- Introduce a multi-account data model (`Account`, `AccountSelection`, account-scoped pinned/hidden repository lists) in `UserSettings` with backward-compatible Codable so existing single-account installs continue to load.
- Add an `AccountManager` that owns per-account `GitHubClient` instances and an account-scoped OAuth refresher, and bootstrap it from `AppState` with a one-shot migration that records the existing single-account credentials under the new account identity.
- Scope persistent GraphQL and HTTP caches per account so each account writes to its own SQLite database under `~/Library/Application Support/RepoBar/Cache/`.
- Surface configured accounts in the Settings sidebar with use/visible/remove actions, and expose `repobar accounts list/use/remove` plus `--account`/`--all`/`--label` flags on `login`, `logout`, `status`, and `import-gh-token` in the CLI.

## 0.6.6 - 2026-05-26

- Open multi-reference GitHub detections in Issue Navigator on left click while keeping the preview menu on right click.
- Open Issue Navigator larger by default while clamping it to the visible screen.
- Add embedded Issue Navigator browser back navigation and reload an already-selected sidebar entry back to its original GitHub URL.
- Preload the first embedded Issue Navigator browser preview when the clipboard resolves to multiple GitHub references.

## 0.6.5 - 2026-05-24

- Reduce GitHub pressure by throttling REST/GraphQL request lanes, moving repo count/release hydration to GraphQL, and fetching commit-activity heatmaps only for visible rows with a daily TTL.
- Keep REST core rate-limit diagnostics focused on the shared quota instead of filling Current Blocker with per-request cooldown rows.
- Keep copied triage lists with leading bare GitHub references from inheriting incidental repository paths mentioned later in item descriptions.
- Show copied GitHub URL previews immediately with loading placeholders, then update each entry as GitHub metadata resolves.
- Recognize copied repo-heading triage blocks like `owner/repo: 1 issue / 1 PR` followed by indented `#123` references.

## 0.6.4 - 2026-05-22

- Read the GitHub reference watcher clipboard contents on the main thread to avoid an AppKit pasteboard crash on macOS 26.5.

## 0.6.3 - 2026-05-22

- Make the Settings Repository table columns sortable (thanks @XueshiQiao).
- Improve copied GitHub reference parsing for maintainer triage lists so bullet-leading references stay prioritized, compound issue lists resolve, and status counts are ignored.

## 0.6.2 - 2026-05-20

- Reduce idle and Issue Navigator CPU use by coalescing timers, polling copied references at background priority, warming previews only while menus or windows are open, and tearing down previews when windows close, while keeping clipboard detection responsive.

## 0.6.1 - 2026-05-17

- Recognize copied prose like `PR 123, 456 and 789` as multiple GitHub references.
- Clean up failed OAuth login listeners and encode OAuth token requests correctly when credentials or refresh tokens contain reserved characters.
- Discover symlinked local project repositories and keep git command output draining while RepoBar waits for local status.
- Bound GitHub lookup fan-out and redact diagnostic query values for REST requests.
- Resolve copied reference snippets with a single `owner/repo` list item so bare `PR #123` references open in that repository.
- Stop showing a repository warning when GitHub's pull request REST endpoint returns 404 for an otherwise visible repository.
- Fix RepoBar CLI help and repository parsing so nested `help` paths, aliases, pasted GitHub URLs, SSH remotes, whitespace, and `.git` suffixes resolve consistently.

## 0.6.0 - 2026-05-14

- Add a full Issue Navigator window for clipboard-aware issue/PR lookup, scoped repository search, keyboard selection, copy/open actions, and inline GitHub previews.
- Add opt-in GitHub pull request notifications for pinned repositories, with browser or Issue Navigator click handling (thanks @Whiteknight07).
- Add an opt-in Actions & Runners menu section for GitHub Actions queue, billing usage, cache, retention, and runner status, with settings to pin the owners RepoBar monitors (thanks @yashiels).
- Add a multi-reference menu action that opens the current GitHub reference set in Issue Navigator.
- Recognize copied GitHub reference lists that write pull requests as `owner/repo #123`.
- Preserve pasted GitHub reference list order in Issue Navigator and ignore incidental references inside list descriptions.
- Show issue, pull request, commit, or workflow run identifiers before titles in the Issue Navigator sidebar.
- Sort Issue Navigator rows by latest update time, choose recent repositories using the active issue/PR filter, and surface scoped repository load failures.
- Cap Issue Navigator all-repository search fan-out, respect the selected issue/PR filter for pasted references, and hide the navigator while signed out.
- Prevent canceled Issue Navigator searches from overwriting newer results and preserve merged pull request state in text search results.
- Keep Issue Navigator typing from opening the selected result, avoid public GitHub fallback before repository inventory loads, and make quick close/reopen cleanup safe.
- Keep Issue Navigator all-repository searches usable when individual repository searches fail, and show GitHub response details instead of a generic client error.
- Show RepoBar in the Dock while the Issue Navigator window is open, then return to menu-bar-only mode when it closes.
- Open Issue Navigator wider by default so the GitHub preview has more usable space.
- Refine Issue Navigator sidebar chrome with a translucent material sidebar and subtler native split-view divider.
- Simplify GitHub Archives settings to accept one repository input while RepoBar manages derived labels and imported SQLite databases internally.
- Harden RepoBar CLI validation and output for GitHub archives, local project roots, markdown images, settings, and copied GitHub references.
- Replace the menu bar GitHub rate-limit bar glyph with a circular quota meter so RepoBar is easier to distinguish from other menu bar apps.
- Fix RepoBar website mobile install cards so long commands and copy controls stay inline without horizontal overflow.

## 0.5.2 - 2026-05-11

- Recognize copied repository-name issue references like `discrawl#64` and resolve them against a unique local or accessible GitHub repository.
- Resolve bare copied commit hashes like `0213e9d` against local repositories before falling back to broad GitHub lookup.
- Recognize copied GitHub Actions run URLs like `owner/repo/actions/runs/123` as GitHub references.
- Move GitHub reference preview actions into an inline browser header with Back, Copy, and Open controls while keeping the preview's persistent GitHub web session.
- Explain in GitHub API Status that rate limits are shared by the GitHub user or actor across PATs, OAuth/GitHub App user tokens, and `gh` CLI requests.
- Recognize chained and ranged copied references like `owner/repo#70/#71` and `owner/repo#66-#69` as multiple GitHub references.
- Start inline GitHub reference browser previews below the repository header so pull request content is visible sooner.
- Improve GitHub reference parsing for grouped `owner/repo: #1, #2` issue lists.
- Rename the GitHub rate-limit menu to GitHub API Status and show the current blocker, shared-token note, endpoint cooldowns, live bucket quotas, and sample age as separate lines.
- Bring the iOS app closer to macOS parity with repository search/filter/sort/owner controls, GitHub rate-limit diagnostics, a manual GitHub reference resolver, share-sheet handoff, and inline reference previews.

## 0.5.1 - 2026-05-10

- Let the GitHub reference monitor recognize multiple copied references at once, infer a surrounding `owner/repo` context for bare `#123` items, and group multiple resolved matches into submenus.
- Infer the GitHub repository for bare references from copied local git paths like `~/Projects/crabbox`.
- Prefer inferred local git repository context over incidental prose slash-words when resolving bare GitHub references.
- Make GitHub reference updates feel faster with shorter clipboard polling, cached local path inference, and progressive concurrent lookups.
- Grow inline GitHub reference previews on larger displays so more of the issue or pull request is visible in the menu.
- Fix the iOS app target build by avoiding macOS-only filesystem and git APIs (#61, thanks @jsj).
- Restore `pnpm restart` so it rebuilds and relaunches the debug app as documented (#60, thanks @biefan).

## 0.5.0 - 2026-05-09

- Add an optional Advanced setting for a clipboard-only GitHub reference monitor that surfaces issues, pull requests, and commit hashes from accessible repositories as a separate menu bar item, with cache-first lookup and live GitHub fallback.
- Show per-endpoint GitHub cooldowns in the Rate Limits sidebar and diagnostics so commit-activity backoff is distinct from healthy REST/GraphQL quota buckets.
- Stop showing a generic “not found” warning when a repository has no visible releases endpoint.
- Hide the repository filter bar when the only available scope would be Local.
- Recognize copied GitHub URLs, owner/repo#number shorthands, and short or long commit hashes, including hashes embedded in pull request changes URLs and numeric-looking short hashes.
- Add a CLI reference translator so GitHub reference parsing can be tested end to end.
- Move GitHub reference watcher pasteboard polling off the main thread so the menu bar stays responsive.
- Restore AppKit-native status item menus, keep the status buttons enabled, and remove the watcher item when no match is visible.
- Keep GitHub reference watching clipboard-only so RepoBar never needs Accessibility permission or global keyboard monitoring.
- Show GitHub reference matches in a preloaded inline browser preview, with iconed Open and Copy commands above a taller browser area.
- Distinguish open, closed, and merged GitHub references in the menu bar title and icon.
- Use fresh AppKit autosave names for RepoBar status items and explicitly tear them down on quit to avoid stale menu bar item state across debug relaunches.
- Collapse the GitHub reference watcher to a zero-width placeholder between matches so it keeps its menu bar placement while avoiding stale hit regions.
- Remove misleading page-size count badges from Releases, Discussions, Tags, Branches, and Contributors submenu rows.
- Sort repository activity events by timestamp so repo submenus do not show stale activity when GitHub returns events out of order.
- Refresh the RepoBar website with a cleaner minimal design, dark-mode support, and clearer install/setup copy.

## 0.4.1 - 2026-05-04

- Add a menu bar GitHub rate-limit meter and a detailed GitHub Rate Limits menu with grouped resource buckets, progress bars, reset times, and GraphQL/API bucket data from GitHub's `/rate_limit` endpoint.
- Move GitHub rate-limit status above the repository filter bar, expose it from the profile submenu, and keep the menu bar meter, main menu row, CLI, and debug output on the same refreshed snapshot.
- Widen and streamline the Repositories settings browser with cached row filtering, lighter visibility controls, and corrected issue/pull request counts when GitHub's `open_issues_count` includes pull requests.
- Keep hosted recent-list menu rows visible so the Open Actions submenu no longer opens blank.
- Fix profile-submenu activity by merging cached per-repository `latestActivity` events when full activity arrays are not present.
- Clarify endpoint cooldown messages so per-endpoint backoff does not look like a global GitHub rate-limit failure.
- Add the RepoBar traffic-light emoji to the README title.

## 0.4.0 - 2026-05-03

- Fix Issues submenus when GitHub returns pull requests in the REST issues feed before actual issues, surface GitHub rate limits in the menu UI, and add usable recent-list/REST logs for debugging stuck submenu loads.
- Keep cached repo submenus wired to their recent Issues/PR loaders after menu filter rebuilds so nested lists do not stay stuck on “Loading…”.
- Rebuild the open menu when hydrated repository counts arrive so PR badges no longer stay at the cheap REST-list placeholder value.
- Seed first-open menu rows from the persistent cache, using cached repo-detail PR counts instead of showing a loading spinner when SQLite already has data.
- Rebuild the contribution/profile submenu when global GitHub activity finishes loading, and add a GitHub Rate Limits submenu with live REST/GraphQL plus persisted REST resource limits.
- Fetch pagination-header-based PR/commit counts without conditional ETag reuse so cached bodies cannot collapse counts to one item.
- Clamp SwiftUI-hosted menu row measurements and give plain hosted rows intrinsic vertical sizing so first-open menu layout cannot inflate into an oversized scroll well.
- Add the GRDB-backed persistent REST cache foundation plus RepoBar-owned GitHub archive source settings/CLI commands, explicitly avoiding gitcrawl config discovery.
- Add CLI cache diagnostics/clear commands and archive status/validate/update commands so the new cache/archive surfaces are script-testable.
- Make RepoBar's SQLite ETag cache authoritative by bypassing URLSession's local HTTP cache for conditional GitHub REST requests.
- Add persistent GraphQL response caching, native gzip archive import, archive issue/PR readers with rate-limit fallback, and Settings archive update/status controls.
- Fix release tagging when Git is configured to sign tags by default.

## 0.3.0 - 2026-05-03

- Stop requesting broad OAuth repository scopes for the built-in GitHub.com GitHub App login; custom Enterprise OAuth still requests `repo read:org`.
- Clarify private organization repository access: Accounts now links to the RepoBar GitHub App installation, docs explain the installation/PAT boundary, and direct repo 404s say when a repo is not visible to the current token.
- Fix release signing defaults so Developer ID builds strip the shared keychain access group unless explicitly enabled with a provisioning profile (#44, thanks @Chefski).
- Sign bundled helper binaries without app-only entitlements so the CLI is not rejected by AMFI.
- Default SwiftPM debug CLI/test auth to file-backed storage so local runs do not trigger Keychain prompts.
- Fix owner-filtered CLI repo lists so `--limit` is applied after filtering by owner.
- Turn the Repositories settings tab into a searchable browser for accessible repos with pinned/hidden state.
- Improve macOS 26 menubar attachment compatibility by updating MenuBarExtraAccess and using its required modifier order (#47, thanks @jviehhauser).
- Prevent duplicate repository entries from crashing refresh or menu rendering.
- Fix awkward cooldown error copy.
- Bound long-lived menu/API caches to avoid gradual memory growth.
- Update README install/setup guidance for the 0.3.0 flow and point Homebrew users at the official cask.
- Add the MIT license.
- Update Swift package and npm dependencies, including MenuBarExtraAccess compatibility work.
- Update GitHub Actions pins, opt actions into the Node 24 runtime, and make CI Homebrew tool installation idempotent.
- Strengthen SwiftLint and SwiftFormat rules and apply the current formatter output.

## 0.2.0 - 2026-01-21

- Fix the menu getting stuck on “Loading repositories…” by staging the initial repo list load.
- Fix menubar clicks doing nothing by attaching the status item via a fallback path.
- Add Personal Access Token authentication with persistence + logout fixes (#21, thanks @kkiermasz).
- Add GitHub.com vs Enterprise login picker with OAuth help text (#4).
- Show OAuth errors in Accounts sign-in UI (#6).
- Add token status checks + forced refresh buttons in Settings for debugging auth issues.
- Prevent token check/refresh from hanging; add timeouts and diagnostics logging.
- Detect auth failures (401/refresh errors) and log out cleanly with a clearer message.
- Preserve keychain access groups in signed builds so app + CLI share tokens (#16, thanks @jj3ny).
- Allow importing GitHub CLI tokens with host matching and no refresh loop (#24, thanks @bahag-chaurasiak).
- Surface a clear error when the OAuth loopback port is already in use (#17, thanks @kiranjd).
- Add “Show only my repositories” toggle (owner filter) for repo lists and search.
- Fix the toggle to reset to “show all” when disabled; disable it when signed out.
- Fix commit links to respect GitHub Enterprise host (#9).
- Make pinned/hidden repo matching case-insensitive (fixes private repo pinning edge cases).
- Keep the menu open after pin/unpin/hide/move actions (#25, thanks @bahag-chaurasiak).
- Make Local Projects scan depth configurable (default 4) (#11, thanks @shunkakinoki).
- Stabilize repo settings autocomplete (no spinner layout wiggle), widen the dropdown, show repo stats/badges, fix filtering/hover/scroll, and anchor/size the dropdown to results (no bounce on shrink).
- Widen Enterprise Base URL field and shrink auth progress indicators to avoid layout jumps.
- Derive activity commit links from repo URL when event repo name is missing or malformed.
- iOS: update app icon + logo assets.

## 0.1.2 - 2025-12-31

- iOS app preview (not finished, not in the App Store yet): repo list/cards, activity feed, detail drill‑downs, login/settings, icons/branding, and continued auth/UI polish.
- CLI parity expansion: new repo list subcommands (releases, CI runs, discussions, tags, branches, contributors, commits, activity) plus `--owner/--mine` filters.
- CLI local actions + settings: sync/rebase/reset/checkout, branch/worktree listings, Finder/Terminal open; pin/hide and settings show/set; installer for `repobar`.
- Changelog UX: submenu preview improvements plus Markdown rendering upgrades (block layout, scrollable preview, header alignment).
- Changelog UX: show the first released section headline in the submenu badge (skips Unreleased).
- Changelog UX: prefetch on repo submenu open and refresh the badge after load.
- Changelog UX: switch to Swift Markdown AST parsing for cross-platform block rendering.
- Releases submenu: show latest release name next to the count badge.
- Menu customization: Display settings to reorder/hide main menu and repo submenu items (reset to defaults), with spacing tweaks.
- Logging/diagnostics: swift-log integration with OSLog + optional file logging; debug logging settings for macOS/iOS.
- Reliability: menu rehydrate on attach, invalidate empty menu cache, stabilize contribution header heatmap size, limit “More” submenus to 20 entries.
- Repo access + errors: include org/collaborator repos, improve repo detail error messaging, cache discussions capability and hide disabled entries.

## 0.1.1 - 2025-12-31

- Add repo submenu changelog preview (CHANGELOG.md or CHANGELOG) with inline markdown rendering.
- Changelog submenu: move under Open in GitHub, make preview scrollable, and show entry counts since last release.
- Improve menu loading UX (repo loading row, earlier contribution fetch) and restore markdown formatting in changelog preview.
- Fix settings login to use default GitHub credentials when blank, refresh after sign-in, and avoid stuck state.
- Dev: SwiftLint cleanup in changelog loader.
- iOS: fix light/dark glass styling and switch to a full-screen login layout.
- iOS: use the modern `UILaunchScreen` plist entry to avoid letterboxed launch.
- iOS: add a close button to the Settings sheet.
- iOS: switch GitHub auth callback to `https://repobar.app/oauth-callback`.
- Site: add Apple App Site Association for `repobar.app` universal links.
- iOS: add `webcredentials` associated domain for HTTPS auth callbacks.
- iOS: silence AppIntents metadata build warnings.
- iOS: add the RepoBar logo to the login screen and app icon.
- iOS: present the logo in a squircle with more padding on login.
- iOS: add activity/commit icons in the activity list.
- iOS: add a repo detail hierarchy with category drill-down lists.
- iOS: declare iPad orientations to silence Xcode build warnings.
- iOS: show avatars in activity and repo detail lists.
- iOS: soften the glass background to match native palettes.
- iOS: keep file browser navigation within the repo detail stack.
- iOS: improve repo detail error messaging and logging.
- Fix CLI: allow invoking bundled `repobarcli` directly (argv0 normalization).
- Fix CLI auth refresh: show actionable error when refresh response is missing tokens.
- CLI: add markdown rendering command backed by Swiftdansi.
- CLI: add changelog parser command and end-to-end markdown/changelog tests.
- CLI: default changelog command to CHANGELOG files in the repo when no path is provided.
- Add Settings installer to link `repobar` CLI into common Homebrew paths.
- Add Display settings to reorder/hide main menu and repo submenu items (reset to defaults included).
- Make Display reset action destructive and stabilize spacing for rows without subtitles.
- Invalidate menu cache and rebuild if the menu appears too small when opening.
- Add padding between About links and bump settings window height for more breathing room.
- Increase padding between Display list entries.
- Remove pinned repo move up/down commands from repo submenu.
- Limit "More Activity/Commits" submenus to 20 entries.
- Include organization and collaborator repositories in repo lists.
- CLI: add `--owner`/`--mine` filters for repos list.

## 0.1.0 - 2025-12-31

First public release of RepoBar — a macOS menubar dashboard for GitHub repo health, activity, and local project state.

### Highlights
- Live repository cards with CI status, activity, releases, and rate‑limit awareness.
- Rich submenus for recent pull requests, issues, releases, workflow runs, discussions, tags, branches, and commits.
- Local Git state surfaced directly in the menu (branch, upstream/ahead/behind, dirty files, worktrees) with safe actions.
- Contribution heatmap header and global activity feed.
- Fast, native menu UI with adaptive layout and caching for performance.

### Feature overview
- **Menubar experience**
  - Repository cards with stats (stars, forks, issues, last push), CI badge, activity preview, and optional heatmaps.
  - Pinned/hidden repos, menu filters, and configurable sorting.
  - Empty/logged‑out states that explain what to do next.

- **Recent activity & insights**
  - Pull requests, issues, releases, workflow runs, discussions, tags, branches, and commit lists per repo.
  - Global activity menu with recent events and commits.
  - Activity links deep‑link to the most relevant GitHub pages.

- **Local projects & Git actions**
  - Local repo status: current branch, upstream sync, dirty counts, and file lists.
  - Worktree and branch menus with metadata and quick actions.
  - Open in Finder/Terminal, checkout, create branch/worktree, sync/rebase/reset.

- **Auth & API**
  - OAuth login, secure token refresh, and shared core used by the CLI.
  - Rate‑limit awareness and caching to minimize GitHub API usage.

- **Contribution heatmap**
  - Header heatmap (cached) with the ability to refresh and clear cache.
  - Optional menu heatmaps aligned to a week‑based date range.

- **Performance & reliability**
  - Cached repo details, activity, and heatmaps for a snappy menu.
  - Menu layout caching, reuse of menu items, and debounced refresh.
  - Timeouts and graceful fallback for slow network requests.

- **CLI** (`repobar`)
  - Status and repo listings with filters, JSON/plain output, and release info.
  - Commands for issues/pulls lists, pinned/hidden scopes, and activity age filtering.

- **Updates**
  - Sparkle updater for signed builds with update‑ready menu entry and full dialog flow.

- **Developer tooling**
  - SwiftPM + pnpm scripts, lint/format, Apollo GraphQL codegen.
