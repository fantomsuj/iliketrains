import XCTest
@testable import TrainsCore

final class GeometryAndAnimatorTests: XCTestCase {
    /// "_p~iF~ps|U_ulLnnqC_mqNvxq`@" is Google's documented example polyline.
    func testDecodePolylineMatchesReferenceExample() {
        let c = Geo.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].lat, 38.5, accuracy: 1e-9); XCTAssertEqual(c[0].lon, -120.2, accuracy: 1e-9)
        XCTAssertEqual(c[1].lat, 40.7, accuracy: 1e-9); XCTAssertEqual(c[1].lon, -120.95, accuracy: 1e-9)
        XCTAssertEqual(c[2].lat, 43.252, accuracy: 1e-9); XCTAssertEqual(c[2].lon, -126.453, accuracy: 1e-9)
    }

    func testPointAtInterpolatesAlongCumulativeDistance() {
        // 0.01 degrees of latitude is ~1112 m; heading due north
        let line = RouteLine(coords: [Coordinate(lat: 41.0, lon: -73.0), Coordinate(lat: 41.01, lon: -73.0), Coordinate(lat: 41.02, lon: -73.0)])
        XCTAssertEqual(line.length, 2223.9, accuracy: 1)
        let (mid, heading) = line.point(at: line.length / 2)
        XCTAssertEqual(mid.lat, 41.01, accuracy: 1e-6)
        XCTAssertEqual(heading, 0, accuracy: 0.01)
        XCTAssertEqual(line.point(at: -50).0, line.coords[0], "clamped at the start")
        XCTAssertEqual(line.point(at: 1e9).0, line.coords[2], "clamped at the end")
    }

    func makeTrain(id: String = "t", plan: MotionPlan?) -> TrainSummary {
        TrainSummary(id: id, operator: .lirr, tripId: id, trainNumber: "1", route: "", routeName: "", headsign: "", color: "#fff", shape: "s",
                     distM: plan?.d0 ?? 0, lat: nil, lon: nil, bearing: 0, speedMps: 0, delaySec: 0, source: .live, fix: .gps, status: .enroute,
                     updatedAt: 0, plan: plan, origin: "", destination: "", progress: 0, next: nil)
    }

    func testAnimatorGlidesAndNeverGoesBackward() {
        let line = RouteLine(coords: (0...100).map { Coordinate(lat: 41 + Double($0) * 0.001, lon: -73) }) // ~11 km
        let anim = TrainAnimator()
        var plan = MotionPlan(d0: 1000, t0: 0, fallbackSpeed: 30, maxSpeed: 60, stops: [], maxD: line.length)
        var shown: [Double] = []
        // 25 s at 60 fps; at 5 s a new plan puts the train 400 m behind where it was drawn
        for f in 0..<1500 {
            let now = Double(f) / 60 * 1000
            if f == 300 { plan = MotionPlan(d0: 1000 + 30 * 5 - 400, t0: 5000, fallbackSpeed: 30, maxSpeed: 60, stops: [], maxD: line.length) }
            let frames = anim.step(now: now, dt: 1.0 / 60, trains: [makeTrain(plan: plan)], lines: { _ in line })
            shown.append(frames[0].distance)
        }
        for i in 1..<shown.count { XCTAssertGreaterThanOrEqual(shown[i], shown[i - 1] - 1e-9, "frame \(i) moved backward") }
        // it held still until the corrected plan caught up (~12 s at 30 m/s), then resumed
        XCTAssertEqual(shown[900], shown[300], accuracy: 1e-6)
        XCTAssertGreaterThan(shown[1499], shown[300] + 100)
    }

    func testAnimatorFadesOnLargeCorrection() {
        let line = RouteLine(coords: (0...100).map { Coordinate(lat: 41 + Double($0) * 0.001, lon: -73) })
        let anim = TrainAnimator()
        let a = MotionPlan(d0: 9000, t0: 0, fallbackSpeed: 30, maxSpeed: 60, stops: [], maxD: line.length)
        for f in 0..<120 { _ = anim.step(now: Double(f) * 16, dt: 1.0 / 60, trains: [makeTrain(plan: a)], lines: { _ in line }) }
        let b = MotionPlan(d0: 2000, t0: 2000, fallbackSpeed: 30, maxSpeed: 60, stops: [], maxD: line.length) // 7 km back
        let f = anim.step(now: 2000, dt: 1.0 / 60, trains: [makeTrain(plan: b)], lines: { _ in line })[0]
        XCTAssertEqual(f.distance, 2000, accuracy: 1)
        XCTAssertLessThan(f.opacity, 0.1, "snapped trains fade back in rather than sliding backward")
    }
}
