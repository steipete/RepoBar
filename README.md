# 🚦 RepoBar

RepoBar is a native macOS menu bar app for keeping GitHub work visible without living in a browser. It shows the repositories you care about, their current issue and PR pressure, recent activity, CI state, releases, local checkout status, and rate-limit health in a compact menu. An early native Windows taskbar tray companion is available under `Windows/`.

![RepoBar screenshot](docs/assets/repobar.png)

RepoBar is built for people who move between many repositories and need fast answers:

- What changed recently?
- Which repos have open issues or pull requests?
- Did CI move?
- Is my local checkout clean or behind?
- Am I about to run into GitHub rate limits?
- Can I inspect issues, PRs, releases, branches, tags, and commits without opening a dozen tabs?

## Install

Homebrew is the recommended install path:

```bash
brew install --cask repobar
```

Direct downloads are available from the [latest GitHub release](https://github.com/steipete/RepoBar/releases/latest).

Windows preview builds are developer-run for now:

```powershell
.\Scripts\build_windows.ps1 build -Runtime win-x64
.\Scripts\build_windows.ps1 publish -Runtime win-x64
```

See [docs/windows.md](docs/windows.md) and [docs/windows-parity.md](docs/windows-parity.md).

## What It Shows

RepoBar's main menu is a repository dashboard:

- Repository cards with issue count, PR count, stars, forks, latest activity, and optional heatmaps.
- A contribution header for the signed-in GitHub account.
- Filters for all repositories, pinned repositories, local repositories, and work-focused views.
- A profile submenu with recent GitHub activity.
- A GitHub API status submenu showing current blockers, live REST/GraphQL state, and persisted REST resource headers.
- Quick access to Preferences, About, and Quit.

Each repository has a rich submenu:

- Open the repository in GitHub.
- Open or checkout the local repo when configured.
- View local branch, ahead/behind, dirty files, and worktrees.
- Browse recent issues, pull requests, releases, CI runs, discussions, tags, branches, contributors, commits, and activity.
- Preview changelog entries from a local `CHANGELOG.md` when available.
- Pin, unpin, or hide the repository.

## Repository Browser

Preferences > Repositories is a real repository browser. It searches repositories RepoBar can access and lets you choose what appears in the menu:

- `Visible` keeps the repo available through normal sorting and filtering.
- `Pinned` keeps the repo near the top.
- `Hidden` removes it from the menu.
- Manual rules remain visible even if a token or GitHub App installation no longer returns the repo, which makes access problems easier to diagnose.

RepoBar can see public repositories, user repositories, collaborator repositories, and organization repositories that the current authentication method is allowed to access.

## Authentication And Private Repos

RepoBar supports GitHub.com and GitHub Enterprise.

For GitHub.com, RepoBar uses a GitHub App user token and does not request broad classic OAuth repository scopes. Access is bounded by:

- the signed-in user's GitHub permissions, and
- where the [RepoBar GitHub App](https://github.com/apps/repobar/installations/new) is installed.

Private organization repositories require the RepoBar GitHub App to be installed on that organization or selected repositories. If an organization requires SAML SSO, or if you need access outside the GitHub App installation boundary, use a Personal Access Token with `repo` and `read:org`.

GitHub Enterprise uses the configured enterprise host and OAuth settings. TLS is required.

Release builds store tokens in the macOS Keychain. Debug builds and SwiftPM CLI/test runs default to file-backed auth storage so local development does not trigger Keychain prompts. See [docs/auth-storage.md](docs/auth-storage.md).

## Local Projects

RepoBar can scan a local projects folder such as `~/Projects` and match local checkouts to GitHub repositories.

Local state appears directly in the menu:

- current branch
- upstream branch
- ahead/behind counts
- dirty file summary
- worktree state
- fast-forward sync status

Optional auto-sync fetches and fast-forwards clean repositories on a configurable cadence. It does not force-push, hard-reset, or discard local changes. See [docs/reposync.md](docs/reposync.md).

## Caching, Archives, And Rate Limits

RepoBar is designed to open from local data first and spend GitHub requests carefully.

It stores REST ETags, response bodies, GraphQL responses, recent lists, repository detail data, and rate-limit state in RepoBar-owned storage. First-open menu rows can be seeded from the persistent cache, then refreshed in the background.

GitHub core limits are usually shared by the GitHub user or integration actor, not by each token string. A PAT, another OAuth app, another GitHub App user token, and `gh` CLI requests for the same account can draw from one shared user budget. The `gh` CLI may keep working after other requests are blocked because GitHub grants that app extra allowance, but using `gh` still spends the normal user budget first.

The optional typed GitHub reference monitor is cache-first too: when enabled in Advanced settings, RepoBar watches issue-number patterns and commit-like hashes, looks for matching cached issues, pull requests, or commits in accessible repositories, and falls back to live GitHub lookups on cache misses. The best match appears as a separate menu bar item that opens in your default browser. Global monitoring requires granting RepoBar Accessibility permission in System Settings.

### Sync With Gitcrawl Archives

RepoBar reads GitHub backup archives that follow the [gitcrawl.sh](https://gitcrawl.sh) portable-store format — a Git-backed SQLite snapshot with `manifest.json` plus `tables/<table>/*.jsonl(.gz)` files. Point RepoBar at any compatible snapshot repository and it imports cleanly into its own SQLite cache.

When GitHub is rate-limited, offline, or temporarily unavailable, issue and pull request lists are answered from the imported archive automatically — the menu does not go blank.

RepoBar owns its own cache and archive configuration: it does not read gitcrawl config and does not write to gitcrawl databases. The archive contract is the on-disk snapshot shape, not a runtime dependency.

The current cache and archive behavior is documented in [docs/cache.md](docs/cache.md). The CLI can inspect this state:

```bash
repobar cache status --plain
repobar cache status --json
repobar archives list
repobar archives status
```

## CLI

RepoBar ships a `repobar` CLI for automation and debugging. It mirrors the app's GitHub and cache paths closely enough to be useful when diagnosing menu behavior.

Examples:

```bash
repobar login
repobar repos --plain
repobar repos --owner openclaw --sort prs --plain
repobar repo openclaw/openclaw --plain
repobar issues openclaw/openclaw --limit 20 --plain
repobar pulls openclaw/openclaw --limit 20 --plain
repobar activity steipete --include-repos --limit 10 --plain
repobar rate-limits --plain
repobar cache status --plain
```

Use `--json` for machine-readable output and `--plain` for output without colors, links, or terminal decoration.

Full reference: [docs/cli.md](docs/cli.md).

## Development

RepoBar is a SwiftPM-based macOS app wrapped by `pnpm` scripts.

Requirements:

- macOS
- Xcode 26 / Swift 6.2
- pnpm 10+

Install script dependencies once:

```bash
pnpm install
```

Common commands:

```bash
pnpm check     # swiftformat + swiftlint + swift test
pnpm test      # Swift Testing suite
pnpm build     # debug Swift build
pnpm windows:build
pnpm windows:publish
pnpm start     # build, package, sign, and launch the app
pnpm restart   # relaunch the app from this checkout
pnpm stop      # quit RepoBar
```

Always launch local builds through `pnpm start` or `pnpm restart`. If the menu does not match the code you just edited, verify the running binary:

```bash
pgrep -af "RepoBar.app/Contents/MacOS/RepoBar"
```

## Project Layout

- `Sources/RepoBar/` - macOS app, menu, settings, auth coordination, local project UI.
- `Sources/RepoBarCore/` - GitHub client, cache/archive readers, models, settings, local Git services.
- `Sources/repobarcli/` - command-line interface.
- `Windows/RepoBar.Windows/` - native Windows taskbar tray companion.
- `Tests/RepoBarTests/` - Swift Testing coverage.
- `docs/` - design notes and operational docs.
- `Scripts/` - build, package, signing, testing, and launch wrappers.

Useful docs:

- [docs/spec.md](docs/spec.md) - product and technical spec.
- [docs/cache.md](docs/cache.md) - persistent cache and archive design.
- [docs/cli.md](docs/cli.md) - CLI command reference.
- [docs/auth-storage.md](docs/auth-storage.md) - Keychain vs debug file-backed token storage.
- [docs/multi-account-auth-plan.md](docs/multi-account-auth-plan.md) - staged design plan for multi-account auth, storage, UI, cache, and CLI support.
- [docs/reposync.md](docs/reposync.md) - local project scanning and sync behavior.
- [docs/release.md](docs/release.md) - release checklist.

## Status

RepoBar is early and moving quickly. The latest released version is 0.5.0, with smarter persistent caching, archive-backed fallback paths, rate-limit visibility, GitHub reference previews, and more robust menu behavior.

## License

MIT. See [LICENSE](LICENSE).
