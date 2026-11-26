import Foundation

/// One simulated train at a moment in time: where it is, and where it was a moment earlier (for its motion tail).
public struct GhostTrain: Hashable, Sendable {
    public let corridorID: FreightCorridor.ID
    /// Departure number on its corridor, so a train keeps the same identity while it moves.
    public let departure: Int
    public let isForward: Bool
    public let coordinate: RailCoordinate
    public let tailCoordinate: RailCoordinate
    public let level: TrafficLevel
    /// Fades in after departure and out before arrival, so trains don't pop at corridor ends.
    public let opacity: Double
}

/// Turns typical-day freight counts into moving trains. Each measured corridor launches trains at an even
/// headway (24 h ÷ trains per day), alternating direction, and runs them end to end at that railroad's
/// average train speed from its STB filing (capped by the line's timetable speed). The result has the same
/// number of trains on each line as a typical day would, in made-up positions: it is a simulation, not
/// tracking, and the app labels it that way.
///
/// The simulator is a pure function of time, so it is deterministic and cheap: a frame only computes the
/// trains currently between departure and arrival on the corridors it is asked about.
public struct GhostTrainSimulator: Sendable {
    public static let secondsPerDay: TimeInterval = 86_400
    /// Used when a railroad has no STB filing.
    public static let fallbackSpeedMPH = 24.0
    /// Slowest plausible average, so short yard-speed lines don't freeze in place.
    public static let minimumSpeedMPH = 10.0

    struct Track: Sendable {
        let corridor: FreightCorridor
        /// Miles from the start of the path to each vertex.
        let cumulativeMiles: [Double]
        let totalMiles: Double
        let speedMPH: Double
        let headway: TimeInterval
        let travelTime: TimeInterval
        /// Seeded per corridor so neighbouring lines don't launch in lockstep.
        let phase: TimeInterval
    }

    let tracks: [FreightCorridor.ID: Track]

    /// - Parameter averageSpeed: a railroad's average train speed in mph, e.g. from its STB filing.
    public init(corridors: [FreightCorridor], averageSpeed: (RailOperator) -> Double?) {
        var tracks: [FreightCorridor.ID: Track] = [:]
        for corridor in corridors {
            guard let trainsPerDay = corridor.trainsPerDay, trainsPerDay > 0, corridor.path.count >= 2 else { continue }
            var cumulative: [Double] = [0]
            cumulative.reserveCapacity(corridor.path.count)
            for (a, b) in zip(corridor.path, corridor.path.dropFirst()) {
                cumulative.append(cumulative[cumulative.count - 1] + a.roughMiles(to: b))
            }
            let total = cumulative[cumulative.count - 1]
            guard total > 0 else { continue }

            var speed = averageSpeed(corridor.railroad) ?? Self.fallbackSpeedMPH
            if let limit = corridor.maxSpeedMPH, limit > 0 {
                speed = min(speed, Double(limit))
            }
            speed = max(speed, Self.minimumSpeedMPH)

            let headway = Self.secondsPerDay / trainsPerDay
            tracks[corridor.id] = Track(
                corridor: corridor,
                cumulativeMiles: cumulative,
                totalMiles: total,
                speedMPH: speed,
                headway: headway,
                travelTime: total / speed * 3_600,
                phase: Self.unitHash(corridor.id) * headway
            )
        }
        self.tracks = tracks
    }

    /// Corridors that can carry ghost trains (those with a train count).
    public var simulatedCorridorCount: Int { tracks.count }

    /// How many trains a typical day keeps on a corridor at once: trains per day × hours end to end ÷ 24.
    public func expectedTrainsOnLine(_ corridorID: FreightCorridor.ID) -> Double {
        guard let track = tracks[corridorID] else { return 0 }
        return track.travelTime / track.headway
    }

