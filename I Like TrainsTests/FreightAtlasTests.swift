import XCTest
@testable import ILikeTrainsData

@MainActor
final class FreightAtlasTests: XCTestCase {
    private static let atlasURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("I Like Trains/Data/freight-atlas.json")

    private func loadAtlas() async throws -> FreightAtlas {
        try await BundledFreightAtlasService(url: Self.atlasURL).freightAtlas()
    }

    // MARK: Bundled data

    func testAtlasCoversEveryClassIRailroadWithMeasuredTraffic() async throws {
        let atlas = try await loadAtlas()

        XCTAssertGreaterThan(atlas.corridors.count, 1_000)
        XCTAssertEqual(
            Set(atlas.corridors.map(\.railroad)),
            [.bnsf, .unionPacific, .csx, .norfolkSouthern, .canadianNational, .canadianPacificKansasCity]
        )
        let measured = atlas.corridors.filter { $0.trainsPerDay != nil }
        XCTAssertGreaterThan(Double(measured.count) / Double(atlas.corridors.count), 0.9)
        XCTAssertTrue(atlas.corridors.allSatisfy { $0.path.count >= 2 && $0.path.allSatisfy(\.isValid) })
        XCTAssertTrue(measured.allSatisfy { ($0.trainsPerDay ?? -1) >= 0 && ($0.trainsPerDay ?? 999) <= 150 })
        XCTAssertTrue(atlas.corridors.allSatisfy {
            $0.level == TrafficLevel(trainsPerDay: $0.trainsPerDay, bounds: atlas.levelBounds)
        })
    }

    func testBusiestLinesAreFreightNotCommuterLines() async throws {
        let atlas = try await loadAtlas()
        let busiest = atlas.busiestCorridors(limit: 10)

        XCTAssertEqual(busiest.count, 10)
        XCTAssertEqual(busiest.map { $0.trainsPerDay ?? 0 }, busiest.map { $0.trainsPerDay ?? 0 }.sorted(by: >))
        // Passenger and transit trains are subtracted, so New York commuter lines must not top the list.
        let newYork = RailCoordinate(latitude: 40.75, longitude: -73.99)
        XCTAssertTrue(busiest.allSatisfy { $0.distanceMiles(to: newYork) > 60 })
        XCTAssertEqual(atlas.busiestCorridors(limit: 3, railroad: .csx).map(\.railroad), [.csx, .csx, .csx])
    }

    func testUnionPacificOverlandRouteIsBusyAndFindableByTap() async throws {
        let atlas = try await loadAtlas()
        let ogallala = RailCoordinate(latitude: 41.13, longitude: -101.72)
        let corridor = try XCTUnwrap(atlas.nearestCorridor(to: ogallala, within: 3))

        XCTAssertEqual(corridor.railroad, .unionPacific)
        XCTAssertGreaterThanOrEqual(corridor.level, .busy)
        XCTAssertNotNil(corridor.place)
        XCTAssertNil(atlas.nearestCorridor(to: RailCoordinate(latitude: 30.0, longitude: -140.0), within: 3))
    }

