import Foundation

/// Epoch milliseconds, as sent by the server.
public typealias EpochMs = Double

public enum Operator: String, Codable, CaseIterable, Sendable {
    case amtrak, lirr, mnr, njt

    public var displayName: String {
        switch self {
        case .amtrak: return "Amtrak"
        case .lirr: return "LIRR"
        case .mnr: return "Metro-North"
        case .njt: return "NJ Transit"
        }
    }
}

public struct PlanStop: Codable, Equatable, Sendable {
    public var d: Double
    public var arr: EpochMs
    public var dep: EpochMs
    public init(d: Double, arr: EpochMs, dep: EpochMs) { self.d = d; self.arr = arr; self.dep = dep }
}

/// Server-provided motion plan; see server/src/motion.ts for the reference implementation.
public struct MotionPlan: Codable, Equatable, Sendable {
    public var d0: Double
    public var t0: EpochMs
    public var fallbackSpeed: Double
    public var maxSpeed: Double
    public var stops: [PlanStop]
    public var maxD: Double
    public init(d0: Double, t0: EpochMs, fallbackSpeed: Double, maxSpeed: Double, stops: [PlanStop], maxD: Double) {
        self.d0 = d0; self.t0 = t0; self.fallbackSpeed = fallbackSpeed; self.maxSpeed = maxSpeed; self.stops = stops; self.maxD = maxD
    }
}

public enum TrainStatus: String, Codable, Sendable { case scheduled, enroute, atStation, completed, cancelled }
public enum DataSource: String, Codable, Sendable { case live, scheduled }
public enum PositionFix: String, Codable, Sendable { case gps, predicted, timetable }

public struct NextStop: Codable, Equatable, Sendable {
    public var stationId: String
    public var name: String
    public var eta: EpochMs?
}

/// One train as broadcast to the map (no stop list).
public struct TrainSummary: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var `operator`: Operator
    public var tripId: String
    public var trainNumber: String
    public var route: String
    public var routeName: String
    public var headsign: String
    public var color: String
    public var shape: String?
    public var distM: Double
    public var lat: Double?
    public var lon: Double?
    public var bearing: Double
    public var speedMps: Double
    public var delaySec: Double?
    public var source: DataSource
    public var fix: PositionFix
    public var status: TrainStatus
    public var updatedAt: EpochMs
    public var plan: MotionPlan?
    public var origin: String
    public var destination: String
    public var progress: Double
    public var next: NextStop?
}

public struct TrainStop: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case departed, upcoming, skipped }
    public var stationId: String
    public var hubId: String
    public var name: String
    public var d: Double
    public var schArr: EpochMs?
    public var schDep: EpochMs?
    public var estArr: EpochMs?
    public var estDep: EpochMs?
    public var status: Status
    public var track: String?
    public var id: String { stationId + "@" + String(Int(d)) }
}

/// Full train record from GET /api/trains/:id.
public struct TrainDetail: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var `operator`: Operator
    public var trainNumber: String
    public var routeName: String
    public var headsign: String
    public var color: String
    public var shape: String?
    public var delaySec: Double?
    public var source: DataSource
    public var fix: PositionFix
    public var status: TrainStatus
    public var updatedAt: EpochMs
    public var plan: MotionPlan?
    public var origin: String
    public var destination: String
    public var progress: Double
    public var next: NextStop?
    public var stops: [TrainStop]
}

public struct LiveEvent: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case departed, arrived, delay, cancelled, tracking }
    public var id: Int
    public var at: EpochMs
    public var trainId: String
    public var `operator`: Operator
    public var kind: Kind
    public var text: String
    public var delaySec: Double?
}

public struct Snapshot: Codable, Sendable {
    public var serverTime: EpochMs
    public var demo: Bool
    public var trains: [TrainSummary]
    public var events: [LiveEvent]
}

/// Messages on the /live WebSocket.
public enum LiveMessage: Decodable, Sendable {
    case snapshot(Snapshot)
    case trains(operator: String, serverTime: EpochMs, trains: [TrainSummary], removed: [String])
    case event(serverTime: EpochMs, event: LiveEvent)
    case unknown

    private enum K: String, CodingKey { case type, serverTime, trains, removed, event, `operator`, demo, events }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "snapshot": self = .snapshot(try Snapshot(from: decoder))
        case "trains":
            self = .trains(operator: try c.decode(String.self, forKey: .operator), serverTime: try c.decode(EpochMs.self, forKey: .serverTime),
                           trains: try c.decode([TrainSummary].self, forKey: .trains), removed: try c.decode([String].self, forKey: .removed))
        case "event": self = .event(serverTime: try c.decode(EpochMs.self, forKey: .serverTime), event: try c.decode(LiveEvent.self, forKey: .event))
        default: self = .unknown
        }
    }
}

public struct StationSummary: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var operators: [Operator]
    public var code: String?
}

public struct BoardRow: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case departure, arrival }
    public var trainId: String?
    public var `operator`: Operator
    public var trainNumber: String
    public var label: String
    public var routeName: String
    public var color: String
    public var origin: String
    public var destination: String
    public var kind: Kind
    public var scheduled: EpochMs
    public var estimated: EpochMs?
    public var delaySec: Double?
    public var status: String
    public var track: String?
    public var source: DataSource
    public var fix: PositionFix
    public var id: String { "\(`operator`.rawValue):\(trainNumber):\(kind.rawValue):\(Int(scheduled))" }
}

public struct Board: Codable, Sendable {
    public struct Hub: Codable, Sendable { public var id: String; public var name: String; public var lat: Double; public var lon: Double; public var operators: [Operator] }
    public var hub: Hub
    public var serverTime: EpochMs
    public var rows: [BoardRow]
}

public struct SearchResult: Codable, Sendable {
    public var trains: [TrainSummary]
    public var stations: [StationSummary]
}

public struct ShapeResponse: Codable, Sendable { public var key: String; public var polyline: String; public var lengthM: Double }

public struct RouteOverview: Codable, Sendable {
    public struct Line: Codable, Sendable { public var key: String; public var `operator`: Operator; public var route: String; public var color: String; public var polyline: String }
    public var license: String
    public var routes: [Line]
}
