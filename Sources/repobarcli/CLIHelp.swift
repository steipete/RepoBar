import Foundation

enum HelpTarget: String {
    case root
    case repos
    case repo
    case issues
    case pulls
    case releases
    case ci
    case discussions
    case tags
    case branches
    case contributors
    case commits
    case activity
    case local
    case localSync
    case localRebase
    case localReset
    case localBranches
    case worktrees
    case openFinder
    case openTerminal
    case checkout
    case refresh
    case contributions
    case changelog
    case markdown
    case pin
    case unpin
    case hide
    case show
    case archivesList
    case archivesStatus
    case archivesValidate
    case archivesUpdate
    case archivesAdd
    case archivesRemove
    case archivesEnable
    case archivesDisable
    case rateLimits
    case referenceTranslate
    case cacheStatus
    case cacheClear
    case settingsShow
    case settingsSet
    case login
    case logout
    case importGHToken
    case status

    static func from(argv: [String]) -> HelpTarget? {
        guard !argv.isEmpty else { return .root }

        if argv.count > 1, argv[1] == "help" {
            return HelpTarget.from(tokens: Array(argv.dropFirst(2)))
        }

        guard argv.contains("--help") || argv.contains("-h") else { return nil }

        let tokens = argv.dropFirst().filter { !$0.hasPrefix("-") }
        return HelpTarget.from(tokens: tokens)
    }

    private static func from(tokens: [String]) -> HelpTarget {
        let normalized = CLIArgumentNormalizer.normalize([RepoBarRoot.commandName] + tokens)
        let target = normalized.dropFirst().first
        return HelpTarget.from(token: target)
    }

    private static func from(token: String?) -> HelpTarget {
        guard let token else { return .root }

        switch token {
        case ReposCommand.commandName:
            return .repos
        case RepoCommand.commandName:
            return .repo
        case IssuesCommand.commandName:
            return .issues
        case PullsCommand.commandName:
            return .pulls
        case ReleasesCommand.commandName:
            return .releases
        case CICommand.commandName:
            return .ci
        case DiscussionsCommand.commandName:
            return .discussions
        case TagsCommand.commandName:
            return .tags
        case BranchesCommand.commandName:
            return .branches
        case ContributorsCommand.commandName:
            return .contributors
        case CommitsCommand.commandName:
            return .commits
        case ActivityCommand.commandName:
            return .activity
        case LocalProjectsCommand.commandName:
            return .local
        case LocalSyncCommand.commandName:
            return .localSync
        case LocalRebaseCommand.commandName:
            return .localRebase
        case LocalResetCommand.commandName:
            return .localReset
        case LocalBranchesCommand.commandName:
            return .localBranches
        case WorktreesCommand.commandName:
            return .worktrees
        case OpenFinderCommand.commandName:
            return .openFinder
        case OpenTerminalCommand.commandName:
            return .openTerminal
        case CheckoutCommand.commandName:
            return .checkout
        case RefreshCommand.commandName:
            return .refresh
        case ContributionsCommand.commandName:
            return .contributions
        case ChangelogCommand.commandName:
            return .changelog
        case MarkdownCommand.commandName:
            return .markdown
        case PinCommand.commandName:
            return .pin
        case UnpinCommand.commandName:
            return .unpin
        case HideCommand.commandName:
            return .hide
        case ShowCommand.commandName:
            return .show
        case ArchivesListCommand.commandName:
            return .archivesList
        case ArchivesStatusCommand.commandName:
            return .archivesStatus
        case ArchivesValidateCommand.commandName:
            return .archivesValidate
        case ArchivesUpdateCommand.commandName:
            return .archivesUpdate
        case ArchivesAddCommand.commandName:
            return .archivesAdd
        case ArchivesRemoveCommand.commandName:
            return .archivesRemove
        case ArchivesEnableCommand.commandName:
            return .archivesEnable
        case ArchivesDisableCommand.commandName:
            return .archivesDisable
        case RateLimitsCommand.commandName:
            return .rateLimits
        case ReferenceTranslateCommand.commandName:
            return .referenceTranslate
        case CacheStatusCommand.commandName:
            return .cacheStatus
        case CacheClearCommand.commandName:
            return .cacheClear
        case SettingsShowCommand.commandName:
            return .settingsShow
        case SettingsSetCommand.commandName:
            return .settingsSet
        case LoginCommand.commandName:
            return .login
        case LogoutCommand.commandName:
            return .logout
        case ImportGHTokenCommand.commandName:
            return .importGHToken
        case StatusCommand.commandName:
            return .status
        default:
            return .root
        }
    }
}

