import Foundation

public struct Coordinate: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/// A route line with cumulative distance (metres), the geometry every train moves along.
public struct RouteLine: Sendable {
    public let coords: [Coordinate]
    public let cum: [Double]
    public var length: Double { cum.last ?? 0 }

    public init(coords: [Coordinate]) {
        self.coords = coords
        var c = [Double](repeating: 0, count: coords.count)
        for i in coords.indices.dropFirst() { c[i] = c[i - 1] + Geo.haversine(coords[i - 1], coords[i]) }
        self.cum = c
    }

    public init(encoded: String) { self.init(coords: Geo.decodePolyline(encoded)) }

    /// Position and heading (degrees) at distance `d` along the line.
    public func point(at d: Double) -> (Coordinate, Double) {
        guard coords.count > 1 else { return (coords.first ?? Coordinate(lat: 0, lon: 0), 0) }
        let dd = min(max(d, 0), length)
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if cum[mid] <= dd { lo = mid } else { hi = mid } }
        let i = min(lo, coords.count - 2)
        let a = coords[i], b = coords[i + 1]
        let seg = cum[i + 1] - cum[i]
        let t = seg > 0 ? (dd - cum[i]) / seg : 0
        return (Coordinate(lat: a.lat + t * (b.lat - a.lat), lon: a.lon + t * (b.lon - a.lon)), Geo.bearing(a, b))
    }
}

public enum Geo {
    static let r = 6371008.8
    static let rad = Double.pi / 180

    public static func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad
        let s = pow(sin(dLat / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(dLon / 2), 2)
        return 2 * r * asin(min(1, s.squareRoot()))
    }

    public static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let y = sin((b.lon - a.lon) * rad) * cos(b.lat * rad)
        let x = cos(a.lat * rad) * sin(b.lat * rad) - sin(a.lat * rad) * cos(b.lat * rad) * cos((b.lon - a.lon) * rad)
        return (atan2(y, x) / rad + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Google encoded polyline, precision 1e5 (the server's encoding).
    public static func decodePolyline(_ s: String, precision: Double = 1e5) -> [Coordinate] {
        let bytes = Array(s.utf8)
        var out: [Coordinate] = [], i = 0, lat = 0, lon = 0
        func next() -> Int {
            var result = 0, shift = 0, b = 0
            repeat { b = Int(bytes[i]) - 63; i += 1; result |= (b & 0x1f) << shift; shift += 5 } while b >= 0x20 && i < bytes.count
            return (result & 1) != 0 ? ~(result >> 1) : result >> 1
        }
        while i < bytes.count {
            lat += next(); if i >= bytes.count { break }
            lon += next()
            out.append(Coordinate(lat: Double(lat) / precision, lon: Double(lon) / precision))
        }
        return out
    }
}
