import Foundation

public enum PathFormatter {
    public static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }

        let home = self.userHomeCandidates().first ?? NSString(string: "~").expandingTildeInPath
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home + path.dropFirst(1)
        }
        return NSString(string: path).expandingTildeInPath
    }

    public static func abbreviateHome(_ path: String) -> String {
        for base in self.userHomeCandidates().sorted(by: { $0.count > $1.count }) {
            if path == base {
                return "~"
            }
            if path.hasPrefix(base + "/") {
                return "~" + path.dropFirst(base.count)
            }
        }
        return NSString(string: path).abbreviatingWithTildeInPath
    }

    public static func displayString(_ path: String) -> String {
        let expanded = self.expandTilde(path)
        let resolved = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        return self.abbreviateHome(resolved)
    }

    private static func userHomeCandidates() -> [String] {
        #if os(macOS)
            let fileManagerHome = FileManager.default.homeDirectoryForCurrentUser.path
            let fileManagerHomeResolved = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        #else
            let fileManagerHome = NSHomeDirectory()
            let fileManagerHomeResolved = fileManagerHome
        #endif

        var candidates: [String] = []
        #if os(macOS)
            let user = NSUserName()
            let homeFromUser = NSHomeDirectoryForUser(user)
            if let homeFromUser, homeFromUser.isEmpty == false {
                candidates.append(homeFromUser)
            }
            if user.isEmpty == false {
                candidates.append("/Users/\(user)")
                candidates.append("/System/Volumes/Data/Users/\(user)")
            }
        #endif
        candidates.append(fileManagerHome)
        candidates.append(fileManagerHomeResolved)

        var unique: [String] = []
        var seen = Set<String>()
        for candidate in candidates where candidate.isEmpty == false {
            if seen.insert(candidate).inserted {
                unique.append(candidate)
            }
        }
        return unique
    }
}
