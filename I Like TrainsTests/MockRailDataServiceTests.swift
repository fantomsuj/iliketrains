import XCTest
@testable import ILikeTrainsData

final class MockRailDataServiceTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testTrainFixturesHaveUniqueIDsAndValidCoordinates() async throws {
        let trains = try await MockRailDataService(referenceDate: referenceDate).trains()

        XCTAssertGreaterThanOrEqual(trains.count, 6)
        XCTAssertEqual(Set(trains.map(\.id)).count, trains.count)
        XCTAssertTrue(trains.allSatisfy { $0.coordinate.isValid })
        XCTAssertTrue(trains.allSatisfy { $0.updatedAt <= referenceDate })
    }

    func testInfrastructureContainsRenderableMainlinesAndStations() async throws {
        let segments = try await MockRailDataService(referenceDate: referenceDate).railSegments()

        XCTAssertGreaterThanOrEqual(segments.count, 5)
        XCTAssertTrue(segments.allSatisfy { $0.coordinates.count >= 2 })
        XCTAssertTrue(segments.flatMap(\.stations).contains { $0.code == "CHI" })
        XCTAssertTrue(segments.flatMap(\.stations).allSatisfy { $0.coordinate.isValid })
    }

    func testFreightSightingsExposeConfidenceAgeAndReporterContext() async throws {
        let sightings = try await MockRailDataService(referenceDate: referenceDate).freightSightings()

        XCTAssertGreaterThanOrEqual(sightings.count, 4)
        XCTAssertTrue(sightings.allSatisfy { 0 ... 1 ~= $0.confidence })
        XCTAssertTrue(sightings.allSatisfy { $0.observedAt <= referenceDate })
        XCTAssertTrue(sightings.allSatisfy { $0.reporterCount > 0 })
    }

    func testConfiguredFailureIsDeliveredByEveryProvider() async {
        let service = MockRailDataService(referenceDate: referenceDate, shouldFail: true)

        await XCTAssertThrowsErrorAsync { try await service.trains() }
        await XCTAssertThrowsErrorAsync { try await service.railSegments() }
        await XCTAssertThrowsErrorAsync { try await service.freightSightings() }
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            XCTAssertNotNil(error, file: file, line: line)
        }
    }
}
