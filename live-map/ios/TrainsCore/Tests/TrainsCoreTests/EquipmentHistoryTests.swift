import XCTest
@testable import TrainsCore

/// Real server responses: a Long Island train with its live consist, an Amtrak train with
/// typical equipment, and Acela 2150's 14-day history.
final class EquipmentHistoryTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    func testLiveConsistDecodes() throws {
        let t = try JSONDecoder().decode(TrainDetail.self, from: fixture("train"))
        let e = try XCTUnwrap(t.equipment)
        XCTAssertTrue(e.live)
        XCTAssertEqual(e.name, "Bombardier M7 electric")
        let cars = try XCTUnwrap(e.cars)
        XCTAssertEqual(cars.count, e.carsRunning)
        XCTAssertEqual(cars.map(\.position), Array(1...cars.count), "front first, numbered")
        XCTAssertTrue(cars.allSatisfy { $0.number != nil })
    }

    func testTypicalAmtrakEquipmentDecodes() throws {
        let t = try JSONDecoder().decode(TrainDetail.self, from: fixture("train-amtrak"))
        let e = try XCTUnwrap(t.equipment)
        XCTAssertFalse(e.live)
        XCTAssertNil(e.cars)
        XCTAssertFalse((e.summary ?? "").isEmpty)
    }

    func testHistoryDecodesWithCountedAndExcludedDays() throws {
        let h = try JSONDecoder().decode(HistorySummary.self, from: fixture("history"))
        XCTAssertEqual(h.days.count, 14)
        XCTAssertEqual(h.thresholdMin, 10)
        XCTAssertEqual(h.scoredRuns, h.days.filter { $0.scored && $0.delayMin != nil }.count)
        XCTAssertTrue(h.days.contains { !$0.scored && $0.flag != nil && $0.status == "completed" }, "some archive days are shown but not counted")
    }

    func testWording() {
        XCTAssertEqual(Wording.lengthNote(running: 12, scheduled: 10), "2 extra cars")
        XCTAssertEqual(Wording.lengthNote(running: 7, scheduled: 8), "1 car short")
        XCTAssertNil(Wording.lengthNote(running: 8, scheduled: 8))
        XCTAssertEqual(Wording.minutes(-13), "13 min early")
        XCTAssertEqual(Wording.minutes(1), "on time")
        XCTAssertEqual(Wording.loading("FEW_SEATS"), "Few seats")
        XCTAssertEqual(Wording.loading("NO_DATA"), "No sensor")
    }
}