    /// Trains on the given corridors at `time` (seconds; any origin, the pattern repeats daily).
    ///
    /// - Parameters:
    ///   - corridorIDs: corridors to simulate, usually the ones drawn on screen.
    ///   - bounds: skip trains outside this box (pad it so trains don't pop in at the edges).
    ///   - tailSeconds: how far back, in simulated seconds, each train's tail starts. Trains also fade in
    ///     and out over this long at each end of their corridor.
    ///   - limit: the most trains to return. When there are more, a stable subset is kept, so the same
    ///     trains stay visible from frame to frame instead of flickering.
    public func trains(
        at time: TimeInterval,
        on corridorIDs: some Collection<FreightCorridor.ID>,
        within bounds: RailBounds? = nil,
        tailSeconds: TimeInterval = 0,
        limit: Int = .max
    ) -> [GhostTrain] {
        var result: [GhostTrain] = []
        var keepFraction = 1.0
        if limit < .max {
            let expected = corridorIDs.reduce(0.0) { $0 + expectedTrainsOnLine($1) }
            keepFraction = expected > Double(limit) ? Double(limit) / expected : 1
        }

        for id in corridorIDs {
            guard let track = tracks[id] else { continue }
            if let bounds, !track.corridor.bounds.intersects(bounds) { continue }

            for isForward in [true, false] {
                // Each direction runs every other departure, offset by half a headway.
                let interval = track.headway * 2
                let offset = track.phase + (isForward ? 0 : track.headway)
                let newest = Int(((time - offset) / interval).rounded(.down))
                let oldest = Int(((time - offset - track.travelTime) / interval).rounded(.down)) + 1
                guard oldest <= newest else { continue }

                for departure in oldest ... newest {
                    let identity = departure * 2 + (isForward ? 0 : 1)
                    if keepFraction < 1, Self.unitHash(id &* 7_919 &+ identity) >= keepFraction { continue }

                    let departed = offset + Double(departure) * interval
                    let elapsed = time - departed
                    let miles = elapsed / 3_600 * track.speedMPH
                    let tailMiles = max(0, miles - tailSeconds / 3_600 * track.speedMPH)
                    let coordinate = point(on: track, atMiles: miles, forward: isForward)
                    if let bounds, !bounds.contains(coordinate) { continue }

                    result.append(GhostTrain(
                        corridorID: id,
                        departure: identity,
                        isForward: isForward,
                        coordinate: coordinate,
                        tailCoordinate: point(on: track, atMiles: tailMiles, forward: isForward),
                        level: track.corridor.level,
                        opacity: Self.fade(elapsed: elapsed, remaining: track.travelTime - elapsed, over: tailSeconds)
                    ))
                    if result.count >= limit { return result }
                }
            }
        }
        return result
    }

    /// The coordinate `miles` along a track from its start (or from its end when running backward).
    func point(on track: Track, atMiles miles: Double, forward: Bool) -> RailCoordinate {
        let distance = min(max(forward ? miles : track.totalMiles - miles, 0), track.totalMiles)
        let path = track.corridor.path
        // Binary search for the segment containing `distance`.
        var low = 0
        var high = track.cumulativeMiles.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if track.cumulativeMiles[middle] <= distance {
                low = middle
            } else {
                high = middle
            }
        }
        let start = track.cumulativeMiles[low]
        let length = track.cumulativeMiles[high] - start
        let t = length > 0 ? (distance - start) / length : 0
        let a = path[low]
        let b = path[high]
        return RailCoordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// How many times faster than real time the simulation runs at a zoom level, chosen so an average
    /// freight train crosses about 2% of the screen height per second at any zoom. Rounded to a friendly
    /// number because the app shows it ("× 7,500").
    public static func timeScale(forLatitudeSpan span: Double) -> Double {
        let milesPerSecond = 0.02 * max(span, 0.01) * 69
        let raw = milesPerSecond * 3_600 / fallbackSpeedMPH
        let clamped = min(max(raw, 30), 12_000)
        let magnitude = pow(10, (log10(clamped)).rounded(.down))
        let steps: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 10]
        let step = steps.min { abs($0 * magnitude - clamped) < abs($1 * magnitude - clamped) } ?? 1
        return step * magnitude
    }

    static func fade(elapsed: TimeInterval, remaining: TimeInterval, over window: TimeInterval) -> Double {
        guard window > 0 else { return 1 }
        return min(1, max(0, min(elapsed, remaining) / window))
    }

    /// A stable pseudo-random number in [0, 1) for an integer (SplitMix64 finaliser).
    static func unitHash(_ value: Int) -> Double {
        var z = UInt64(bitPattern: Int64(value)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// The simulation clock. It starts at the current local time of day and advances by real elapsed time
/// multiplied by the zoom's time scale, so changing zoom changes speed without making trains jump.
public final class GhostClock {
    public private(set) var simulatedTime: TimeInterval
    private var lastTick: Date?

    public init(startingAt date: Date = Date(), calendar: Calendar = .current) {
        simulatedTime = date.timeIntervalSince(calendar.startOfDay(for: date))
    }

    /// Advances to `date`. Gaps over a quarter second (app backgrounded, paused, a dropped frame) count
    /// as one frame, so trains never leap forward.
    @discardableResult
    public func tick(to date: Date, scale: Double, isPaused: Bool = false) -> TimeInterval {
        defer { lastTick = date }
        guard !isPaused, let lastTick else { return simulatedTime }
        let elapsed = date.timeIntervalSince(lastTick)
        guard elapsed > 0 else { return simulatedTime }
        simulatedTime += min(elapsed, 0.25) * scale
        return simulatedTime
    }

    /// "6:42 PM" style label for the simulated typical-day time.
    public var timeOfDay: DateComponents {
        let seconds = Int(simulatedTime.truncatingRemainder(dividingBy: GhostTrainSimulator.secondsPerDay))
        let wrapped = seconds < 0 ? seconds + Int(GhostTrainSimulator.secondsPerDay) : seconds
        return DateComponents(hour: wrapped / 3_600, minute: (wrapped % 3_600) / 60)
    }
}