private func rootHelpText() -> String {
    """
    repobar - list repositories by activity, issues, PRs, stars

    Usage:
      repobar [repos] [--limit N] [--age DAYS] [--release] [--event] [--forks] [--archived] [--scope VAL] [--filter VAL]
              [--pinned-only] [--only-with VAL] [--owner LOGIN] [--mine] [--json] [--plain] [--sort KEY]
      repobar repo <owner/name> [--traffic] [--heatmap] [--release] [--json] [--plain]
      repobar issues <owner/name> [--limit N] [--json] [--plain]
      repobar pulls <owner/name> [--limit N] [--json] [--plain]
      repobar releases <owner/name> [--limit N] [--json] [--plain]
      repobar ci <owner/name> [--limit N] [--json] [--plain]
      repobar discussions <owner/name> [--limit N] [--json] [--plain]
      repobar tags <owner/name> [--limit N] [--json] [--plain]
      repobar branches <owner/name> [--limit N] [--json] [--plain]
      repobar contributors <owner/name> [--limit N] [--json] [--plain]
      repobar commits [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--json] [--plain]
      repobar activity [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--include-repos] [--json] [--plain]
      repobar local [--root PATH] [--depth N] [--sync] [--limit N] [--json] [--plain]
      repobar local sync <path|owner/name> [--json] [--plain]
      repobar local rebase <path|owner/name> [--json] [--plain]
      repobar local reset <path|owner/name> [--yes] [--json] [--plain]
      repobar local branches <path|owner/name> [--json] [--plain]
      repobar worktrees <path|owner/name> [--json] [--plain]
      repobar open finder <path|owner/name>
      repobar open terminal <path|owner/name>
      repobar checkout <owner/name> [--root PATH] [--destination PATH] [--open] [--json] [--plain]
      repobar refresh [--json] [--plain]
      repobar contributions [--login USER] [--json] [--plain]
      repobar changelog [path] [--release TAG] [--json] [--plain]
      repobar markdown <path> [--width N] [--no-wrap] [--plain] [--no-color]
      repobar pin <owner/name> [--json] [--plain]
      repobar unpin <owner/name> [--json] [--plain]
      repobar hide <owner/name> [--json] [--plain]
      repobar show <owner/name> [--json] [--plain]
      repobar archives list [--json] [--plain]
      repobar archives status [name] [--json] [--plain]
      repobar archives validate [name] [--json] [--plain]
      repobar archives update <name> [--json] [--plain]
      repobar archives add <repo|url|path|name> [--repo PATH|REPO|URL] [--remote URL] [--branch BRANCH] [--db PATH] [--json] [--plain]
      repobar archives remove <name> [--json] [--plain]
      repobar archives enable <name> [--json] [--plain]
      repobar archives disable <name> [--json] [--plain]
      repobar rate-limits [--limit N] [--json] [--plain]
      repobar reference-translate <text> [--json] [--plain]
      repobar cache status [--limit N] [--json] [--plain]
      repobar cache clear [--json] [--plain]
      repobar settings show [--json] [--plain]
      repobar settings set <key> <value> [--json] [--plain]
      repobar login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]
      repobar logout
      repobar import-gh-token [--host URL]
      repobar status [--json]

    Options:
      --limit N    Max repositories to fetch (default: all accessible)
      --age DAYS   Only show repos with activity in the last N days (default: 365)
      --release    Include latest release tag and date
      --event      Show activity event column (hidden by default)
      --forks      Include forked repositories (hidden by default)
      --archived   Include archived repositories (hidden by default)
      --scope      Scope repositories (values: all, pinned, hidden)
      --filter     Filter repositories (values: all, work, issues, prs)
      --pinned-only  Only list pinned repositories from settings (alias for --scope pinned)
      --only-with  Only show repos that have issues and/or PRs (values: work, issues, prs)
      --owner      Only show repositories owned by the given login (repeatable, comma-separated)
      --mine       Only show repositories owned by the authenticated user
      --json       Output JSON instead of formatted table
      --plain      Plain table output (no links, no colors, no URLs)
      --sort KEY   Sort by activity, issues, prs, stars, repo, or event
      --no-color   Disable color output
      -h, --help   Show help
    """
}

