import XCTest
@testable import ILikeTrainsData

@MainActor
final class RailMapViewModelTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testLoadComposesAllProvidersIntoOneSnapshot() async {
        let service = MockRailDataService(referenceDate: referenceDate)
        let model = RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service
        )

        await model.load()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.trains.isEmpty)
        XCTAssertFalse(model.segments.isEmpty)
        XCTAssertFalse(model.sightings.isEmpty)
        XCTAssertTrue(model.hasVisibleContent)
    }

    func testSearchMatchesTrainNumberNameRouteAndOperator() async {
        let model = makeLoadedModel()
        await model.load()

        model.searchQuery = "50"
        XCTAssertEqual(model.filteredTrains.map(\.number), ["50"])

        model.searchQuery = "Zephyr"
        XCTAssertEqual(model.filteredTrains.map(\.name), ["California Zephyr"])

        model.searchQuery = "Miami"
        XCTAssertEqual(model.filteredTrains.map(\.railOperator), [.brightline])

        model.searchQuery = "Amtrak"
        XCTAssertTrue(model.filteredTrains.allSatisfy { $0.railOperator == .amtrak })
    }

    func testOperatorAndLayerFiltersAreIndependent() async {
        let model = makeLoadedModel()
        await model.load()

        model.selectedOperator = .brightline
        XCTAssertTrue(model.filteredTrains.allSatisfy { $0.railOperator == .brightline })

        model.layers.infrastructure = false
        model.layers.stations = false
        model.layers.freightSightings = false
        XCTAssertTrue(model.visibleSegments.isEmpty)
        XCTAssertTrue(model.visibleStations.isEmpty)
        XCTAssertTrue(model.visibleSightings.isEmpty)
        XCTAssertFalse(model.filteredTrains.isEmpty)
    }

    func testSelectionTogglesAndResolvesSelectedTrain() async {
        let model = makeLoadedModel()
        await model.load()
        let train = try! XCTUnwrap(model.trains.first)

        model.selectTrain(train)
        XCTAssertEqual(model.selectedTrain, train)

        model.selectTrain(train)
        XCTAssertNil(model.selectedTrain)
    }

    func testExplicitSelectionNeverTogglesOffAndHiddenSelectionIsNotPresented() async {
        let model = makeLoadedModel()
        await model.load()
        let train = try! XCTUnwrap(model.trains.first)

        model.setSelectedTrain(train)
        model.setSelectedTrain(train)
        XCTAssertEqual(model.selectedTrain, train)

        model.layers.passengerTrains = false
        XCTAssertNil(model.selectedTrain)
    }

    func testEmptySnapshotExposesEmptyState() async {
        let service = EmptyRailDataService()
        let model = RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service
        )

        await model.load()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.hasVisibleContent)
    }

    func testRefreshFailurePreservesPreviousSnapshot() async {
        let healthy = MockRailDataService(referenceDate: referenceDate)
        let model = RailMapViewModel(
            trainProvider: SequencedTrainProvider(first: healthy),
            infrastructureProvider: SequencedInfrastructureProvider(first: healthy),
            freightProvider: SequencedFreightProvider(first: healthy)
        )
        await model.load()
        let previousTrains = model.trains
        let previousSegments = model.segments
        let previousSightings = model.sightings

        await model.refresh()

        guard case .failed = model.loadState else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(model.trains, previousTrains)
        XCTAssertEqual(model.segments, previousSegments)
        XCTAssertEqual(model.sightings, previousSightings)
    }

    private func makeLoadedModel() -> RailMapViewModel {
        let service = MockRailDataService(referenceDate: referenceDate)
        return RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service
        )
    }
}

private struct EmptyRailDataService:
    TrainProviding,
    RailInfrastructureProviding,
    FreightSightingProviding
{
    func trains() async throws -> [Train] { [] }
    func railSegments() async throws -> [RailSegment] { [] }
    func freightSightings() async throws -> [FreightSighting] { [] }
}

private actor SequencedTrainProvider: TrainProviding {
    let first: MockRailDataService
    var count = 0

    init(first: MockRailDataService) {
        self.first = first
    }

    func trains() async throws -> [Train] {
        defer { count += 1 }
        if count > 0 { throw RailDataError.unavailable }
        return try await first.trains()
    }
}

private actor SequencedInfrastructureProvider: RailInfrastructureProviding {
    let first: MockRailDataService
    var count = 0

    init(first: MockRailDataService) {
        self.first = first
    }

    func railSegments() async throws -> [RailSegment] {
        defer { count += 1 }
        if count > 0 { throw RailDataError.unavailable }
        return try await first.railSegments()
    }
}

private actor SequencedFreightProvider: FreightSightingProviding {
    let first: MockRailDataService
    var count = 0

    init(first: MockRailDataService) {
        self.first = first
    }

    func freightSightings() async throws -> [FreightSighting] {
        defer { count += 1 }
        if count > 0 { throw RailDataError.unavailable }
        return try await first.freightSightings()
    }
}
