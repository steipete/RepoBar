import Foundation

enum StatValueFormatter {
    static func compact(_ value: Int) -> String {
        if value < 1000 {
            return "\(value)"
        }
        if value < 10000 {
            let short = self.oneDecimal(value, divisor: 1000)
            return "\(short)K"
        }
        if value < 1_000_000 {
            let thousands = self.rounded(value, divisor: 1000)
            return thousands >= 1000 ? "1M" : "\(thousands)K"
        }
        if value < 10_000_000 {
            let short = self.oneDecimal(value, divisor: 1_000_000)
            return "\(short)M"
        }
        let millions = self.rounded(value, divisor: 1_000_000)
        return millions >= 1000 ? "999M" : "\(millions)M"
    }

    private static func rounded(_ value: Int, divisor: Int) -> Int {
        // Round half up without an intermediate `value + divisor/2` that could
        // overflow near Int.max: compare the remainder against half the divisor.
        value / divisor + (value % divisor * 2 >= divisor ? 1 : 0)
    }

    private static func oneDecimal(_ value: Int, divisor: Double) -> String {
        let scaled = Double(value) / divisor
        let formatted = String(format: "%.1f", scaled)
        if formatted.hasSuffix(".0") {
            return String(formatted.dropLast(2))
        }
        return formatted
    }
}
