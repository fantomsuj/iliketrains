import Foundation
import TrainsCore

/// REST calls to the Trains server.
struct API {
    let base: URL
    private let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.percentEncodedPath = (c.percentEncodedPath.hasSuffix("/") ? String(c.percentEncodedPath.dropLast()) : c.percentEncodedPath) + path
        if !query.isEmpty { c.queryItems = query }
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decoder.decode(T.self, from: data)
    }

    private static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    func snapshot() async throws -> Snapshot { try await get("/api/snapshot") }
    func train(_ id: String) async throws -> TrainDetail { try await get("/api/trains/" + Self.encode(id)) }
    func board(_ hubId: String) async throws -> Board { try await get("/api/stations/" + Self.encode(hubId) + "/board") }
    func search(_ q: String) async throws -> SearchResult { try await get("/api/search", query: [URLQueryItem(name: "q", value: q)]) }
    func stations() async throws -> [StationSummary] { (try await get("/api/stations") as StationsResponse).stations }
    func routes() async throws -> RouteOverview { try await get("/api/routes") }
    func shape(_ key: String) async throws -> ShapeResponse { try await get("/api/shapes/" + Self.encode(key)) }
    /// Raw JSON for the "view raw record" sheet.
    func rawTrain(_ id: String) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("api/trains").appendingPathComponent(id))
        let obj = try JSONSerialization.jsonObject(with: data)
        return String(data: try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? ""
    }
    private struct StationsResponse: Decodable { var stations: [StationSummary] }
}
