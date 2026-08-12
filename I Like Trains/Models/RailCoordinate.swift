import Foundation

public struct RailCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }
}
