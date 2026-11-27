import SwiftUI
import TrainsCore

/// Flighty-like palette: calm dark surfaces, one bright status colour per state.
enum Theme {
    static let background = Color(hex: "#0d1117")
    static let surface = Color(hex: "#151b23")
    static let hairline = Color.white.opacity(0.08)
    static let text = Color(hex: "#e6edf3")
    static let dim = Color(hex: "#7d8a99")
    static let onTime = Color(hex: "#3fb950")
    static let late = Color(hex: "#f0a33a")
    static let bad = Color(hex: "#f85149")
    static let noData = Color(hex: "#7d8a99")
    static let mono = Font.system(.caption, design: .monospaced)

    static func color(_ p: Punctuality) -> Color {
        switch p {
        case .onTime: return onTime
        case .late: return late
        case .veryLate, .cancelled: return bad
        case .noData: return noData
        }
    }
    static func hex(_ p: Punctuality) -> String {
        switch p {
        case .onTime: return "#3fb950"
        case .late: return "#f0a33a"
        case .veryLate, .cancelled: return "#f85149"
        case .noData: return "#7d8a99"
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

extension TrainSummary {
    var punctuality: Punctuality { Wording.punctuality(delaySec: delaySec, status: status, source: source) }
}
extension TrainDetail {
    var punctuality: Punctuality { Wording.punctuality(delaySec: delaySec, status: status, source: source) }
}
