import Foundation
import Observation

public struct RailLayerVisibility: Equatable, Sendable {
    public var passengerTrains = true
    public var infrastructure = true
    public var stations = true
    public var freightSightings = true

    public init() {}
}

@MainActor
@Observable
public final class RailMapViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    public private(set) var trains: [Train] = []
    public private(set) var segments: [RailSegment] = []
    public private(set) var sightings: [FreightSighting] = []
    public private(set) var loadState: LoadState = .idle
    public var searchQuery = ""
    public var selectedOperator: RailOperator?
    public var selectedTrainID: Train.ID?
    public var layers = RailLayerVisibility()

    @ObservationIgnored private let trainProvider: any TrainProviding
    @ObservationIgnored private let infrastructureProvider: any RailInfrastructureProviding
    @ObservationIgnored private let freightProvider: any FreightSightingProviding

    public init(
        trainProvider: any TrainProviding,
        infrastructureProvider: any RailInfrastructureProviding,
        freightProvider: any FreightSightingProviding
    ) {
        self.trainProvider = trainProvider
        self.infrastructureProvider = infrastructureProvider
        self.freightProvider = freightProvider
    }

    public var filteredTrains: [Train] {
        guard layers.passengerTrains else { return [] }
        return trains.filter { train in
            let matchesOperator = selectedOperator == nil || train.operator == selectedOperator
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return matchesOperator }
            let searchable = [
                train.number,
                train.name,
                train.operator.displayName,
                train.origin,
                train.destination,
                train.nextStop
            ].joined(separator: " ")
            return matchesOperator && searchable.localizedCaseInsensitiveContains(query)
        }
    }

    public var visibleSegments: [RailSegment] {
        guard layers.infrastructure else { return [] }
        guard let selectedOperator else { return segments }
        return segments.filter { $0.operator == nil || $0.operator == selectedOperator }
    }

    public var visibleStations: [RailStation] {
        guard layers.stations else { return [] }
        var seen = Set<RailStation.ID>()
        return visibleSegments
            .flatMap(\.stations)
            .filter { seen.insert($0.id).inserted }
    }

    public var visibleSightings: [FreightSighting] {
        guard layers.freightSightings else { return [] }
        guard let selectedOperator else { return sightings }
        return sightings.filter { $0.operator == selectedOperator }
    }

    public var selectedTrain: Train? {
        filteredTrains.first { $0.id == selectedTrainID }
    }

    public var hasVisibleContent: Bool {
        !trains.isEmpty || !segments.isEmpty || !sightings.isEmpty
    }

    public func load() async {
        loadState = .loading
        do {
            async let nextTrains = trainProvider.trains()
            async let nextSegments = infrastructureProvider.railSegments()
            async let nextSightings = freightProvider.freightSightings()
            let snapshot = try await (nextTrains, nextSegments, nextSightings)
            trains = snapshot.0
            segments = snapshot.1
            sightings = snapshot.2
            loadState = .loaded
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }

    public func refresh() async {
        await load()
    }

    public func selectTrain(_ train: Train) {
        selectedTrainID = selectedTrainID == train.id ? nil : train.id
    }

    public func setSelectedTrain(_ train: Train) {
        selectedTrainID = train.id
    }
}
