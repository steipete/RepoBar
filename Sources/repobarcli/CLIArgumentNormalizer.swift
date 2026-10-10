import Foundation
import RepoBarCore

enum CLIArgumentNormalizer {
    static func normalize(_ args: [String]) -> [String] {
        guard !args.isEmpty else { return [RepoBarRoot.commandName] }

        var normalized = args
        let invokedName = URL(fileURLWithPath: args[0]).lastPathComponent

        // Commander's argument-tail API expects the root command first. Our binary name can vary
        // (e.g. `repobarcli` when bundled inside the app), but the root stays `repobar`.
        if invokedName != RepoBarRoot.commandName {
            normalized[0] = RepoBarRoot.commandName
        } else {
            normalized[0] = invokedName
        }

        if normalized.count > 1, normalized[1] == "list" {
            normalized[1] = "repos"
        }
        if normalized.count > 1, ["pr", "prs"].contains(normalized[1]) {
            normalized[1] = "pulls"
        }
        if normalized.count > 1, ["runs", "workflow", "workflows"].contains(normalized[1]) {
            normalized[1] = "ci"
        }

        if normalized.count > 2, normalized[1] == "local" {
            let subcommand = normalized[2].lowercased()
            let mapped: String? = switch subcommand {
            case "sync": "local-sync"
            case "rebase": "local-rebase"
            case "reset": "local-reset"
            case "branches": "local-branches"
            case "worktrees": "worktrees"
            default: nil
            }
            if let mapped {
                normalized[1] = mapped
                normalized.remove(at: 2)
            }
        }

        if normalized.count > 2, normalized[1] == "open" {
            let subcommand = normalized[2].lowercased()
            let mapped: String? = switch subcommand {
            case "finder": "open-finder"
            case "terminal": "open-terminal"
            default: nil
            }
            if let mapped {
                normalized[1] = mapped
                normalized.remove(at: 2)
            }
        }

        if normalized.count > 2, normalized[1] == "settings" {
            let subcommand = normalized[2].lowercased()
            let mapped: String? = switch subcommand {
            case "show": "settings-show"
            case "set": "settings-set"
            default: nil
            }
            if let mapped {
                normalized[1] = mapped
                normalized.remove(at: 2)
            }
        }

        if normalized.count > 2, normalized[1] == "accounts" {
            let subcommand = normalized[2].lowercased()
            let mapped: String? = switch subcommand {
            case "list", "ls": "accounts-list"
            case "use", "switch": "accounts-use"
            case "remove", "rm": "accounts-remove"
            default: nil
            }
            if let mapped {
                normalized[1] = mapped
                normalized.remove(at: 2)
            }
        }

        if normalized.count > 2, normalized[1] == "archives" {
            let subcommand = normalized[2].lowercased()
            let mapped: String? = switch subcommand {
            case "list": "archives-list"
            case "status": "archives-status"
            case "validate": "archives-validate"
            case "update": "archives-update"
            case "add": "archives-add"
            case "remove", "rm": "archives-remove"
            case "enable": "archives-enable"
            case "disable": "archives-disable"
            default: nil
            }
            if let mapped {
                normalized[1] = mapped
                normalized.remove(at: 2)
            }
        }

        if normalized.count > 2, normalized[1] == "cache" {
            let subcommand = normalized[2].lowercased()
            let mapped: String? = switch subcommand {
            case "status": "cache-status"
            case "clear": "cache-clear"
            case "rate-limits", "rate-limit", "limits": "rate-limits"
            default: nil
            }
            if let mapped {
                normalized[1] = mapped
                normalized.remove(at: 2)
            }
        }

        if normalized.count > 1, ["rate-limit", "ratelimits", "limits"].contains(normalized[1]) {
            normalized[1] = "rate-limits"
        }

        return normalized
    }
}
