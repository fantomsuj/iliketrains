import Foundation

/// How busy a stretch of freight track is on a typical day, from FRA crossing-inventory counts.
public enum TrafficLevel: Int, Comparable, CaseIterable, Sendable {
    case unmeasured = -1
    case light
    case moderate
    case busy
    case heavy
    case veryHeavy
    case extreme

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Levels are bands between consecutive `bounds` (trains per day), lowest first.
    public init(trainsPerDay: Double?, bounds: [Double]) {
        guard let trainsPerDay else {
            self = .unmeasured
            return
        }
        let band = bounds.filter { trainsPerDay >= $0 }.count
        self = TrafficLevel(rawValue: min(band, TrafficLevel.extreme.rawValue)) ?? .extreme
    }

    public var label: String {
        switch self {
        case .unmeasured: "No count"
        case .light: "Light"
        case .moderate: "Moderate"
        case .busy: "Busy"
        case .heavy: "Heavy"
        case .veryHeavy: "Very heavy"
        case .extreme: "Extreme"
        }
    }
}

/// A run of one railroad's main line with a fairly even typical-day train count.
public struct FreightCorridor: Identifiable, Hashable, Sendable {
    public let id: Int
    public let railroad: RailOperator
    /// Median freight trains a day (through trains minus passenger and transit trains) at the public
    /// crossings along this run; nil if none report.
    public let trainsPerDay: Double?
    public let maxSpeedMPH: Int?
    public let mainTracks: Int?
    /// How many crossings the count is drawn from. Zero means it was filled in from neighbouring track.
    public let crossingCount: Int
    public let level: TrafficLevel
    /// Where the corridor runs, e.g. "Chicago, IL – Galesburg, IL" or "40 mi west of Denver, CO".
    public let place: String?
    public let path: [RailCoordinate]
    public let bounds: RailBounds

    public init(
        id: Int,
        railroad: RailOperator,
        trainsPerDay: Double?,
        maxSpeedMPH: Int?,
        mainTracks: Int?,
        crossingCount: Int,
        level: TrafficLevel,
        place: String? = nil,
        path: [RailCoordinate]
    ) {
        self.id = id
        self.railroad = railroad
        self.trainsPerDay = trainsPerDay
        self.maxSpeedMPH = maxSpeedMPH
        self.mainTracks = mainTracks
        self.crossingCount = crossingCount
        self.level = level
        self.place = place
        self.path = path
        self.bounds = RailBounds(path)
    }

    /// Track length, in miles, along the simplified path.
    public var miles: Double {
        zip(path, path.dropFirst()).reduce(0.0) { total, pair in total + pair.0.roughMiles(to: pair.1) }
    }

    /// Shortest distance in miles from `point` to this corridor's track.
    public func distanceMiles(to point: RailCoordinate) -> Double {
        guard path.count > 1 else { return path.first.map { $0.roughMiles(to: point) } ?? .infinity }
        return zip(path, path.dropFirst())
            .map { point.roughMiles(toSegmentFrom: $0.0, to: $0.1) }
            .min() ?? .infinity
    }
}

/// A rail intermodal ramp where containers or highway trailers move between trucks and trains.
public struct IntermodalTerminal: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let city: String
    public let state: String
    public let port: String?
    /// Railroads as the source lists them, e.g. "BNSF, UP via OYLO".
    public let operatorsDescription: String
    public let railroads: [RailOperator]
    public let handlesTrailers: Bool
    public let handlesContainers: Bool
    public let coordinate: RailCoordinate

    public init(
        id: String,
        name: String,
        city: String,
        state: String,
        port: String?,
        operatorsDescription: String,
        railroads: [RailOperator],
        handlesTrailers: Bool,
        handlesContainers: Bool,
        coordinate: RailCoordinate
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.state = state
        self.port = port
        self.operatorsDescription = operatorsDescription
        self.railroads = railroads
        self.handlesTrailers = handlesTrailers
        self.handlesContainers = handlesContainers
        self.coordinate = coordinate
    }

    public var place: String { [city, state].filter { !$0.isEmpty }.joined(separator: ", ") }

    public var equipmentLabel: String {
        switch (handlesContainers, handlesTrailers) {
        case (true, true): "Containers and trailers"
        case (true, false): "Containers"
        case (false, true): "Trailers"
        case (false, false): "Intermodal"
        }
    }
}

/// One of a railroad's ten largest yards, with how long cars sat there on average that week.
public struct YardDwell: Identifiable, Hashable, Sendable {
    public let railroad: RailOperator
    public let name: String
    /// Approximate (city-level) location; the STB filings name terminals but do not locate them.
    public let coordinate: RailCoordinate
    public let dwellHours: Double

