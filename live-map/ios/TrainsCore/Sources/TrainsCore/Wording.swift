import Foundation

/// Status classes shared by the map, the card and the board (colour-coded like Flighty).
public enum Punctuality: String, Sendable { case onTime, late, veryLate, cancelled, noData }

public enum Wording {
    public static func punctuality(delaySec: Double?, status: TrainStatus, source: DataSource) -> Punctuality {
        if status == .cancelled { return .cancelled }
        guard source == .live, let d = delaySec else { return .noData }
        if d >= 15 * 60 { return .veryLate }
        if d >= 5 * 60 { return .late }
        return .onTime
    }

    /// "On time", "4 min late", "2 min early".
    public static func lateness(_ delaySec: Double?) -> String? {
        guard let s = delaySec else { return nil }
        let m = Int((s / 60).rounded())
        if abs(m) <= 1 { return "On time" }
        return m > 0 ? "\(m) min late" : "\(-m) min early"
    }

    /// Big glanceable countdown: "now", "4 min", "1 h 12 m".
    public static func countdown(to eta: EpochMs, now: EpochMs) -> String {
        let s = (eta - now) / 1000
        if s < 45 { return "now" }
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60) m"
    }

    /// One-line headline for the train card, with a little personality.
    public static func headline(_ t: TrainDetail, now: EpochMs) -> String {
        switch t.status {
        case .cancelled: return "Cancelled. Sorry, this one isn't coming."
        case .scheduled:
            if let dep = t.stops.first?.estDep ?? t.stops.first?.schDep { return "Leaves \(t.origin) in \(countdown(to: dep, now: now))" }
            return "Not moving yet"
        case .completed: return "Arrived. That's a wrap."
        case .atStation: return "Stopped at \(t.next?.name ?? "a station")"
        case .enroute:
            guard let n = t.next else { return "On the move" }
            if let eta = n.eta { return "\(n.name) in \(countdown(to: eta, now: now))" }
            return "Heading to \(n.name)"
        }
    }

    /// How the position was found, for the small badge on the card.
    public static func fixLabel(_ fix: PositionFix, source: DataSource) -> String {
        if source == .scheduled { return "Scheduled" }
        switch fix {
        case .gps: return "Live GPS"
        case .predicted: return "Live times"
        case .timetable: return "Scheduled"
        }
    }

    public static func trainLabel(operator op: Operator, routeName: String, number: String) -> String {
        op == .amtrak ? "\(routeName.isEmpty ? "Amtrak" : routeName) \(number)" : "\(op.displayName) \(number)"
    }

    /// Seat availability for a car, in rider terms.
    public static func loading(_ code: String) -> String {
        switch code {
        case "EMPTY": return "Plenty of seats"
        case "MANY_SEATS": return "Many seats"
        case "FEW_SEATS": return "Few seats"
        case "STANDING_ROOM_ONLY": return "Standing room"
        case "FULL": return "Full"
        default: return "No sensor"
        }
    }

    /// "4 min late" / "3 min early" / "on time" for a whole-minute delay.
    public static func minutes(_ m: Int?) -> String {
        guard let m else { return "—" }
        if abs(m) <= 1 { return "on time" }
        return m > 0 ? "\(m) min late" : "\(-m) min early"
    }

    /// "2 extra cars" / "1 car short" when the train runs a different length than scheduled.
    public static func lengthNote(running: Int?, scheduled: Int?) -> String? {
        guard let r = running, let s = scheduled, r != s else { return nil }
        let n = abs(r - s)
        return r > s ? "\(n) extra car\(n == 1 ? "" : "s")" : "\(n) car\(n == 1 ? "" : "s") short"
    }
}
