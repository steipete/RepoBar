import Foundation

public enum RelativeFormatter {
    public static func string(from date: Date, relativeTo now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        let absoluteInterval = abs(interval)
        if absoluteInterval < 60 {
            return self.format(value: max(1, Int(absoluteInterval.rounded())), unit: "sec.", isFuture: interval >= 0)
        }
        if absoluteInterval < 60 * 60 {
            return self.format(value: max(1, Int((absoluteInterval / 60).rounded())), unit: "min.", isFuture: interval >= 0)
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func format(value: Int, unit: String, isFuture: Bool) -> String {
        isFuture ? "in \(value) \(unit)" : "\(value) \(unit) ago"
    }
}
