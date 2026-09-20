---
summary: "RepoBar caching and GitHub archive source design."
read_when:
  - Adding or changing persistent GitHub caching
  - Adding SQLite or GRDB-backed storage
  - Integrating Git-backed GitHub issue/PR archives
  - Debugging rate-limit behavior or stale cached data
---

# Cache And Archive Design

RepoBar should own its GitHub cache and archive configuration. It must not read
or infer settings from gitcrawl or any other crawler's config file.

## Goals

- Open menus from local data first.
- Spend GitHub requests only when data is stale and the rate budget is healthy.
- Survive app restarts with persistent ETags, REST response bodies, GraphQL
  response bodies, recent lists, and rate-limit state.
- Allow one or more GitHub backup archives to be configured directly in
  RepoBar.
- Treat backup archives as read-only input unless the user explicitly runs an
  import/update command.

## Recent-List Deadlines

Recent-list menus stop waiting after 12 seconds. Each caller has its own deadline; a shared request is cancelled only when its last waiter leaves. Cancelled requests retain their timeout state during a 12-second cleanup window, so immediate retries do not start duplicate work. Completion clears the request sooner; otherwise the cache retires it after that window and permits a fresh request. Late results cannot clear or publish into a newer request.

## Rate-Limit Backoff

REST and GraphQL distinguish primary quota exhaustion from secondary throttling. `Retry-After` supports seconds and HTTP dates; an exhausted primary quota also waits for its reset. Secondary limits without a retry header wait at least one minute. Queued requests recheck the budget before starting network work, and ordinary permission failures do not create a quota cooldown.

## RepoBar-Owned Configuration

RepoBar stores archive sources in `UserSettings.githubArchives`. The app and CLI
persist this in RepoBar's own settings store, not in gitcrawl config.

Implemented settings model:

```swift
public struct GitHubArchiveSettings: Equatable, Codable {
    public var sources: [GitHubArchiveSource] = []
    public var preferArchiveWhenRateLimited = true
    public var staleAfterSeconds: TimeInterval = 15 * 60
}

public struct GitHubArchiveSource: Identifiable, Equatable, Codable {
    public var id: String
    public var name: String
    public var enabled: Bool = true
    public var localRepositoryPath: String?
    public var remoteURL: String?
    public var branch: String = "main"
    public var importedDatabasePath: String
    public var format: GitHubArchiveFormat = .discrawlSnapshot
}

public enum GitHubArchiveFormat: String, Equatable, Codable {
    case discrawlSnapshot
}
```

The CLI has scriptable source management commands:

```sh
repobar archives add openclaw \
  --repo ~/Backups/github-openclaw \
  --db "~/Library/Application Support/RepoBar/Archives/openclaw.sqlite"
repobar archives list
repobar archives status openclaw --json
repobar archives validate openclaw
repobar archives update openclaw --json
```

`archives update` pulls the configured Git snapshot repo when a remote is set,
reads `manifest.json`, imports `tables/<table>/*.jsonl` and
`tables/<table>/*.jsonl.gz` into the configured SQLite database, and records
import metadata in `repo_bar_archive_imports` plus a `repobar:last_import` row
in `sync_state`. If a source has only `--remote`, update creates a RepoBar-owned
local snapshot checkout under Application Support and stores that path in
RepoBar settings.

## RepoBar SQLite Cache

RepoBar persists REST ETag response bodies and rate-limit reset times in
`~/Library/Application Support/RepoBar/Cache.sqlite` using GRDB. This cache is
the first step toward moving all hot menu data into SQLite.

Current tables:

- `api_responses`: request key, URL, ETag, status, headers JSON, body, fetch
  time, and rate-limit metadata.
- `graphql_responses`: endpoint, operation, request-body key, response body,
  and fetch time for GraphQL calls such as contribution heatmaps.
- `graphql_quota_snapshots`: endpoint and last observed response-header quota,
  scoped to the account database and restored only before its reset time.
- `rate_limits`: GitHub resource name, remaining budget, reset time, and last
  error.

Current behavior:

- REST requests with ETags write response bodies to SQLite.
- Later app/CLI runs can satisfy `304 Not Modified` from the persisted body.
- ETag-enabled REST requests bypass URLSession's local HTTP cache so GitHub
  conditional responses are visible to RepoBar's SQLite cache instead of being
  masked as cached `200` responses.
- Rate-limit reset state survives restarts, so RepoBar can avoid immediately
  retrying a known-limited GitHub resource.
- GraphQL calls use the persistent cache for 15 minutes and fall back to stale
  cached response bodies when GitHub is rate-limited, offline, or temporarily
  unavailable.
- GraphQL quota observations survive restarts even when all repository responses
  come from cache. Restoring a sample makes no API request and does not change
  its original observation time. Expired samples are not restored.
- When no current GraphQL quota sample exists (including upgrades from older
  caches), the first query refreshes from GitHub even if its data is cached.
  This makes at most one bootstrap refresh attempt, costs that query's usual
  points, and still permits stale-cache fallback on failure. Other cached
  queries do not fan out into additional bootstrap requests.
