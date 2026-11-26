import XCTest
@testable import ILikeTrainsData

@MainActor
final class GhostTrainSimulatorTests: XCTestCase {
    /// A straight line due east along 40°N, about 100 miles long.
    private let line = [
        RailCoordinate(latitude: 40, longitude: -100),
        RailCoordinate(latitude: 40, longitude: -99.4),
        RailCoordinate(latitude: 40, longitude: -98.11)
    ]

    private func corridor(id: Int = 1, trainsPerDay: Double? = 48, maxSpeed: Int? = 70, railroad: RailOperator = .bnsf) -> FreightCorridor {
        FreightCorridor(
            id: id,
            railroad: railroad,
            trainsPerDay: trainsPerDay,
            maxSpeedMPH: maxSpeed,
            mainTracks: 2,
            crossingCount: 12,
            level: TrafficLevel(trainsPerDay: trainsPerDay, bounds: [5, 15, 30, 50, 80]),
            path: line
        )
    }

    private func simulator(_ corridors: [FreightCorridor], speed: Double = 25) -> GhostTrainSimulator {
        GhostTrainSimulator(corridors: corridors) { _ in speed }
    }

    private var lineMiles: Double {
        zip(line, line.dropFirst()).reduce(0.0) { $0 + $1.0.roughMiles(to: $1.1) }
    }

    // MARK: Counts

    func testTrainsOnTheLineMatchATypicalDay() {
        let sim = simulator([corridor()])
        // 48 trains a day is a 30-minute headway; ~100 miles at 25 mph is ~4 hours end to end.
        let expected = (lineMiles / 25 * 3_600) / (86_400 / 48)
        XCTAssertEqual(sim.expectedTrainsOnLine(1), expected, accuracy: 0.001)

        // An irregular step over ten days samples every point of the departure cycle.
        let samples = stride(from: 0.0, to: 864_000, by: 997).map { Double(sim.trains(at: $0, on: [1]).count) }
        XCTAssertTrue(samples.allSatisfy { abs($0 - expected) <= 2 })
        XCTAssertEqual(samples.reduce(0, +) / Double(samples.count), expected, accuracy: 0.15)
    }

    func testBothDirectionsRunAndStayOnTheTrack() {
        let trains = simulator([corridor()]).trains(at: 40_000, on: [1], tailSeconds: 600)

        XCTAssertTrue(trains.contains { $0.isForward })
        XCTAssertTrue(trains.contains { !$0.isForward })
        for train in trains {
            XCTAssertEqual(train.coordinate.latitude, 40, accuracy: 1e-9)
            XCTAssertTrue((-100 ... -98.11).contains(train.coordinate.longitude))
            // The line runs east, so a forward train's tail is west of it and a backward train's east.
            if train.isForward {
                XCTAssertLessThanOrEqual(train.tailCoordinate.longitude, train.coordinate.longitude)
            } else {
                XCTAssertGreaterThanOrEqual(train.tailCoordinate.longitude, train.coordinate.longitude)
            }
            XCTAssertTrue((0 ... 1).contains(train.opacity))
        }
    }

    func testTrainsMoveSmoothlyAndKeepTheirIdentity() {
        let sim = simulator([corridor()])
        let before = Dictionary(uniqueKeysWithValues: sim.trains(at: 30_000, on: [1]).map { ($0.departure, $0) })
        let after = sim.trains(at: 30_060, on: [1])

        let moved = after.compactMap { train in
            before[train.departure].map { train.coordinate.roughMiles(to: $0.coordinate) }
        }
        XCTAssertFalse(moved.isEmpty)
        // One simulated minute at 25 mph is about 0.42 miles.
        for miles in moved {
            XCTAssertEqual(miles, 25.0 / 60, accuracy: 0.02)
        }
        XCTAssertEqual(sim.trains(at: 30_000, on: [1]), sim.trains(at: 30_000, on: [1]))
    }

