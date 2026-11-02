import Foundation

public struct FreightSighting: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let railOperator: RailOperator
    public let coordinate: RailCoordinate
    public let direction: String
    public let equipment: String
    public let confidence: Double
    public let observedAt: Date
    public let reporterCount: Int

    public init(
        id: String,
        railOperator: RailOperator,
        coordinate: RailCoordinate,
        direction: String,
        equipment: String,
        confidence: Double,
        observedAt: Date,
        reporterCount: Int
    ) {
        self.id = id
        self.railOperator = railOperator
        self.coordinate = coordinate
        self.direction = direction
        self.equipment = equipment
        self.confidence = min(max(confidence, 0), 1)
        self.observedAt = observedAt
        self.reporterCount = reporterCount
    }
}