    func testIntermodalTerminalsServiceAndVolumeDecode() async throws {
        let atlas = try await loadAtlas()

        XCTAssertEqual(atlas.terminals.count, 241)
        XCTAssertEqual(Set(atlas.terminals.map(\.id)).count, atlas.terminals.count)
        XCTAssertTrue(atlas.terminals.allSatisfy { $0.coordinate.isValid && ($0.handlesContainers || $0.handlesTrailers) })
        let olympia = try XCTUnwrap(atlas.terminals.first { $0.city == "Olympia" })
        XCTAssertEqual(olympia.railroads, [.bnsf, .unionPacific])
        XCTAssertEqual(olympia.port, "Port of Olympia")

        XCTAssertEqual(atlas.service.count, 6)
        XCTAssertEqual(atlas.serviceWeekEnded, ReportDate(year: 2026, month: 11, day: 13))
        let bnsf = try XCTUnwrap(atlas.service(for: .bnsf))
        XCTAssertEqual(bnsf.systemSpeedMPH, 25.3)
        XCTAssertEqual(bnsf.yards.count, 10)
        XCTAssertEqual(bnsf.slowestYard?.name, "Barstow, CA")
        XCTAssertEqual(bnsf.speeds.first?.trainType, "Intermodal")
        XCTAssertFalse(bnsf.speeds.contains { $0.trainType == "System" })
        XCTAssertEqual(atlas.yards.count, 60)

        let volume = try XCTUnwrap(atlas.volume)
        XCTAssertEqual(volume.week, 46)
        XCTAssertEqual(volume.weekEnded.shortLabel, "Nov 21")
        XCTAssertEqual(volume.totalTraffic.count, 540_111)
        XCTAssertEqual(volume.commodities.first?.name, "Coal")
        XCTAssertEqual(Set(atlas.sources.map(\.id)), ["crossings", "track", "intermodal", "service", "volume"])
    }

    // MARK: Small values

    func testTrafficLevelsFollowTheBounds() {
        let bounds: [Double] = [5, 15, 30, 50, 80]
        XCTAssertEqual(TrafficLevel(trainsPerDay: nil, bounds: bounds), .unmeasured)
        XCTAssertEqual(TrafficLevel(trainsPerDay: 0, bounds: bounds), .light)
        XCTAssertEqual(TrafficLevel(trainsPerDay: 5, bounds: bounds), .moderate)
        XCTAssertEqual(TrafficLevel(trainsPerDay: 29.9, bounds: bounds), .busy)
        XCTAssertEqual(TrafficLevel(trainsPerDay: 120, bounds: bounds), .extreme)
    }

    func testRangeLabels() async throws {
        let atlas = try await loadAtlas()
        XCTAssertEqual(atlas.rangeLabel(for: .light), "0–5")
        XCTAssertEqual(atlas.rangeLabel(for: .busy), "15–30")
        XCTAssertEqual(atlas.rangeLabel(for: .extreme), "80+")
        XCTAssertEqual(atlas.rangeLabel(for: .unmeasured), "No count")
    }

    func testReportDatesParseWithoutTimeZones() {
        XCTAssertEqual(ReportDate(iso: "2026-11-13")?.shortLabel, "Nov 13")
        XCTAssertNil(ReportDate(iso: "2026-13-01"))
        XCTAssertNil(ReportDate(iso: "not a date"))
        XCTAssertLessThan(ReportDate(year: 2026, month: 1, day: 31)!, ReportDate(year: 2026, month: 2, day: 1)!)
    }

    func testDistanceToSegmentUsesTheClosestPoint() {
        let a = RailCoordinate(latitude: 40, longitude: -100)
        let b = RailCoordinate(latitude: 40, longitude: -99)
        let above = RailCoordinate(latitude: 40.1, longitude: -99.5)
        XCTAssertEqual(above.roughMiles(toSegmentFrom: a, to: b), 6.87, accuracy: 0.05)
        let beyond = RailCoordinate(latitude: 40, longitude: -98.9)
        XCTAssertEqual(beyond.roughMiles(toSegmentFrom: a, to: b), beyond.roughMiles(to: b), accuracy: 0.2)
    }

    // MARK: Map view model

