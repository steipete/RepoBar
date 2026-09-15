---
summary: "Local Projects: scan a project folder, map repos to GitHub cards, show branch + optional auto-sync."
read_when:
  - Adding/changing Local Projects scanning or matching
  - Debugging “no repositories found” in sandboxed builds
  - Adjusting auto-sync behavior or notifications
---

# Local Projects (RepoSync)

Goal: map a local “project folder” (e.g. `~/Projects`) to GitHub repos shown in RepoBar, then surface local branch + sync state, with optional fast-forward auto-sync.

## User-Facing Behavior

### Settings (Advanced → Local Projects)
- **Project folder**: pick a folder; if unset, Local Projects UI stays hidden everywhere.
- **Found count**: show how many git repos are discovered under the folder (fast, even if no GitHub match).
- **Rescan**: icon button (`arrow.clockwise`); triggers a forced rescan + status refresh; shows “Scanning…” while running.
- **Auto-sync clean repos**: when enabled, attempts `git pull --ff-only` on eligible repos.
- **Show dirty files in menu**: shows up to 3 dirty files inline in the main menu (repo card).
- **Fetch interval**: controls how often RepoBar runs `git fetch --prune` to refresh upstream state.
- **Scan depth**: how many folder levels to traverse under the root (default 4).
- **Worktree folder**: default subfolder used for new worktrees (defaults to `.work` inside the repo).
- **Preferred Terminal**: choose terminal app for “Open in Terminal” actions (defaults to Ghostty if installed, else Terminal.app).
  - Ghostty opens a new window via AppleScript; macOS will prompt for Automation/System Events access.
  - Ghostty open mode: New Window (AppleScript) or Tab (standard open).

### Repo cards + details
- Repo card: show current local branch + small status icon when a matching local repo exists.
- Details/menu: show branch, sync state, plus actions:
  - Open in Finder
  - Open in Terminal (preferred terminal)

Worktree listings preserve complete paths, including spaces, Unicode, and line breaks, and complete nested branch names when resolving status and commit metadata.

### Notifications
- Fire a local notification on **successful sync** (auto or manual).
- No notification on failure.

## Scanning & Matching

### Discovery
- Scan the selected folder up to the configured depth (**default 4 levels**).
- A directory counts as a git repo if it contains `.git` (file or folder).
- Skip hidden directories and symlinks.

### Mapping to GitHub repos
- Primary match: folder name == GitHub repo name (owner ignored).
- Secondary hint: parse `origin` remote to derive `fullName` when available.
- Performance: only compute git status for “interesting” repos:
  - current visible repos (plus pinned)
  - matched by folder name

## Auto-Sync Rules

Manual Sync, Rebase, and Reset first fetch the upstream state. If fetching fails, the action stops and displays Git's error; it does not rebase, reset, or push using stale remote-tracking refs.

Only attempt sync when:
- repo is **clean** (no local changes),
- not detached HEAD,
- behind remote,
- pull is **fast-forward only** (`git pull --ff-only`).

“Synced” means:
- pull succeeded **and** `rev-parse HEAD` changed.

## Refresh & Caching

### Triggers
- App refresh tick (same cadence as GitHub refresh).
- Settings → Local Projects section appears.
- Manual Rescan button.

### Caching (for speed)
- Discovery cache TTL: 10 minutes (repo roots under the project folder).
- Status cache TTL: 2 minutes (branch/clean/ahead/behind/sync state).
- Forced rescan bypasses both caches.

## Sandbox Notes (macOS)

RepoBar runs sandboxed; project folder access requires:
- Persisted security-scoped bookmark for the chosen folder.
- Entitlement: `com.apple.security.files.user-selected.read-write` (needed for git writes during sync).

If bookmark is missing/stale: show “0 repos” until user re-chooses the folder.

## CLI Debugging

Use the CLI to validate discovery without launching the app:
- `repobar local --root ~/Projects --depth 4`
- `repobar local --root ~/Projects --depth 4 --sync`

## Reference Context

Local path and commit probes run only on macOS. They use the same Git executable and file-backed process capture as Local Projects, with noninteractive local reads and a five-second bound. Other platforms skip the Git probe and continue normal reference parsing.
