import Foundation
import Observation
import TrainsCore

/// Live state for the whole app: trains, events, route geometry, and the server clock.
@MainActor @Observable
final class LiveStore {
    enum Connection: Equatable { case connecting, live, reconnecting }

    let config: AppConfig
    let api: API
    private(set) var trains: [String: TrainSummary] = [:]
    private(set) var events: [LiveEvent] = []
    private(set) var connection: Connection = .connecting
    private(set) var isDemo = false
    private(set) var stations: [StationSummary] = []
    private(set) var overview: RouteOverview?
    /// Bumped whenever the set of trains changes; the map redraws from `trains` every frame anyway.
    private(set) var revision = 0
    /// The most recent event for each train (drives haptics on the open card).
    private(set) var lastEventByTrain: [String: LiveEvent] = [:]

    @ObservationIgnored private var lines: [String: RouteLine] = [:]
    @ObservationIgnored private var pendingShapes = Set<String>()
    @ObservationIgnored private var clockOffsetMs: Double = 0
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var backoff: Double = 1
    let animator = TrainAnimator()

    init(config: AppConfig) {
        self.config = config
        self.api = API(base: config.serverURL)
    }

    /// Server time in epoch ms (the server's clock drives all motion, which also makes demo replay work).
    var now: EpochMs { Date().timeIntervalSince1970 * 1000 + clockOffsetMs }

    func line(_ key: String) -> RouteLine? { lines[key] }

    func start() {
        Task { await loadStatic() }
        connect()
    }

    private func loadStatic() async {
        async let s = try? api.stations()
        async let o = try? api.routes()
        stations = await s ?? []
        overview = await o
        for r in overview?.routes ?? [] where lines[r.key] == nil { lines[r.key] = RouteLine(encoded: r.polyline) }
    }

    private func connect() {
        socket?.cancel()
        let task = URLSession.shared.webSocketTask(with: config.liveURL)
        socket = task
        task.resume()
        Task { await receive(task) }
    }

    private func receive(_ task: URLSessionWebSocketTask) async {
        while task === socket {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: continue
                }
                apply(try JSONDecoder().decode(LiveMessage.self, from: data))
                connection = .live
                backoff = 1
            } catch {
                guard task === socket else { return }
                connection = .reconnecting
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
                connect()
                return
            }
        }
    }

    private func apply(_ msg: LiveMessage) {
        switch msg {
        case .snapshot(let s):
            clockOffsetMs = s.serverTime - Date().timeIntervalSince1970 * 1000
            isDemo = s.demo
            trains = Dictionary(uniqueKeysWithValues: s.trains.map { ($0.id, $0) })
            events = s.events
            s.trains.forEach { ensureShape($0.shape) }
            revision += 1
        case .trains(_, let serverTime, let list, let removed):
            clockOffsetMs = serverTime - Date().timeIntervalSince1970 * 1000
            for t in list { trains[t.id] = t; ensureShape(t.shape) }
            for id in removed { trains[id] = nil }
            revision += 1
        case .event(_, let e):
            events.insert(e, at: 0)
            if events.count > 60 { events.removeLast(events.count - 60) }
            lastEventByTrain[e.trainId] = e
        case .unknown:
            break
        }
    }

    private func ensureShape(_ key: String?) {
        guard let key, lines[key] == nil, !pendingShapes.contains(key) else { return }
        pendingShapes.insert(key)
        Task {
            if let r = try? await api.shape(key) { lines[key] = RouteLine(encoded: r.polyline) }
            pendingShapes.remove(key)
        }
    }

    /// Progress 0...1 between first and last stop, from the distance currently drawn on the map.
    func liveProgress(_ detail: TrainDetail) -> Double {
        let placed = detail.stops.filter { $0.d >= 0 }
        guard let first = placed.first?.d, let last = placed.last?.d, last > first else { return detail.progress }
        let d = animator.shownDistance(detail.id) ?? trains[detail.id].flatMap { t in t.plan.map { Motion.distanceAt($0, now) } } ?? first
        return min(1, max(0, (d - first) / (last - first)))
    }
}