    func testFreightLayersThinOutWhenZoomedOutAndFollowTheOperatorFilter() async throws {
        let model = makeModel()
        await model.load()
        let atlas = try XCTUnwrap(model.freightAtlas)

        // National default: only busy lines, no terminals, every yard.
        XCTAssertEqual(model.minimumVisibleLevel, .busy)
        XCTAssertTrue(model.visibleCorridors.allSatisfy { $0.level >= .busy })
        XCTAssertTrue(model.visibleTerminals.isEmpty)
        XCTAssertTrue(model.terminalsNeedZoom)
        XCTAssertEqual(model.visibleYards.count, 60)
        XCTAssertEqual(model.visibleCorridors.map(\.level), model.visibleCorridors.map(\.level).sorted())

        // Zoomed in on Chicago: everything nearby, nothing far away.
        let chicago = RailCoordinate(latitude: 41.88, longitude: -87.63)
        model.visibleRegion = RailBounds(center: chicago, latitudeDelta: 2, longitudeDelta: 2.5)
        XCTAssertEqual(model.minimumVisibleLevel, .unmeasured)
        XCTAssertFalse(model.visibleTerminals.isEmpty)
        XCTAssertTrue(model.visibleTerminals.allSatisfy { model.visibleRegion!.contains($0.coordinate) })
        XCTAssertLessThan(model.visibleCorridors.count, atlas.corridors.count)
        XCTAssertFalse(model.terminalsNeedZoom)

        model.selectedOperator = .csx
        XCTAssertTrue(model.visibleCorridors.allSatisfy { $0.railroad == .csx })
        XCTAssertTrue(model.visibleYards.allSatisfy { $0.railroad == .csx })
        XCTAssertTrue(model.visibleTerminals.allSatisfy { $0.railroads.contains(.csx) })

        model.layers.trafficDensity = false
        model.layers.intermodalTerminals = false
        model.layers.yardDwell = false
        XCTAssertTrue(model.visibleCorridors.isEmpty)
        XCTAssertTrue(model.visibleTerminals.isEmpty)
        XCTAssertTrue(model.visibleYards.isEmpty)
        XCTAssertEqual(model.layers.hiddenCount, 3)
    }

    func testTrainAndFreightSelectionsAreExclusive() async throws {
        let model = makeModel()
        await model.load()
        let train = try XCTUnwrap(model.trains.first)
        let yard = try XCTUnwrap(model.freightAtlas?.yards.first)

        model.selectTrain(train)
        model.toggleFreight(.yard(yard.id))
        XCTAssertNil(model.selectedTrain)
        XCTAssertEqual(model.selectedYard, yard)

        model.selectTrain(train)
        XCTAssertNil(model.selectedFreight)
        XCTAssertEqual(model.selectedTrain, train)

        model.selectedFreight = nil
        XCTAssertEqual(model.selectedTrain, train, "clearing an empty freight selection keeps the train")

        model.toggleFreight(.yard(yard.id))
        model.toggleFreight(.yard(yard.id))
        XCTAssertNil(model.selectedFreight)
        XCTAssertNil(model.selectedTrain)
    }

    func testTappingNearALineSelectsItAndTappingOpenMapClears() async throws {
        let model = makeModel()
        await model.load()
        model.visibleRegion = RailBounds(
            center: RailCoordinate(latitude: 41.1, longitude: -101.5),
            latitudeDelta: 3,
            longitudeDelta: 4
        )

        let corridor = try XCTUnwrap(model.selectCorridor(near: RailCoordinate(latitude: 41.13, longitude: -101.72)))
        XCTAssertEqual(model.selectedCorridor, corridor)

        XCTAssertNil(model.selectCorridor(near: RailCoordinate(latitude: 42.4, longitude: -100.1)))
        XCTAssertNil(model.selectedFreight)
    }

    func testFreightAtlasFailureLeavesTheRestOfTheMapWorking() async {
        let service = MockRailDataService()
        let model = RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service,
            freightAtlasProvider: BundledFreightAtlasService(url: nil)
        )

        await model.load()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertFalse(model.trains.isEmpty)
        XCTAssertNil(model.freightAtlas)
        XCTAssertNotNil(model.freightAtlasError)
        XCTAssertTrue(model.visibleCorridors.isEmpty)
        XCTAssertTrue(model.visibleYards.isEmpty)
    }

    private func makeModel() -> RailMapViewModel {
        let service = MockRailDataService()
        return RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service,
            freightAtlasProvider: BundledFreightAtlasService(url: Self.atlasURL)
        )
    }
}
