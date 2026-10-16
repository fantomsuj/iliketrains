import XCTest
@testable import TrainsCore

/// Runs the same hand-worked vectors as the server's motion tests, so both implementations agree.
final class MotionTests: XCTestCase {
    struct Vectors: Decodable {
        struct DistanceCase: Decodable { var name: String; var plan: MotionPlan; var samples: [[Double]] }
        struct SmoothCase: Decodable { var name: String; var displayed: Double; var target: Double; var dt: Double; var expect: Double; var snapped: Bool }
        var distance: [DistanceCase]
        var smooth: [SmoothCase]
    }

    func loadVectors() throws -> Vectors {
        // Single source of truth lives with the server tests.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../server/test/fixtures/motion-vectors.json").standardizedFileURL
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    func testDistanceVectors() throws {
        let v = try loadVectors()
        XCTAssertFalse(v.distance.isEmpty)
        for c in v.distance {
            for s in c.samples {
                XCTAssertEqual(Motion.distanceAt(c.plan, s[0]), s[1], accuracy: 0.01, "\(c.name) at t=\(s[0])")
            }
        }
    }

    func testSmoothVectors() throws {
        for c in try loadVectors().smooth {
            let r = Motion.smoothStep(displayed: c.displayed, target: c.target, dt: c.dt)
            XCTAssertEqual(r.d, c.expect, accuracy: 0.01, c.name)
            XCTAssertEqual(r.snapped, c.snapped, c.name)
        }
    }

    func testMonotonicOnRandomPlans() {
        var seed: UInt64 = 42
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for _ in 0..<200 {
            var stops: [PlanStop] = []
            var d = rnd() * 2000, t = -60000 + rnd() * 120000
            for _ in 0..<(1 + Int(rnd() * 5)) { d += 500 + rnd() * 8000; t += rnd() * 400000 - 50000; stops.append(PlanStop(d: d, arr: t, dep: t + rnd() * 60000)) }
            let plan = MotionPlan(d0: rnd() * 1000, t0: 0, fallbackSpeed: 1 + rnd() * 40, maxSpeed: 10 + rnd() * 70, stops: stops, maxD: d)
            var prev = -Double.infinity
            var s = -10000.0
            while s < 2_000_000 {
                let x = Motion.distanceAt(plan, s)
                XCTAssertGreaterThanOrEqual(x, prev - 1e-6)
                XCTAssertLessThanOrEqual(x, plan.maxD + 1e-6)
                prev = x; s += 997
            }
        }
    }
}