    public var id: String { "\(railroad.rawValue)-\(name)" }

    public init(railroad: RailOperator, name: String, coordinate: RailCoordinate, dwellHours: Double) {
        self.railroad = railroad
        self.name = name
        self.coordinate = coordinate
        self.dwellHours = dwellHours
    }
}

/// A Class I railroad's weekly service filing to the Surface Transportation Board.
public struct RailroadServiceReport: Identifiable, Hashable, Sendable {
    public struct TrainSpeed: Hashable, Sendable {
        public let trainType: String
        public let mph: Double

        public init(trainType: String, mph: Double) {
            self.trainType = trainType
            self.mph = mph
        }
    }

    public let railroad: RailOperator
    public let systemSpeedMPH: Double?
    /// Average speed by train type, fastest first, excluding the system average.
    public let speeds: [TrainSpeed]
    public let systemDwellHours: Double
    public let carsOnline: Int
    public let trainsHeldPerDay: Double
    public let yards: [YardDwell]

    public var id: RailOperator { railroad }

    public init(
        railroad: RailOperator,
        systemSpeedMPH: Double?,
        speeds: [TrainSpeed],
        systemDwellHours: Double,
        carsOnline: Int,
        trainsHeldPerDay: Double,
        yards: [YardDwell]
    ) {
        self.railroad = railroad
        self.systemSpeedMPH = systemSpeedMPH
        self.speeds = speeds
        self.systemDwellHours = systemDwellHours
        self.carsOnline = carsOnline
        self.trainsHeldPerDay = trainsHeldPerDay
        self.yards = yards
    }

    public var slowestYard: YardDwell? { yards.max { $0.dwellHours < $1.dwellHours } }
}

/// National weekly carload and intermodal totals.
public struct FreightVolumeReport: Hashable, Sendable {
    public struct Figure: Hashable, Sendable {
        public let count: Int
        /// Percent change versus the same week a year earlier.
        public let changePercent: Double

        public init(count: Int, changePercent: Double) {
            self.count = count
            self.changePercent = changePercent
        }
    }

    public struct Commodity: Identifiable, Hashable, Sendable {
        public let name: String
        public let carloads: Int
        public let changePercent: Double

        public var id: String { name }

        public init(name: String, carloads: Int, changePercent: Double) {
            self.name = name
            self.carloads = carloads
            self.changePercent = changePercent
        }
    }

    public let week: Int
    public let weekEnded: ReportDate
    public let carloads: Figure
    public let intermodalUnits: Figure
    public let totalTraffic: Figure
    /// Largest first.
    public let commodities: [Commodity]

    public init(
        week: Int,
        weekEnded: ReportDate,
        carloads: Figure,
        intermodalUnits: Figure,
        totalTraffic: Figure,
        commodities: [Commodity]
    ) {
        self.week = week
        self.weekEnded = weekEnded
        self.carloads = carloads
        self.intermodalUnits = intermodalUnits
        self.totalTraffic = totalTraffic
        self.commodities = commodities
    }
}

/// Where a piece of the freight atlas came from, shown wherever its data appears.
public struct FreightDataSource: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let publisher: String
    public let url: URL?
    public let asOf: String
    public let detail: String

    public init(id: String, name: String, publisher: String, url: URL?, asOf: String, detail: String) {
        self.id = id
        self.name = name
        self.publisher = publisher
        self.url = url
        self.asOf = asOf
        self.detail = detail
    }
}

/// A calendar date from a report, kept as plain components so time zones can't shift it a day.
public struct ReportDate: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "2026-11-13".
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1 ... 12).contains(parts[1]), (1 ... 31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// "Nov 13".
    public var shortLabel: String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[month - 1]) \(day)"
    }
}

/// Everything public about U.S. freight rail that the map can show: how busy each main line is on a
/// typical day, where the intermodal ramps are, and how each Class I railroad ran last week.
public struct FreightAtlas: Sendable {
    public let corridors: [FreightCorridor]
    public let terminals: [IntermodalTerminal]
    public let serviceWeekEnded: ReportDate?
    public let service: [RailroadServiceReport]
    public let volume: FreightVolumeReport?
    public let sources: [FreightDataSource]
    /// Lower bounds, in trains per day, of `TrafficLevel.moderate` and up.
    public let levelBounds: [Double]

