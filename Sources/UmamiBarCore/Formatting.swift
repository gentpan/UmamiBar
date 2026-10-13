import Foundation

public func compactNumber(_ value: Double) -> String {
    let abs = Swift.abs(value)
    if abs >= 1_000_000 {
        return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
    }
    if abs >= 1_000 {
        return String(format: "%.1fK", value / 1_000).replacingOccurrences(of: ".0K", with: "K")
    }
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(format: "%.0f", value)
    }
    return String(format: "%.1f", value)
}

public func percent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

public func duration(seconds: Double) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    if m >= 60 {
        let h = m / 60
        return String(format: "%dh %dm", h, m % 60)
    }
    return String(format: "%d:%02d", m, s)
}

public func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 5 { return String(localized: "just now", bundle: .main) }
    if interval < 60 {
        return String.localizedStringWithFormat(String(localized: "%.0fs ago", bundle: .main), interval)
    }
    if interval < 3600 {
        return String.localizedStringWithFormat(String(localized: "%.0fm ago", bundle: .main), interval / 60)
    }
    if interval < 86400 {
        return String.localizedStringWithFormat(String(localized: "%.0fh ago", bundle: .main), interval / 3600)
    }
    return String.localizedStringWithFormat(String(localized: "%.0fd ago", bundle: .main), interval / 86400)
}
