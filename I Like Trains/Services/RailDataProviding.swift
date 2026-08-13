import Foundation

public protocol TrainProviding: Sendable {
    func trains() async throws -> [Train]
}

public protocol RailInfrastructureProviding: Sendable {
    func railSegments() async throws -> [RailSegment]
}

public protocol FreightSightingProviding: Sendable {
    func freightSightings() async throws -> [FreightSighting]
}

public enum RailDataError: LocalizedError, Sendable {
    case unavailable

    public var errorDescription: String? {
        "Rail data is temporarily unavailable. Your last map is still here."
    }
}
