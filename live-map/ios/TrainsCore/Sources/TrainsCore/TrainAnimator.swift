import Foundation

/// Per-frame state for drawing trains: dead-reckon each plan, ease toward it, never move backward,
/// and fade a train out and back in when its position needs a big correction.
public final class TrainAnimator {
    public struct Frame: Equatable, Sendable {
        public var id: String
        public var coordinate: Coordinate
        public var bearing: Double
        public var opacity: Double
        public var distance: Double
    }

    private struct State { var shown: Double?; var opacity: Double = 0; var shape: String? }
    private var states: [String: State] = [:]
    public static let fadeInPerSecond = 2.5

    public init() {}

    /// Advance all trains to time `now` (server clock, epoch ms) after `dt` seconds of wall time.
    public func step(now: EpochMs, dt: Double, trains: [TrainSummary], lines: (String) -> RouteLine?) -> [Frame] {
        var out: [Frame] = []
        out.reserveCapacity(trains.count)
        var alive = Set<String>()
        for t in trains {
            alive.insert(t.id)
            var st = states[t.id] ?? State()
            if st.shape != t.shape { st.shown = nil; st.shape = t.shape } // rerouted: start over on the new line
            if let key = t.shape, let line = lines(key), let plan = t.plan {
                let target = Motion.distanceAt(plan, now)
                let r = Motion.smoothStep(displayed: st.shown ?? target, target: target, dt: dt)
                if r.snapped { st.opacity = 0 }
                st.shown = r.d
                st.opacity = min(1, st.opacity + dt * Self.fadeInPerSecond)
                let (c, b) = line.point(at: r.d)
                out.append(Frame(id: t.id, coordinate: c, bearing: b, opacity: st.opacity, distance: r.d))
            } else if let lat = t.lat, let lon = t.lon {
                st.opacity = min(1, st.opacity + dt * Self.fadeInPerSecond)
                out.append(Frame(id: t.id, coordinate: Coordinate(lat: lat, lon: lon), bearing: t.bearing, opacity: st.opacity, distance: t.distM))
            }
            states[t.id] = st
        }
        for id in states.keys where !alive.contains(id) { states[id] = nil }
        return out
    }

    /// The distance currently drawn for a train (for the card's progress rail), if any.
    public func shownDistance(_ id: String) -> Double? { states[id]?.shown }
}