    func testTrainsFadeAtTheEndsOfTheirRun() {
        XCTAssertEqual(GhostTrainSimulator.fade(elapsed: 0, remaining: 5_000, over: 100), 0)
        XCTAssertEqual(GhostTrainSimulator.fade(elapsed: 50, remaining: 5_000, over: 100), 0.5)
        XCTAssertEqual(GhostTrainSimulator.fade(elapsed: 3_000, remaining: 3_000, over: 100), 1)
        XCTAssertEqual(GhostTrainSimulator.fade(elapsed: 3_000, remaining: 25, over: 100), 0.25)
        XCTAssertEqual(GhostTrainSimulator.fade(elapsed: 10, remaining: 10, over: 0), 1)
    }

    // MARK: Inputs

    func testSpeedIsCappedByTheTimetableAndFloored() {
        let fast = simulator([corridor(maxSpeed: 40)], speed: 80)
        XCTAssertEqual(fast.expectedTrainsOnLine(1), (lineMiles / 40 * 3_600) / 1_800, accuracy: 0.001)

        let crawl = simulator([corridor(maxSpeed: 5)], speed: 25)
        XCTAssertEqual(crawl.expectedTrainsOnLine(1), (lineMiles / GhostTrainSimulator.minimumSpeedMPH * 3_600) / 1_800, accuracy: 0.001)

        let unknownRailroad = GhostTrainSimulator(corridors: [corridor(maxSpeed: nil)]) { _ in nil }
        XCTAssertEqual(
            unknownRailroad.expectedTrainsOnLine(1),
            (lineMiles / GhostTrainSimulator.fallbackSpeedMPH * 3_600) / 1_800,
            accuracy: 0.001
        )
    }

    func testUnmeasuredLinesCarryNoTrains() {
        let sim = simulator([corridor(id: 1, trainsPerDay: nil), corridor(id: 2, trainsPerDay: 0)])
        XCTAssertEqual(sim.simulatedCorridorCount, 0)
        XCTAssertTrue(sim.trains(at: 1_000, on: [1, 2]).isEmpty)
    }

    func testLimitKeepsAStableSubsetAndBoundsCull() {
        let corridors = (1 ... 20).map { corridor(id: $0, trainsPerDay: 120) }
        let sim = simulator(corridors)
        let ids = Set(1 ... 20)

        let all = sim.trains(at: 10_000, on: ids)
        let limited = sim.trains(at: 10_000, on: ids, limit: 60)
        XCTAssertGreaterThan(all.count, 150)
        XCTAssertLessThanOrEqual(limited.count, 60)
        XCTAssertGreaterThan(limited.count, 30)

        let later = Set(sim.trains(at: 10_030, on: ids, limit: 60).map { "\($0.corridorID)-\($0.departure)" })
        let kept = limited.filter { later.contains("\($0.corridorID)-\($0.departure)") }
        XCTAssertGreaterThan(Double(kept.count) / Double(limited.count), 0.9, "the same trains stay visible")

        let westHalf = RailBounds(minLatitude: 39, maxLatitude: 41, minLongitude: -100.1, maxLongitude: -99.05)
        let culled = sim.trains(at: 10_000, on: ids, within: westHalf)
        XCTAssertFalse(culled.isEmpty)
        XCTAssertTrue(culled.allSatisfy { westHalf.contains($0.coordinate) })
        XCTAssertTrue(sim.trains(at: 10_000, on: ids, within: RailBounds(minLatitude: 10, maxLatitude: 11, minLongitude: 10, maxLongitude: 11)).isEmpty)
    }

    // MARK: Time

    func testTimeScaleKeepsMotionVisibleAtEveryZoom() {
        XCTAssertEqual(GhostTrainSimulator.timeScale(forLatitudeSpan: 38), 7_500)
        XCTAssertEqual(GhostTrainSimulator.timeScale(forLatitudeSpan: 1), 200)
        XCTAssertEqual(GhostTrainSimulator.timeScale(forLatitudeSpan: 0.01), 30)
        XCTAssertLessThanOrEqual(GhostTrainSimulator.timeScale(forLatitudeSpan: 500), 12_000)
        let spans: [Double] = [0.05, 0.3, 1, 3, 8, 20, 38, 60]
        let scales = spans.map(GhostTrainSimulator.timeScale(forLatitudeSpan:))
        XCTAssertEqual(scales, scales.sorted())
    }

