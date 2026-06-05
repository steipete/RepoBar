# RepoBar for Windows

RepoBar's Windows support is a native taskbar notification-area companion. It is intentionally separate from the macOS SwiftUI/AppKit app because that stack is macOS-only.

The Windows app currently provides:

- a single-instance tray process
- left-click or right-click taskbar menu access
- configured repository status rows
- optional local project discovery
- local branch, upstream, ahead/behind, dirty-file, and worktree state
- issue and pull request counts
- latest default-branch Actions run status
- latest release link
- recent issue, pull request, release, branch, tag, and commit submenus
- direct links to GitHub repository, Issues, Pull Requests, and Actions

## Build

Requirements:

- Windows 10 2004 or newer
- .NET 8 SDK

```powershell
.\Scripts\build_windows.ps1 build -Runtime win-x64
.\Scripts\build_windows.ps1 publish -Runtime win-x64
```

Use `win-arm64` on Windows on Arm.

## Run

```powershell
.\Scripts\build_windows.ps1 run
```

The first run creates:

```text
%APPDATA%\RepoBar\windows-settings.json
```

Edit that file to choose repositories:

```json
{
  "githubHost": "github.com",
  "tokenEnvironmentVariable": "REPOBAR_GITHUB_TOKEN",
  "refreshIntervalMinutes": 5,
  "openMenuOnLeftClick": true,
  "discoverLocalProjects": true,
  "localProjectsRoot": "%USERPROFILE%\\Projects",
  "localProjectsMaxDepth": 3,
  "repositories": [
    { "owner": "steipete", "name": "RepoBar", "visibility": "pinned" }
  ]
}
```

## Authentication

Set a token in the configured environment variable before launching:

```powershell
$env:REPOBAR_GITHUB_TOKEN = "<token>"
```

The app also checks `GITHUB_TOKEN` and `GH_TOKEN`. Tokens are not written to the settings file. Private repositories require a token with repository read access.

## Local Projects

When `discoverLocalProjects` is enabled, RepoBar scans `localProjectsRoot` for Git checkouts. It matches each checkout's `origin` remote to configured repositories and adds branch, upstream, ahead/behind, dirty-file, and folder/terminal actions to the tray menu.

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
