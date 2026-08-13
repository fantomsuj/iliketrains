import Foundation

public enum RailOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case amtrak
    case brightline
    case metrolink
    case bnsf
    case unionPacific
    case csx
    case norfolkSouthern
    case canadianPacificKansasCity

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .amtrak: "Amtrak"
        case .brightline: "Brightline"
        case .metrolink: "Metrolink"
        case .bnsf: "BNSF Railway"
        case .unionPacific: "Union Pacific"
        case .csx: "CSX"
        case .norfolkSouthern: "Norfolk Southern"
        case .canadianPacificKansasCity: "CPKC"
        }
    }

    public var shortName: String {
        switch self {
        case .bnsf: "BNSF"
        case .unionPacific: "UP"
        case .norfolkSouthern: "NS"
        case .canadianPacificKansasCity: "CPKC"
        default: displayName
        }
    }
}

public struct Train: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case onTime
        case delayed
        case early
        case stopped

        public var label: String {
            switch self {
            case .onTime: "On time"
            case .delayed: "Delayed"
            case .early: "Early"
            case .stopped: "At station"
            }
        }
    }

    public let id: String
    public let number: String
    public let name: String
    public let operator: RailOperator
    public let origin: String
    public let destination: String
    public let coordinate: RailCoordinate
    public let heading: Double
    public let speedMPH: Int
    public let delayMinutes: Int
    public let nextStop: String
    public let nextStopCode: String
    public let nextStopETA: Date
    public let updatedAt: Date
    public let status: Status

    public init(
        id: String,
        number: String,
        name: String,
        operator: RailOperator,
        origin: String,
        destination: String,
        coordinate: RailCoordinate,
        heading: Double,
        speedMPH: Int,
        delayMinutes: Int,
        nextStop: String,
        nextStopCode: String,
        nextStopETA: Date,
        updatedAt: Date,
        status: Status
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.operator = operator
        self.origin = origin
        self.destination = destination
        self.coordinate = coordinate
        self.heading = heading
        self.speedMPH = speedMPH
        self.delayMinutes = delayMinutes
        self.nextStop = nextStop
        self.nextStopCode = nextStopCode
        self.nextStopETA = nextStopETA
        self.updatedAt = updatedAt
        self.status = status
    }
}