    func testClockAdvancesByScaledTimeAndIgnoresLongGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 18 * 3_600 + 42 * 60)   // 6:42 PM UTC
        let clock = GhostClock(startingAt: start, calendar: calendar)
        XCTAssertEqual(clock.timeOfDay.hour, 18)
        XCTAssertEqual(clock.timeOfDay.minute, 42)

        XCTAssertEqual(clock.tick(to: start, scale: 100), 67_320, "the first tick only sets the reference")
        XCTAssertEqual(clock.tick(to: start.addingTimeInterval(0.1), scale: 100), 67_330, accuracy: 0.0001)
        XCTAssertEqual(clock.tick(to: start.addingTimeInterval(60), scale: 100), 67_355, accuracy: 0.0001, "long gaps count as a quarter second")
        XCTAssertEqual(clock.tick(to: start.addingTimeInterval(61), scale: 100, isPaused: true), 67_355, accuracy: 0.0001)
        XCTAssertEqual(clock.tick(to: start.addingTimeInterval(61.2), scale: 1_000), 67_555, accuracy: 0.0001)

        for _ in 0 ..< 400 {
            clock.tick(to: Date().addingTimeInterval(Double.random(in: 0 ... 0.0001)), scale: 12_000)
        }
        XCTAssertTrue((0 ..< 24).contains(clock.timeOfDay.hour ?? -1))
    }

    // MARK: Bundled data and the map

    func testTheNationalNetworkRunsAboutAsManyTrainsAsRealLife() async throws {
        let model = makeModel()
        await model.load()
        let simulator = try XCTUnwrap(model.ghostSimulator)
        let atlas = try XCTUnwrap(model.freightAtlas)

        let total = atlas.corridors.reduce(0.0) { $0 + simulator.expectedTrainsOnLine($1.id) }
        XCTAssertGreaterThan(total, 1_400)
        XCTAssertLessThan(total, 2_400)

        let trains = simulator.trains(at: 50_000, on: atlas.corridors.map(\.id))
        XCTAssertEqual(Double(trains.count), total, accuracy: total * 0.05)
        XCTAssertTrue(trains.allSatisfy(\.coordinate.isValid))
    }

    func testGhostTrainsFollowTheLayerZoomAndOperatorFilter() async throws {
        let model = makeModel()
        await model.load()

        XCTAssertFalse(model.ghostCorridorIDs.isEmpty)
        XCTAssertGreaterThan(model.ghostTrainsInView, 500)
        XCTAssertEqual(model.ghostTimeScale, 7_500)
        XCTAssertFalse(model.ghostTrainsPaused)

        // Ghost trains don't depend on the traffic colours being drawn.
        model.layers.trafficDensity = false
        XCTAssertTrue(model.visibleCorridors.isEmpty)
        XCTAssertFalse(model.ghostCorridorIDs.isEmpty)

        let atlas = try XCTUnwrap(model.freightAtlas)
        model.selectedOperator = .norfolkSouthern
        let ids = model.ghostCorridorIDs
        XCTAssertTrue(atlas.corridors.filter { ids.contains($0.id) }.allSatisfy { $0.railroad == .norfolkSouthern })

        model.visibleRegion = RailBounds(center: RailCoordinate(latitude: 41.88, longitude: -87.63), latitudeDelta: 1, longitudeDelta: 1.3)
        XCTAssertEqual(model.ghostTimeScale, 200)
        XCTAssertNotNil(model.ghostBounds)

        model.layers.ghostTrains = false
        XCTAssertTrue(model.ghostCorridorIDs.isEmpty)
        XCTAssertEqual(model.ghostTrainsInView, 0)
        XCTAssertEqual(model.layers.hiddenCount, 2)
    }

    private func makeModel() -> RailMapViewModel {
        let atlasURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("I Like Trains/Data/freight-atlas.json")
        let service = MockRailDataService()
        return RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service,
            freightAtlasProvider: BundledFreightAtlasService(url: atlasURL)
        )
    }
}
