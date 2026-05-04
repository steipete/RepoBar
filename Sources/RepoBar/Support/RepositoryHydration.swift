import Foundation
import RepoBarCore

enum RepositoryHydration {
    static func merge(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        let lookup = Dictionary(
            detailed.map { ($0.fullName.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return repos.map { lookup[$0.fullName.lowercased()] ?? $0 }
    }
}
