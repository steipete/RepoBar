import Foundation

public enum RelativeFormatter {
    public static func machineString(from date: Date, relativeTo now: Date) -> String {
        self.string(from: date, relativeTo: now, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func string(from date: Date, relativeTo now: Date, locale: Locale? = nil) -> String {
        let localizer = RepoBarLocalization.localizer(locale: locale)
        let interval = date.timeIntervalSince(now)
        let absoluteInterval = abs(interval)
        if absoluteInterval < 60 {
            return localizer.string(interval >= 0 ? "relative.future.seconds" : "relative.past.seconds", max(1, Int64(absoluteInterval.rounded())))
        }
        if absoluteInterval < 60 * 60 {
            return localizer.string(interval >= 0 ? "relative.future.minutes" : "relative.past.minutes", max(1, Int64((absoluteInterval / 60).rounded())))
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = localizer.locale
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