- On menu refresh, RepoBar seeds the first visible repository rows from cached
  `/user/repos` pages plus cached repo-detail PR counts before live GitHub
  hydration finishes. Rows without cached PR counts stay out of that seed so
  GitHub's `open_issues_count` is never shown as an issue-only value.
- `repobar cache status --json` reports DB path, row counts, recent responses,
  and stored rate limits.
- The main menu includes a compact GitHub API Status row with a streamlined
  submenu for blockers, cooldowns, and quota groups. The submenu shows sample
  age once instead of repeating it for every resource.
- The API settings tab explains the budget actor, not only the token. GitHub core
  limits are usually shared by all tokens acting as the same user: RepoBar's
  GitHub App user token, PATs, OAuth app tokens, GitHub App user tokens, and
  `gh` CLI requests can all spend the same user budget. Creating another token
  for the same account does not create another core quota.
- `gh` CLI has elevated treatment from GitHub, so it may keep working after
  RepoBar, PAT, or OAuth requests are blocked. It still spends the normal user
  core budget first, which makes failures order-dependent across tools.
- The menu bar rate-limit meter, compact status row, submenu, and API settings
  tab share one refreshed display snapshot. Headers from actual API responses
  take precedence within their known reset window: `/rate_limit` can incorrectly
  report unused, rolling windows despite real usage, including in its own headers.
  That endpoint supplies fallback/resource inventory data, not proof that an active
  budget refilled. Search headers never replace REST core quota. Counts are
  last-observed values, not a live guarantee.
- The menu bar labels both budgets: `R` is REST core requests remaining; `G` is
  GraphQL points remaining (not requests). REST is stacked above GraphQL without an extra icon to save space. Hover for exact counts and
  units; open GitHub API Status for reset times and separate search budgets.
  `?` means unknown; `!` means an API is paused despite remaining primary quota.
- GraphQL HTTP-200 error envelopes are reported as GraphQL errors, never cached
  as successful data. Invalid legacy cache entries are bypassed on refresh.
- `repobar cache clear --json` clears persisted REST responses, GraphQL
  responses, quota observations, and rate limits.

## Discrawl-Compatible Snapshot

Use Discrawl's sharing shape as the transport contract:

- `manifest.json` at the snapshot root.
- Table data in `tables/<table>/NNNNNN.jsonl.gz`.
- Manifest table entries with `name`, `files`, `columns`, and `rows`.
- Optional `files` checksums.
- Imported data stored in SQLite.
- Freshness stored in `sync_state`.
- Schema guarded with `PRAGMA user_version`.

This means the backup is Discrawl-compatible as a Git-backed SQLite snapshot
workflow, not that GitHub data is forced into Discord table names.

Suggested GitHub tables:

- `repositories`: owner/name, visibility, archived/fork flags, stars, forks,
  open issue/PR counts, pushed/updated timestamps.
- `threads`: issues and pull requests with number, kind, state, title, author,
  labels, timestamps, draft/merged fields, URL, and raw JSON.
- `comments`: issue/PR comments and review comments.
- `timeline_events`: renamed/closed/reopened/labeled/merged events.
- `workflow_runs`: recent CI runs keyed by repository.
- `releases`: release/tag metadata.
- `sync_state`: source freshness, last import, and per-repo cursors.
- `documents_fts`: optional FTS table for issue/PR/comment search.

## Read Policy

RepoBar issue and pull request list policy:

- Use live GitHub while the request budget is healthy so fresh data wins.
- Use ETags for REST requests so repeated calls spend minimal budget.
- If GitHub is rate-limited, offline, or temporarily unavailable, read enabled
  archive databases and return the first non-empty archive result.

If live GitHub is rate-limited or offline, keep showing stale cache/archive data.
The next UI improvement is adding a visible source label such as `Cached 12m` or
`Archive 6d` on every stale row; diagnostics already log the fallback source.

Menu opens should not run `git pull`, import snapshots, or fan out live GitHub
requests. Snapshot updates belong to explicit commands, explicit settings
buttons, or a background task with a long throttle and visible status.

## Write Policy

RepoBar writes only its own cache database. Archive databases are read-only from
the menu path.

Allowed writes:

- `repobar archives update <id>` may pull/import a configured snapshot into the
  configured `importedDatabasePath`.
- A Settings button triggers the same explicit update path and persists the
  resolved local checkout path for remote-only sources.
- Future publisher tooling may create a compatible GitHub snapshot, but that is
  separate from the menubar reader.

Disallowed writes:

- Do not edit gitcrawl config.
- Do not write into gitcrawl databases.
- Do not auto-discover archive paths from other tools.
- Do not update Git snapshot repos during menu open.

## Rate-Limit Behavior

Persist:

- API response ETags and bodies.
- GraphQL response bodies.
- `X-RateLimit-Resource`, limit, remaining count, reset time, and last error.
- Per-request backoff for `403`, secondary rate limits, and `202` stats
  endpoints.

When budget is low:

- Skip background prefetch.
- Prefer archive reads for issue/PR lists.
- Keep interactive requests limited to the opened repo/submenu.
- Surface the reset time in the menu instead of showing an endless loading row.
