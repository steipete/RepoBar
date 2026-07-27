import Foundation

enum RepositoryErrorClassifier {
    static func isNonCriticalMenuWarning(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("generating repository stats") {
            return true
        }
        if lower.contains("generating stats for this repo") {
            return true
        }
        if lower.contains("http 202"), lower.contains("stats") {
            return true
        }
        return false
    }
}
