import XCTest
@testable import ILikeTrainsData

@MainActor
final class RouteAtlasTests: XCTestCase {
    private static let atlasURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("I Like Trains/Data/route-atlas.json")

    private func loadAtlas() async throws -> RouteAtlas {
        try await BundledRouteAtlasService(url: Self.atlasURL).routeAtlas()
    }

    func testPolylineDecodesReferenceExample() async {
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 1e-6)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 1e-6)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 1e-6)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 1e-6)
    }

    func testAtlasCoversPassengerServicesAndEveryClassIRailroad() async throws {
        let atlas = try await loadAtlas()

        XCTAssertGreaterThanOrEqual(atlas.passengerRoutes.count, 45)
        XCTAssertEqual(Set(atlas.passengerRoutes.map(\.id)).count, atlas.passengerRoutes.count)
        XCTAssertEqual(
            Set(atlas.freightNetworks.map(\.railroad)),
            [.bnsf, .unionPacific, .csx, .norfolkSouthern, .canadianNational, .canadianPacificKansasCity]
        )
        XCTAssertTrue(atlas.passengerRoutes.allSatisfy { $0.path.count >= 2 && $0.path.allSatisfy(\.isValid) })
        XCTAssertTrue(atlas.passengerRoutes.allSatisfy { atlas.city($0.originID) != nil && atlas.city($0.terminusID) != nil })
        XCTAssertTrue(atlas.passengerRoutes.allSatisfy { route in
            zip(route.stops, route.stops.dropFirst()).allSatisfy { $0.mile <= $1.mile }
        })
    }

    func testCaliforniaZephyrMileageMatchesTheTimetable() async throws {
        let atlas = try await loadAtlas()
        let zephyr = try XCTUnwrap(atlas.passengerRoutes.first { $0.id == "california-zephyr" })

        // Amtrak publishes 2,438 miles Chicago–Emeryville.
        XCTAssertEqual(Double(zephyr.miles), 2438, accuracy: 60)
        XCTAssertTrue(zephyr.serves("denver"))
        XCTAssertTrue(zephyr.serves("salt-lake-city"))
    }

    func testPassengerConnectionsBetweenTwoCities() async throws {
        let atlas = try await loadAtlas()
        let trips = atlas.passengerConnections(from: "chicago", to: "denver")
        let zephyr = try XCTUnwrap(trips.first { $0.route.id == "california-zephyr" })

        XCTAssertEqual(Double(zephyr.miles), 1038, accuracy: 50)
        XCTAssertTrue(zephyr.intermediateStopIDs.contains("omaha"))
        XCTAssertLessThan(zephyr.path.first!.roughMiles(to: atlas.city("chicago")!.coordinate), 15)
        XCTAssertLessThan(zephyr.path.last!.roughMiles(to: atlas.city("denver")!.coordinate), 15)
        XCTAssertEqual(atlas.passengerConnections(from: "denver", to: "chicago").first?.miles, trips.first?.miles)
    }

    func testFreightConnectionsFollowEachRailroadsOwnTrack() async throws {
        let atlas = try await loadAtlas()
        let routes = atlas.freightConnections(from: "chicago", to: "los-angeles")

        XCTAssertTrue(routes.contains { $0.railroad == .bnsf })
        XCTAssertTrue(routes.contains { $0.railroad == .unionPacific })
        XCTAssertFalse(routes.contains { $0.railroad == .csx })
        let bnsf = try XCTUnwrap(routes.first { $0.railroad == .bnsf })
        XCTAssertEqual(Double(bnsf.miles), 2200, accuracy: 200)
        XCTAssertLessThan(bnsf.path.first!.roughMiles(to: atlas.city("chicago")!.coordinate), 25)
        XCTAssertLessThan(bnsf.path.last!.roughMiles(to: atlas.city("los-angeles")!.coordinate), 25)
    }

    func testFreightTreesAreWellFormed() async throws {
        let atlas = try await loadAtlas()
        for network in atlas.freightNetworks {
            for (index, branch) in network.branches.enumerated() {
                if let parent = branch.parent {
                    XCTAssertLessThan(parent, index, "\(network.id) branch \(index) points forward")
                }
                XCTAssertGreaterThanOrEqual(branch.weight, branch.endCityIDs.count)
            }
            XCTAssertFalse(network.destinationIDs.contains(network.hubID))
        }
    }

    func testExplorerSwitchesModesAndClearsUnreachableDestinations() async {
        let model = RouteExplorerViewModel(provider: BundledRouteAtlasService(url: Self.atlasURL))
        await model.load()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.originID, "chicago")
        XCTAssertFalse(model.lines.isEmpty)
        XCTAssertTrue(model.legend.contains { $0.title == "California Zephyr" })

        model.destinationID = "glenwood-springs"
        XCTAssertFalse(model.passengerConnections.isEmpty)

        model.mode = .freight
        XCTAssertNil(model.destinationID, "Glenwood Springs is not a freight hub")
        XCTAssertTrue(model.legend.contains { $0.title == "BNSF" })

        model.destinationID = "los-angeles"
        XCTAssertTrue(model.lines.allSatisfy(\.isHighlighted))
        XCTAssertGreaterThanOrEqual(model.freightConnections.count, 2)

        model.originID = "los-angeles"
        XCTAssertNil(model.destinationID)
    }

    func testFailedLoadIsReported() async {
        let model = RouteExplorerViewModel(provider: BundledRouteAtlasService(url: nil))
        await model.load()
        XCTAssertEqual(model.loadState, .failed(message: RailDataError.unavailable.localizedDescription))
    }
}
