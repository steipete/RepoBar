# Windows Parity Plan

RepoBar for Windows should become a native taskbar companion with the same product contract as the macOS menu bar app. The implementation is separate because SwiftUI/AppKit and macOS Keychain/Sparkle are not portable.

## Parity Targets

| Surface | macOS behavior | Windows target | Current status |
| --- | --- | --- | --- |
| Tray chrome | Menu bar status item, left/right click behavior, single instance | Notification-area icon, left/right click menu, single instance, refresh/preferences/log out/update/quit actions | Mostly |
| Repository rows | Issue/PR counts, stars, forks, CI, release, activity, traffic, heatmap display/window controls | Same repository status signals rendered in native tray rows and submenus with configurable heatmap placement and 1/3/6/12-month window | Mostly |
| Repository submenu | GitHub links, local state, Finder/Terminal open actions, worktrees, issues, PRs, releases, changelog, CI runs, discussions, tags, branches, contributors, commits, activity, recent issue/PR filters, pin/hide, hide/reorder customization with grouped sections | Same actions where GitHub APIs support them; Windows shell opens folders/terminal and worktrees through independent customizable submenu entries, can check out missing local repos, shows scoped global and per-repository Commit/Activity feeds, filters recent issues by viewer/label and recent PRs by viewer/engagement, and can hide/reorder grouped repository submenu entries with individual pin/visible/hide/move controls | Mostly |
| Local projects | Scan project root, match remotes, show branch/ahead/behind/dirty/worktrees, optional dirty file names, preferred terminal, sync actions | Scan Windows project root with Preferences scan feedback, match remotes, show branch/ahead/behind/dirty/worktrees, optional dirty file names, Explorer/preferred terminal actions, safe fast-forward sync with success notifications, branch switching, worktree creation, and worktree navigation actions | Mostly |
| Auth/accounts | GitHub App OAuth, PAT fallback, GitHub Enterprise, multi-account storage | GitHub App browser OAuth with refresh, PAT/env fallback, GitHub Enterprise host support, named account profiles with account-scoped Credential Manager entries and repository lists | Mostly |
| Repository browser | Search accessible repos, filter forked/archived repos, set Visible/Pinned/Hidden, owner/status filters, all/pinned/local/work menu scopes, display limit, menu sort, and display/menu customization | Native settings window with filtered accessible repo discovery, fork/archive inclusion toggles, account-scoped visibility controls, owner/status display filters, all/pinned/local/work menu scopes, display limit, menu sort, and main/repository menu customization | Mostly |
| Cache/offline | Account-scoped SQLite cache, ETags, archive fallback | Account-scoped ETag response cache plus RepoBar archive SQLite fallback for recent issue/PR lists | Mostly |
| Contribution header | Signed-in account contribution heatmap | Signed-in account contribution totals, compact heatmap preview, and recent week totals in the tray menu | Mostly |
| Rate limits | REST/GraphQL resource meter and blocker banner | Tray rate-limit state with REST/GraphQL resource buckets, quota, reset, blocker, and shared-budget details | Mostly |
| Actions usage | Optional Actions/runners billing menu with plan-tier limits and artifact-retention policy | Optional workflow summary plus queue, billing usage, included-minute/plan-tier allowance, cache usage, artifact-retention policy, and self-hosted runner state | Mostly |
| Issue Navigator | Clipboard/reference resolver window with browser preview and optional clipboard-only monitor | Windows reference resolver window with embedded browser preview, copy, open actions, and optional clipboard watcher balloon click-through | Mostly |
| Notifications | Optional PR notifications for new PRs, updates, closed/reopened/merged state changes, review requests, and comments with browser or Issue Navigator click handling | Windows tray notifications for new PRs, updates, closed/reopened/merged state changes, review requests, and comments with configurable browser or Issue Navigator click-through, account-scoped baselines, first-enable baseline reset, and persistent duplicate suppression across transient empty refreshes | Mostly |
| Updates/install | Sparkle/Homebrew/DMG plus copyable update diagnostics and automatic update checks | Installer, current-user startup option, manual/automatic GitHub release checks with Windows installer asset detection, and copyable update diagnostics | Mostly |
| Debug logging | Optional diagnostics overlay, log verbosity, and file logging | Preferences expose diagnostics capture, log verbosity, and file logging; diagnostics include log state and Crabbox smoke proves log-file creation | Mostly |
| Tests | Swift tests for parsing, auth, cache, refs, menu signatures | .NET unit tests plus Windows Crabbox build/runtime smoke with screenshot/artifact capture | Mostly |

## Implementation Order

1. Native tray baseline with GitHub status and local git state.
2. Unit-testable service layer for GitHub REST, settings, local git, URL building, and menu model generation.
3. Native Windows settings window for token/account, local projects, repository visibility, and refresh interval.
4. Persistent cache with ETags and offline rendering.
5. Recent list endpoints and submenu parity for issues, PRs, releases, CI runs, tags, branches, contributors, commits, and activity.
6. Windows packaging and update story.
7. Crabbox Windows validation: build, tests, tray launch smoke, settings-file smoke, and screenshot/artifact capture when desktop leases are available.

## Validation Contract

Feature parity is not complete until the Windows target has:

- `dotnet build` and `dotnet test` passing on a Windows runner.
- A Crabbox Windows run proving build and tests against the dirty checkout.
- A Crabbox desktop smoke that launches the tray, captures the notification-area process, and verifies the generated settings file. Current screenshot proof is checked in at `docs/assets/repobar-windows-tray-menu.png`.
- A manual or automated proof artifact for at least one repository with GitHub status and local git status shown together; Windows validation writes a TRX artifact for this coverage under `dist/windows/test-results`, and CI uploads it as `repobar-windows-test-results`.
- A launch-smoke proof artifact with the running tray process, local Git fixture, archive fallback rows, runtime settings, rendered menu proof, screenshot status, and `repobar-windows-validation.json` validation manifest under `dist/windows/smoke`; CI uploads it as `repobar-windows-smoke`.
- GitHub App OAuth proof against GitHub.com or a stubbed loopback/token exchange plus refresh coverage.
- Account-switch proof that separate Windows profiles resolve separate OAuth/PAT credential targets, repository lists, response caches, and PR notification baselines.
- Archive fallback proof that recent issue and pull request lists survive failed live GitHub endpoints.
- Diagnostics logging proof that Windows settings can enable debug/file logging and the launched tray writes the configured log file.

## Current Validation Commands

```powershell
.\Scripts\build_windows.ps1 build -Runtime win-x64
.\Scripts\build_windows.ps1 test
.\Scripts\smoke_windows.ps1 -Runtime win-x64
```

```bash
CRABBOX_PROVIDER=aws CRABBOX_TARGET=windows pnpm windows:crabbox
```

The Crabbox gate is the required hosted proof. If the coordinator returns `401 unauthorized`, the implementation is not considered Crabbox-validated.
