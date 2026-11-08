import Foundation

extension Int64 {
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var shortDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }

    /// "Expires in 5 days" / "Expired 2 days ago".
    func expiryCountdown(now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: self, relativeTo: now)
        return self > now ? "Expires \(relative)" : "Expired \(relative)"
    }
}
