import XCTest
@testable import TrainsCore

/// Decodes real server responses captured from the live feed (Fixtures/), so model drift breaks the build.
final class DecodingTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    func testSnapshotDecodes() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: fixture("snapshot"))
        XCTAssertFalse(s.trains.isEmpty)
        XCTAssertTrue(s.trains.contains { $0.fix == .gps && $0.plan != nil })
        XCTAssertEqual(Set(s.trains.map(\.operator)), Set(Operator.allCases))
    }

    func testWebSocketSnapshotMessageDecodes() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("snapshot")) as? [String: Any])
        obj["type"] = "snapshot"
        let msg = try JSONDecoder().decode(LiveMessage.self, from: JSONSerialization.data(withJSONObject: obj))
        guard case .snapshot(let s) = msg else { return XCTFail("expected snapshot") }
        XCTAssertFalse(s.trains.isEmpty)
    }

    func testTrainDetailAndBoardDecode() throws {
        let t = try JSONDecoder().decode(TrainDetail.self, from: fixture("train"))
        XCTAssertGreaterThan(t.stops.count, 1)
        let b = try JSONDecoder().decode(Board.self, from: fixture("board"))
        XCTAssertFalse(b.rows.isEmpty)
    }

    func testWording() {
        XCTAssertEqual(Wording.lateness(30), "On time")
        XCTAssertEqual(Wording.lateness(240), "4 min late")
        XCTAssertEqual(Wording.lateness(-180), "3 min early")
        XCTAssertEqual(Wording.countdown(to: 10_000, now: 0), "now")
        XCTAssertEqual(Wording.countdown(to: 4 * 60_000, now: 0), "4 min")
        XCTAssertEqual(Wording.countdown(to: 72 * 60_000, now: 0), "1 h 12 m")
        XCTAssertEqual(Wording.punctuality(delaySec: 400, status: .enroute, source: .live), .late)
        XCTAssertEqual(Wording.punctuality(delaySec: 0, status: .enroute, source: .scheduled), .noData)
    }
}
