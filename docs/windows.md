# RepoBar for Windows

RepoBar's Windows support is a native taskbar notification-area companion. It is intentionally separate from the macOS SwiftUI/AppKit app because that stack is macOS-only.

The Windows app currently provides:

- a single-instance tray process
- left-click or right-click taskbar menu access
- configured repository status rows
- optional local project discovery
- local branch, upstream, ahead/behind, dirty-file, and worktree state
- local fetch and fast-forward sync actions
- issue and pull request counts
- latest default-branch Actions run status
- latest release link
- optional traffic views/clones, commit activity summary, and changelog headline
- recent issue, pull request, release, CI run, branch, tag, commit, contributor, activity, and discussion submenus
- direct links to GitHub repository, Issues, Pull Requests, and Actions
- native Preferences window for GitHub host, GitHub App browser sign-in, Credential Manager token storage, token environment variable, local project scanning, refresh cadence, and repository visibility
- repository discovery from GitHub's accessible repository list
- ETag-backed response cache with stale reads when GitHub is temporarily unavailable
- optional signed-in account contribution summary from GitHub GraphQL
- optional GitHub API rate-limit row with quota, reset, blocker, and shared-budget details
- optional Actions summary with latest workflow state, active queue counts, billing usage, and self-hosted runner state per configured repository
- optional pull request notifications through Windows tray balloons with click-through to the pull request
- Issue Navigator window for pasted GitHub URLs and issue/PR references
- optional launch-at-login registration for the current Windows user
- manual update check against the latest GitHub release

## Build

Requirements:

- Windows 10 2004 or newer
- .NET 8 SDK

```powershell
.\Scripts\build_windows.ps1 build -Runtime win-x64
.\Scripts\build_windows.ps1 test
.\Scripts\build_windows.ps1 publish -Runtime win-x64
.\Scripts\package_windows.ps1 -Runtime win-x64
```

Use `win-arm64` on Windows on Arm.

## Package

`Scripts\package_windows.ps1` publishes a self-contained Windows build into `dist\windows\publish\<runtime>` and, when Inno Setup 6 is installed, builds an installer from `Windows\installer.iss`.

Use `-SkipInstaller` to validate the publish layout without requiring the Inno compiler:

```powershell
.\Scripts\package_windows.ps1 -Runtime win-x64 -SkipInstaller
```

The installer can optionally create a desktop shortcut and a current-user startup entry.

Use **Launch at login** in Preferences to add or remove the current executable from the current user's Windows `Run` registry key. Use **Check for updates** from the tray menu to compare the running app version with the latest RepoBar GitHub release.

## Run

```powershell
.\Scripts\build_windows.ps1 run
```

The first run creates:

```text
%APPDATA%\RepoBar\windows-settings.json
```

Use **Preferences** from the tray menu to choose repositories and local project settings. The same values are stored in JSON for scriptable setup:

```json
{
  "githubHost": "github.com",
  "tokenEnvironmentVariable": "REPOBAR_GITHUB_TOKEN",
  "gitHubOAuthClientId": "Iv23liGm2arUyotWSjwJ",
  "gitHubOAuthClientSecretEnvironmentVariable": "REPOBAR_GITHUB_CLIENT_SECRET",
  "refreshIntervalMinutes": 5,
  "openMenuOnLeftClick": true,
  "launchAtLogin": false,
  "discoverLocalProjects": true,
  "localProjectsRoot": "%USERPROFILE%\\Projects",
  "localProjectsMaxDepth": 3,
  "fetchLocalProjectsBeforeStatus": true,
  "autoSyncLocalProjects": false,
  "enableResponseCache": true,
  "showRateLimits": true,
  "showContributionSummary": true,
  "enablePullRequestNotifications": false,
  "showActionsUsage": false,
  "repositories": [
    { "owner": "steipete", "name": "RepoBar", "visibility": "pinned" }
  ]
}
```

## Validation

Run the local Windows build and unit-test gates:

```powershell
.\Scripts\build_windows.ps1 build -Runtime win-x64
.\Scripts\build_windows.ps1 test
```

Run the launch smoke on Windows:

```powershell
.\Scripts\smoke_windows.ps1 -Runtime win-x64
```

Run the hosted Windows Crabbox validation from a machine with Crabbox access:

```bash
CRABBOX_PROVIDER=aws CRABBOX_TARGET=windows pnpm windows:crabbox
```

## Authentication

Use **Preferences > Sign in with GitHub** to authenticate through the RepoBar GitHub App browser flow. RepoBar listens on the same loopback callback as the macOS app, exchanges the PKCE code for GitHub user tokens, stores the OAuth token bundle in Windows Credential Manager, and refreshes it before GitHub requests when needed. The built-in RepoBar client ID is used by default; set `REPOBAR_GITHUB_CLIENT_SECRET` or the configured OAuth secret environment variable before signing in.

OAuth tokens are stored under a per-host target such as:

```text
RepoBar.Windows.OAuth:github.com
```

You can also save a personal access token in Windows Credential Manager. RepoBar stores PATs separately under a per-host target such as:

```text
RepoBar.Windows:github.com
```

Environment variables still work as bootstrap/fallback:

```powershell
$env:REPOBAR_GITHUB_TOKEN = "<token>"
```

The app also checks `GITHUB_TOKEN` and `GH_TOKEN`. Tokens are not written to the settings file. Private repositories require the RepoBar GitHub App to be installed for OAuth access, or a token with repository read access.

## Local Projects

When `discoverLocalProjects` is enabled, RepoBar scans `localProjectsRoot` for Git checkouts. It matches each checkout's `origin` remote to configured repositories and adds branch, upstream, ahead/behind, dirty-file, worktree, fetch, sync, and folder/terminal actions to the tray menu.

Sync is intentionally conservative: manual and automatic sync use `git pull --ff-only`, and auto-sync only runs for clean repositories that are behind their upstream.

Local-only repositories are shown in their own tray section so Windows can still be useful without GitHub authentication.

Repository entries support `visible`, `pinned`, and `hidden` visibility. The tray menu can pin, hide, or restore configured repositories, and writes the updated settings file immediately.

## Design Notes

The Windows target follows the same tray-first shape used by robust Windows companions:

- initialize the tray icon before any optional UI
- keep the tray alive even when a repository refresh fails
- capture repository state, then render the menu from that snapshot
- use native shell opening for GitHub links and settings files

The next natural step is a WinUI 3 flyout for richer cards once the basic Windows packaging path is proven.

See [windows-parity.md](windows-parity.md) for the full parity checklist.
