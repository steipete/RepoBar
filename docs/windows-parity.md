# Windows Parity Plan

RepoBar for Windows should become a native taskbar companion with the same product contract as the macOS menu bar app. The implementation is separate because SwiftUI/AppKit and macOS Keychain/Sparkle are not portable.

## Parity Targets

| Surface | macOS behavior | Windows target | Current status |
| --- | --- | --- | --- |
| Tray chrome | Menu bar status item, left/right click behavior, single instance | Notification-area icon, left/right click menu, single instance | Started |
| Repository rows | Issue/PR counts, stars, forks, CI, release, activity, traffic, heatmap | Same repository status signals, rendered in native tray/flyout | Partial |
| Repository submenu | GitHub links, local state, worktrees, issues, PRs, releases, changelog, CI runs, discussions, tags, branches, contributors, commits, activity, pin/hide | Same actions where GitHub APIs support them; Windows shell opens folders/terminal | Partial |
| Local projects | Scan project root, match remotes, show branch/ahead/behind/dirty/worktrees, open Finder/Terminal, sync actions | Scan Windows project root, match remotes, show branch/ahead/behind/dirty/worktrees, open Explorer/Terminal, later safe sync actions | Started |
| Auth/accounts | GitHub App OAuth, PAT fallback, GitHub Enterprise, multi-account storage | PAT/env bootstrap first, then Windows Credential Manager + OAuth/GHE account UI | Missing |
| Repository browser | Search accessible repos and set Visible/Pinned/Hidden | Native settings window with search and visibility controls | Missing |
| Cache/offline | SQLite cache, ETags, archive fallback | Shared cache schema or Windows-owned equivalent with ETags/offline reads | Missing |
| Rate limits | REST/GraphQL resource meter and blocker banner | Tray tooltip/menu rate-limit state and blocker row | Missing |
| Actions usage | Optional Actions/runners billing menu | Optional Actions/runners billing menu | Missing |
| Issue Navigator | Clipboard/reference resolver window with browser preview | Windows reference resolver/flyout or window | Missing |
| Notifications | Optional PR notifications | Windows toast notifications | Missing |
| Updates/install | Sparkle/Homebrew/DMG | MSIX or installer plus update path | Missing |
| Tests | Swift tests for parsing, auth, cache, refs, menu signatures | .NET unit tests plus Windows Crabbox build/runtime smoke | Started |

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
- A Crabbox desktop smoke that launches the tray, captures the notification-area process, and verifies the generated settings file.
- A manual or automated proof artifact for at least one repository with GitHub status and local git status shown together.