func printHelp(_ target: HelpTarget) {
    let text = switch target {
    case .root:
        rootHelpText()
    case .repos:
        """
        repobar repos - list repositories

        Usage:
          repobar repos [--limit N] [--age DAYS] [--release] [--event] [--forks] [--archived] [--scope VAL] [--filter VAL]
                        [--pinned-only] [--only-with VAL] [--owner LOGIN] [--mine] [--json] [--plain] [--sort KEY]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --release    Include latest release tag and date
          --event      Show activity event column (hidden by default)
          --forks      Include forked repositories (hidden by default)
          --archived   Include archived repositories (hidden by default)
          --scope      Scope repositories (values: all, pinned, hidden)
          --filter     Filter repositories (values: all, work, issues, prs)
          --pinned-only  Only list pinned repositories from settings (alias for --scope pinned)
          --only-with  Only show repos that have issues and/or PRs (values: work, issues, prs)
          --owner      Only show repositories owned by the given login (repeatable, comma-separated)
          --mine       Only show repositories owned by the authenticated user
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
        """
    case .repo:
        """
        repobar repo - fetch a repository summary

        Usage:
          repobar repo <owner/name> [--traffic] [--heatmap] [--release] [--json] [--plain]

        Options:
          --traffic   Include traffic stats
          --heatmap   Include commit activity heatmap
          --release   Include latest release data
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .issues:
        """
        repobar issues - list open issues

        Usage:
          repobar issues <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max issues to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .pulls:
        """
        repobar pulls - list open pull requests

        Usage:
          repobar pulls <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max PRs to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .releases:
        """
        repobar releases - list recent releases

        Usage:
          repobar releases <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max releases to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .ci:
        """
        repobar ci - list workflow runs

        Usage:
          repobar ci <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max workflow runs to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .discussions:
        """
        repobar discussions - list recent discussions

        Usage:
          repobar discussions <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max discussions to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .tags:
        """
        repobar tags - list recent tags

        Usage:
          repobar tags <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max tags to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .branches:
        """
        repobar branches - list recent branches

        Usage:
          repobar branches <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max branches to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .contributors:
        """
        repobar contributors - list top contributors

        Usage:
          repobar contributors <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max contributors to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .commits:
        """
        repobar commits - list recent commits

        Usage:
          repobar commits [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--json] [--plain]

        Options:
          --limit N   Max commits to fetch (default: 20)
          --scope     Activity scope (values: all, my)
          --login     GitHub login for global commits
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .activity:
        """
        repobar activity - list recent activity

        Usage:
          repobar activity [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--include-repos] [--json] [--plain]

        Options:
          --limit N       Max events to fetch (default: 20)
          --scope         Activity scope (values: all, my)
          --login         GitHub login for global activity
          --include-repos Merge cached repository activity like the menu profile submenu
          --json          Output JSON instead of formatted text
          --plain         Plain output (no links, no colors)
          --no-color      Disable color output
        """
    case .local:
        """
        repobar local - scan local projects

        Usage:
          repobar local [--root PATH] [--depth N] [--sync] [--limit N] [--json] [--plain]

        Options:
          --root PATH  Project folder to scan (defaults to settings value, then ~/Projects)
          --depth N    Max scan depth (default: 2)
          --sync       Fast-forward pull clean repos that are behind
          --limit N    Limit processed repos (default: all)
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --no-color   Disable color output
        """
    case .localSync:
        """
        repobar local sync - sync a local repository

        Usage:
          repobar local sync <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .localRebase:
        """
        repobar local rebase - rebase a local repository onto upstream

        Usage:
          repobar local rebase <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .localReset:
        """
        repobar local reset - hard reset a local repository to upstream

        Usage:
          repobar local reset <path|owner/name> [--yes] [--json] [--plain]

        Options:
          --yes       Skip confirmation prompt
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .localBranches:
        """
        repobar local branches - list local branches

        Usage:
          repobar local branches <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .worktrees:
        """
        repobar worktrees - list local worktrees

        Usage:
          repobar worktrees <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .openFinder:
        """
        repobar open finder - open a local repository in Finder

        Usage:
          repobar open finder <path|owner/name>
        """
    case .openTerminal:
        """
        repobar open terminal - open a local repository in Terminal

        Usage:
          repobar open terminal <path|owner/name>
        """
    case .checkout:
        """
        repobar checkout - clone a repository into the local projects folder

        Usage:
          repobar checkout <owner/name> [--root PATH] [--destination PATH] [--open] [--json] [--plain]

        Options:
          --root PATH        Root folder to clone into (defaults to Local Projects root)
          --destination PATH Explicit destination folder
          --open             Open Finder after checkout
          --json             Output JSON instead of formatted text
          --plain            Plain output (no links, no colors)
          --no-color         Disable color output
        """
    case .refresh:
        """
        repobar refresh - refresh pinned repositories

        Usage:
          repobar refresh [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .contributions:
        """
        repobar contributions - fetch contribution heatmap

        Usage:
          repobar contributions [--login USER] [--json] [--plain]

        Options:
          --login USER  GitHub login (defaults to current user)
          --json        Output JSON instead of formatted text
          --plain       Plain output (no links, no colors)
          --no-color    Disable color output
        """
    case .changelog:
        """
        repobar changelog - parse a changelog and summarize entries

        Usage:
          repobar changelog [path] [--release TAG] [--json] [--plain]

        Options:
          --release TAG  Release tag to compare against (ex: v1.0.0)
          --json         Output JSON instead of formatted text
          --plain        Plain output (no links, no colors)
          --no-color     Disable color output
        """
    case .markdown:
        """
        repobar markdown - render markdown to ANSI text

        Usage:
          repobar markdown <path> [--width N] [--no-wrap] [--plain] [--no-color]

        Options:
          --width N   Wrap at N columns (defaults to terminal width)
          --no-wrap   Disable line wrapping
          --plain     Plain output (strip ANSI styles)
          --no-color  Disable color output
        """
    case .referenceTranslate:
        """
        repobar reference-translate - translate copied text into a GitHub reference query

        Usage:
          repobar reference-translate <text> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output
          --no-color  Disable color output
        """
    case .pin:
        """
        repobar pin - pin a repository

        Usage:
          repobar pin <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .unpin:
        """
        repobar unpin - unpin a repository

        Usage:
          repobar unpin <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .hide:
        """
        repobar hide - hide a repository

        Usage:
          repobar hide <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .show:
        """
        repobar show - show a hidden repository

        Usage:
          repobar show <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .archivesList:
        """
        repobar archives list - list GitHub archive sources

        Usage:
          repobar archives list [--json] [--plain]
        """
    case .archivesStatus:
        """
        repobar archives status - show GitHub archive source status

        Usage:
          repobar archives status [name] [--json] [--plain]
        """
    case .archivesValidate:
        """
        repobar archives validate - validate GitHub archive source configuration

        Usage:
          repobar archives validate [name] [--json] [--plain]
        """
    case .archivesUpdate:
        """
        repobar archives update - pull and import a GitHub archive snapshot

        Usage:
          repobar archives update <name> [--json] [--plain]
        """
    case .archivesAdd:
        """
        repobar archives add - add a GitHub archive source

        Usage:
          repobar archives add <repo|url|path|name> [--repo PATH|REPO|URL] [--remote URL] [--branch BRANCH] [--db PATH] [--json] [--plain]
        """
    case .archivesRemove:
        """
        repobar archives remove - remove a GitHub archive source

        Usage:
          repobar archives remove <name> [--json] [--plain]
        """
    case .archivesEnable:
        """
        repobar archives enable - enable a GitHub archive source

        Usage:
          repobar archives enable <name> [--json] [--plain]
        """
    case .archivesDisable:
        """
        repobar archives disable - disable a GitHub archive source

        Usage:
          repobar archives disable <name> [--json] [--plain]
        """
    case .cacheStatus:
        """
        repobar cache status - show persistent cache status

        Usage:
          repobar cache status [--limit N] [--json] [--plain]
        """
    case .cacheClear:
        """
        repobar cache clear - clear persistent cache

        Usage:
          repobar cache clear [--json] [--plain]
        """
    case .rateLimits:
        """
        repobar rate-limits - show GitHub rate-limit state

        Usage:
          repobar rate-limits [--limit N] [--json] [--plain]

        Options: --limit N, --json, --plain, --no-color
        """
    case .settingsShow:
        """
        repobar settings show - show current settings

        Usage:
          repobar settings show [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .settingsSet:
        """
        repobar settings set - update a settings value

        Usage:
          repobar settings set <key> <value> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .login:
        """
        repobar login - sign in via browser OAuth

        Usage:
          repobar login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]
        """
    case .logout:
        """
        repobar logout - clear stored credentials

        Usage:
          repobar logout
        """
    case .importGHToken:
        """
        repobar import-gh-token - import token from GitHub CLI (gh)

        Usage:
          repobar import-gh-token [--host URL]

        Imports the authentication token from GitHub CLI (gh) into RepoBar.
        This is useful for SSO-enabled organizations where you've already
        authorized the gh CLI but need to use that same access in RepoBar.

        Options:
          --host URL   GitHub host to import from (defaults to current settings)

        Prerequisites:
          - GitHub CLI must be installed (brew install gh)
          - You must be logged in via gh (gh auth login)
          - Your gh token should have SSO authorization for your org
        """
    case .status:
        """
        repobar status - show login state

        Usage:
          repobar status [--json]
        """
    }
    cliPrint(localizedHelp(text))
}

private func localizedHelp(_ text: String) -> String {
    guard CLILocalizer().locale.language.languageCode?.identifier == "tr" else {
        return text
    }

    return text
        .replacingOccurrences(of: "Usage:", with: "Kullanım:")
        .replacingOccurrences(of: "Options:", with: "Seçenekler:")
        .replacingOccurrences(of: "Prerequisites:", with: "Ön koşullar:")
        .replacingOccurrences(
            of: "repobar - list repositories by activity, issues, PRs, stars",
            with: "repobar - depoları etkinlik, sorunlar, PR'ler ve yıldızlara göre listele"
        )
        .replacingOccurrences(of: " - show ", with: " - göster: ")
        .replacingOccurrences(of: " - add ", with: " - ekle: ")
        .replacingOccurrences(of: " - remove ", with: " - kaldır: ")
        .replacingOccurrences(of: " - enable ", with: " - etkinleştir: ")
        .replacingOccurrences(of: " - disable ", with: " - devre dışı bırak: ")
        .replacingOccurrences(of: " - clear ", with: " - temizle: ")
        .replacingOccurrences(of: "Show help", with: "Yardımı göster")
        .replacingOccurrences(of: "Disable color output", with: "Renkli çıktıyı devre dışı bırak")
        .replacingOccurrences(of: "Output JSON instead of formatted text", with: "Biçimlendirilmiş metin yerine JSON çıktısı ver")
        .replacingOccurrences(of: "Plain output (no links, no colors)", with: "Düz çıktı (bağlantı ve renk yok)")
}
