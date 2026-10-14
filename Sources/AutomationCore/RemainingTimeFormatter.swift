import Foundation

public enum RemainingTimeFormatter {
    public static func string(seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return nil }
        let total = Int(seconds.rounded(.up))
        let remainder = total % 60
        if total < 60 { return "\(total)s" }
        if total < 3600 { return String(format: "%dm%02ds", total / 60, remainder) }
        return String(format: "%dh%02dm%02ds", total / 3600, (total / 60) % 60, remainder)
    }
}