    public init(
        corridors: [FreightCorridor],
        terminals: [IntermodalTerminal],
        serviceWeekEnded: ReportDate?,
        service: [RailroadServiceReport],
        volume: FreightVolumeReport?,
        sources: [FreightDataSource],
        levelBounds: [Double]
    ) {
        self.corridors = corridors
        self.terminals = terminals
        self.serviceWeekEnded = serviceWeekEnded
        self.service = service
        self.volume = volume
        self.sources = sources
        self.levelBounds = levelBounds
    }

    public var yards: [YardDwell] { service.flatMap(\.yards) }

    public func service(for railroad: RailOperator) -> RailroadServiceReport? {
        service.first { $0.railroad == railroad }
    }

    public func source(_ id: String) -> FreightDataSource? {
        sources.first { $0.id == id }
    }

    /// Measured corridors, busiest first.
    public func busiestCorridors(limit: Int, railroad: RailOperator? = nil) -> [FreightCorridor] {
        corridors
            .filter { $0.trainsPerDay != nil && (railroad == nil || $0.railroad == railroad) }
            .sorted { ($0.trainsPerDay ?? 0) > ($1.trainsPerDay ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    /// The corridor whose track passes closest to `point`, if any is within `maxMiles`.
    public func nearestCorridor(
        to point: RailCoordinate,
        within maxMiles: Double,
        among candidates: [FreightCorridor]? = nil
    ) -> FreightCorridor? {
        let pad = maxMiles / 50
        return (candidates ?? corridors)
            .filter { $0.bounds.padded(by: pad).contains(point) }
            .map { ($0, $0.distanceMiles(to: point)) }
            .filter { $0.1 <= maxMiles }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Trains-per-day range of a level, e.g. "15–30".
    public func rangeLabel(for level: TrafficLevel) -> String {
        guard level != .unmeasured else { return "No count" }
        let lower: Double? = level.rawValue == 0 ? 0 : levelBounds[safe: level.rawValue - 1]
        let upper: Double? = levelBounds[safe: level.rawValue]
        switch (lower, upper) {
        case let (lower?, upper?): return "\(Int(lower))–\(Int(upper))"
        case let (lower?, nil): return "\(Int(lower))+"
        default: return "—"
        }
    }
}

/// A latitude/longitude box, used to skip map work for things off screen.
public struct RailBounds: Hashable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    public init(_ coordinates: [RailCoordinate]) {
        self.init(
            minLatitude: coordinates.map(\.latitude).min() ?? 0,
            maxLatitude: coordinates.map(\.latitude).max() ?? 0,
            minLongitude: coordinates.map(\.longitude).min() ?? 0,
            maxLongitude: coordinates.map(\.longitude).max() ?? 0
        )
    }

    /// The box around a map region's centre and span.
    public init(center: RailCoordinate, latitudeDelta: Double, longitudeDelta: Double) {
        self.init(
            minLatitude: center.latitude - latitudeDelta / 2,
            maxLatitude: center.latitude + latitudeDelta / 2,
            minLongitude: center.longitude - longitudeDelta / 2,
            maxLongitude: center.longitude + longitudeDelta / 2
        )
    }

    public var latitudeSpan: Double { maxLatitude - minLatitude }

    public func contains(_ point: RailCoordinate) -> Bool {
        (minLatitude ... maxLatitude).contains(point.latitude)
            && (minLongitude ... maxLongitude).contains(point.longitude)
    }

    public func intersects(_ other: RailBounds) -> Bool {
        minLatitude <= other.maxLatitude && other.minLatitude <= maxLatitude
            && minLongitude <= other.maxLongitude && other.minLongitude <= maxLongitude
    }

    public func padded(by degrees: Double) -> RailBounds {
        RailBounds(
            minLatitude: minLatitude - degrees,
            maxLatitude: maxLatitude + degrees,
            minLongitude: minLongitude - degrees,
            maxLongitude: maxLongitude + degrees
        )
    }
}

extension RailCoordinate {
    /// Miles to the nearest point of the segment a–b, using a local flat projection (fine for short segments).
    func roughMiles(toSegmentFrom a: RailCoordinate, to b: RailCoordinate) -> Double {
        let milesPerDegreeLatitude = 68.7
        let milesPerDegreeLongitude = 69.17 * cos(latitude * .pi / 180)
        let ax = (a.longitude - longitude) * milesPerDegreeLongitude
        let ay = (a.latitude - latitude) * milesPerDegreeLatitude
        let bx = (b.longitude - longitude) * milesPerDegreeLongitude
        let by = (b.latitude - latitude) * milesPerDegreeLatitude
        let dx = bx - ax
        let dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        let x = ax + t * dx
        let y = ay + t * dy
        return (x * x + y * y).squareRoot()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
