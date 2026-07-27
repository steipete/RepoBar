import Foundation

public enum ReleaseFormatter {
    public static func menuLine(for release: Release, now: Date = Date()) -> String {
        let date = RelativeFormatter.string(from: release.publishedAt, relativeTo: now)
        return "\(release.name) • \(date)"
    }

    public static func releasedLabel(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        return DateFormatters.yyyyMMdd.string(from: date)
    }
}

private enum DateFormatters {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
