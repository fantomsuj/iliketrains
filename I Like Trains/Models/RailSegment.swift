import Foundation

public struct RailStation: Identifiable, Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let city: String
    public let coordinate: RailCoordinate

    public var id: String { code }

    public init(code: String, name: String, city: String, coordinate: RailCoordinate) {
        self.code = code
        self.name = name
        self.city = city
        self.coordinate = coordinate
    }
}

public struct RailSegment: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case intercity
        case commuter
        case freightMainline
    }

    public let id: String
    public let name: String
    public let operator: RailOperator?
    public let kind: Kind
    public let coordinates: [RailCoordinate]
    public let stations: [RailStation]
    public let trafficDensity: Int
    public let electrified: Bool

    public init(
        id: String,
        name: String,
        operator: RailOperator?,
        kind: Kind,
        coordinates: [RailCoordinate],
        stations: [RailStation],
        trafficDensity: Int,
        electrified: Bool
    ) {
        self.id = id
        self.name = name
        self.operator = operator
        self.kind = kind
        self.coordinates = coordinates
        self.stations = stations
        self.trafficDensity = trafficDensity
        self.electrified = electrified
    }
}
