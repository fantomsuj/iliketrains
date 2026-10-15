import Foundation

/// Swift port of server/src/motion.ts. Both are checked against server/test/fixtures/motion-vectors.json.
public enum Motion {
    public static let minDwellMs: Double = 30_000
    public static let snapBackM: Double = 3000
    public static let snapForwardM: Double = 2000
    public static let easeTauS: Double = 1.5
    public static let maxCatchUpMps: Double = 150

    /// Dead-reckoned distance along the route at time `t` (epoch ms). Never decreases with `t`, never exceeds `maxD`.
    public static func distanceAt(_ plan: MotionPlan, _ t: EpochMs) -> Double {
        var d = plan.d0, now = plan.t0
        if t <= now { return min(d, plan.maxD) }
        for s in plan.stops {
            if s.d < d { continue }
            let overdue = s.arr <= now
            let earliest = now + ((s.d - d) / max(plan.maxSpeed, 0.1)) * 1000
            let legEnd = overdue ? now + ((s.d - d) / max(min(plan.fallbackSpeed, plan.maxSpeed), 0.1)) * 1000 : max(s.arr, earliest)
            if t < legEnd { return min(d + ((s.d - d) * (t - now)) / (legEnd - now), plan.maxD) }
            d = s.d; now = legEnd
            let leave = max(s.dep, overdue ? now + minDwellMs : now)
            if t < leave { return min(d, plan.maxD) }
            now = leave
        }
        return min(d + (min(plan.fallbackSpeed, plan.maxSpeed) * (t - now)) / 1000, plan.maxD)
    }

    public struct Smoothed: Equatable { public var d: Double; public var snapped: Bool }

    /// Ease the drawn position toward the target, never backward; large corrections snap (callers cross-fade).
    public static func smoothStep(displayed: Double, target: Double, dt: Double) -> Smoothed {
        let gap = target - displayed
        if gap < -snapBackM || gap > snapForwardM { return Smoothed(d: target, snapped: true) }
        if gap <= 0 { return Smoothed(d: displayed, snapped: false) }
        let k = 1 - exp(-dt / easeTauS)
        return Smoothed(d: displayed + min(gap * k, maxCatchUpMps * dt), snapped: false)
    }
}
