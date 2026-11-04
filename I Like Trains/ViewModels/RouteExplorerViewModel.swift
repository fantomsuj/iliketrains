import Foundation
import Observation

/// Drives the route explorer: pick a city, then see every passenger service or
/// single-railroad freight route that leaves it, and optionally narrow to one destination.
@MainActor
@Observable
public final class RouteExplorerViewModel {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case passenger
        case freight

        public var id: Self { self }

        public var title: String {
            switch self {
            case .passenger: "Passenger"
            case .freight: "Freight"
            }
        }
    }

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    /// One coloured line on the map.
    public struct Line: Identifiable, Hashable, Sendable {
        public enum Style: Hashable, Sendable {
            /// Index into the passenger palette.
            case palette(Int)
            case railroad(RailOperator)
        }

        public let id: String
        public let style: Style
        /// 0...1, scales stroke width.
        public let weight: Double
        public let isHighlighted: Bool
        public let path: [RailCoordinate]
    }

    /// One row of the legend under the map.
    public struct LegendEntry: Identifiable, Hashable, Sendable {
        public let id: String
        public let style: Line.Style
        public let title: String
        public let detail: String
        /// Share of reachable destinations this entry covers, 0...1.
        public let share: Double
    }

    public static let featuredCityIDs = [
        "chicago", "new-york", "los-angeles", "houston", "denver", "atlanta", "seattle",
        "kansas-city", "new-orleans", "salt-lake-city", "miami", "st-paul", "washington", "dallas"
    ]

    public static let passengerPaletteSize = 8

    public private(set) var atlas: RouteAtlas?
    public private(set) var loadState: LoadState = .idle
    public var mode: Mode = .passenger {
        didSet { normalizeSelection() }
    }
    public var originID: AtlasCity.ID = "chicago" {
        didSet {
            if destinationID == originID { destinationID = nil }
            normalizeSelection()
        }
    }
    public var destinationID: AtlasCity.ID?

    @ObservationIgnored private let provider: any RouteAtlasProviding

    public init(provider: any RouteAtlasProviding) {
        self.provider = provider
    }

    public func load() async {
        loadState = .loading
        do {
            atlas = try await provider.routeAtlas()
            loadState = .loaded
            normalizeSelection()
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }

    // MARK: Cities

    public var origin: AtlasCity? { atlas?.city(originID) }
    public var destination: AtlasCity? { destinationID.flatMap { atlas?.city($0) } }

    /// Cities that have something to show in the current mode, alphabetised.
    public var originChoices: [AtlasCity] {
        guard let atlas else { return [] }
        return atlas.cities
            .filter { city in
                switch mode {
                case .passenger: !atlas.passengerRoutes(serving: city.id).isEmpty
                case .freight: !atlas.freightNetworks(from: city.id).isEmpty
                }
            }
            .sorted { $0.name < $1.name }
    }

    public var featuredCities: [AtlasCity] {
        let available = Set(originChoices.map(\.id))
        return Self.featuredCityIDs.filter(available.contains).compactMap { atlas?.city($0) }
    }

    /// Cities reachable from the origin without changing trains or railroads, nearest first.
    public var destinationChoices: [AtlasCity] {
        guard let atlas, let origin else { return [] }
        let ids = mode == .passenger
            ? atlas.passengerDestinations(from: originID)
            : atlas.freightDestinations(from: originID)
        return ids.compactMap { atlas.city($0) }
            .sorted { $0.coordinate.roughMiles(to: origin.coordinate) < $1.coordinate.roughMiles(to: origin.coordinate) }
    }

    // MARK: Headline

    public var headline: String {
        switch (mode, destination) {
        case (.passenger, nil): "Passenger trains from"
        case (.freight, nil): "Freight railroads from"
        case (.passenger, .some): "Trains between"
        case (.freight, .some): "Freight routes between"
        }
    }

    public var title: String {
        guard let origin else { return "" }
        guard let destination else { return origin.displayName }
        return "\(origin.name) → \(destination.name)"
    }

    public var summary: String {
        guard let atlas else { return "" }
        if destinationID != nil {
            switch mode {
            case .passenger:
                let count = passengerConnections.count
                guard let shortest = passengerConnections.first else { return "No one-seat ride. Try connecting through a hub." }
                return "\(count) direct \(count == 1 ? "train" : "trains") · shortest \(shortest.miles.formatted()) mi"
            case .freight:
                let count = freightConnections.count
                guard let shortest = freightConnections.first else { return "No single railroad connects these cities." }
                return "\(count) \(count == 1 ? "railroad" : "railroads") · shortest \(shortest.miles.formatted()) mi"
            }
        }
        switch mode {
        case .passenger:
            let routes = atlas.passengerRoutes(serving: originID).count
            let reach = atlas.passengerDestinations(from: originID).count
            return "\(routes) \(routes == 1 ? "service" : "services") · \(reach) cities without changing trains"
        case .freight:
            let railroads = atlas.freightNetworks(from: originID).count
            let reach = atlas.freightDestinations(from: originID).count
            return "\(railroads) Class I \(railroads == 1 ? "railroad" : "railroads") · \(reach) hubs on a single railroad"
        }
    }

    // MARK: Connections

    public var passengerConnections: [PassengerConnection] {
        guard let atlas, let destinationID else { return [] }
        return atlas.passengerConnections(from: originID, to: destinationID)
    }

    public var freightConnections: [FreightConnection] {
        guard let atlas, let destinationID else { return [] }
        return atlas.freightConnections(from: originID, to: destinationID)
    }

    // MARK: Map lines

    public var lines: [Line] {
        guard let atlas else { return [] }
        switch mode {
        case .passenger:
            let routes = atlas.passengerRoutes(serving: originID)
            let highlighted = Set(passengerConnections.map(\.route.id))
            return routes.enumerated().map { index, route in
                let isHighlighted = highlighted.contains(route.id)
                let connection = passengerConnections.first { $0.route.id == route.id }
                return Line(
                    id: route.id,
                    style: passengerStyle(for: route, index: index),
                    weight: route.kind == .longDistance ? 0.75 : 0.5,
                    isHighlighted: destinationID == nil || isHighlighted,
                    path: connection?.path ?? route.path
                )
            }
        case .freight:
            if destinationID != nil {
                return freightConnections.map {
                    Line(id: $0.railroad.rawValue, style: .railroad($0.railroad), weight: 1, isHighlighted: true, path: $0.path)
                }
            }
            let networks = atlas.freightNetworks(from: originID)
            let maxWeight = Double(networks.flatMap(\.branches).map(\.weight).max() ?? 1)
            return networks.flatMap { network in
                network.branches.enumerated().map { index, branch in
                    Line(
                        id: "\(network.id)-\(index)",
                        style: .railroad(network.railroad),
                        weight: (Double(branch.weight) / maxWeight).squareRoot(),
                        isHighlighted: true,
                        path: branch.path
                    )
                }
            }
        }
    }

    /// Cities to label on the map: the origin, the destination, and every reachable city.
    public var mapCities: [AtlasCity] {
        let ids = Set(destinationChoices.map(\.id))
        return (atlas?.cities ?? []).filter { ids.contains($0.id) }
    }

    // MARK: Legend

    public var legend: [LegendEntry] {
        guard let atlas, let origin else { return [] }
        switch mode {
        case .passenger:
            if destinationID != nil {
                return passengerConnections.enumerated().map { _, connection in
                    let index = atlas.passengerRoutes(serving: originID).firstIndex { $0.id == connection.route.id } ?? 0
                    let stops = connection.intermediateStopIDs.count
                    return LegendEntry(
                        id: connection.route.id,
                        style: passengerStyle(for: connection.route, index: index),
                        title: connection.route.name,
                        detail: "\(connection.miles.formatted()) mi · \(stops == 0 ? "nonstop between major cities" : "\(stops) major \(stops == 1 ? "stop" : "stops") between")",
                        share: 1
                    )
                }
            }
            let routes = atlas.passengerRoutes(serving: originID)
            let reach = max(atlas.passengerDestinations(from: originID).count, 1)
            return routes.enumerated().map { index, route in
                let destinations = Set(route.stops.map(\.cityID)).subtracting([originID])
                return LegendEntry(
                    id: route.id,
                    style: passengerStyle(for: route, index: index),
                    title: route.name,
                    detail: passengerDetail(route, atlas: atlas, origin: origin),
                    share: Double(destinations.count) / Double(reach)
                )
            }
        case .freight:
            if destinationID != nil {
                return freightConnections.map { connection in
                    LegendEntry(
                        id: connection.railroad.rawValue,
                        style: .railroad(connection.railroad),
                        title: connection.railroad.displayName,
                        detail: connection.via.isEmpty
                            ? "\(connection.miles.formatted()) mi"
                            : "\(connection.miles.formatted()) mi · via \(connection.via.joined(separator: ", "))",
                        share: 1
                    )
                }
            }
            let networks = atlas.freightNetworks(from: originID)
            let reach = max(atlas.freightDestinations(from: originID).count, 1)
            return networks.map { network in
                let farthest = network.destinationIDs
                    .compactMap { atlas.city($0) }
                    .max { $0.coordinate.roughMiles(to: origin.coordinate) < $1.coordinate.roughMiles(to: origin.coordinate) }
                let count = network.destinationIDs.count
                return LegendEntry(
                    id: network.id,
                    style: .railroad(network.railroad),
                    title: network.railroad.shortName,
                    detail: "\(count) \(count == 1 ? "hub" : "hubs")" + (farthest.map { " · as far as \($0.name)" } ?? ""),
                    share: Double(count) / Double(reach)
                )
            }
        }
    }

    // MARK: Helpers

    private func passengerStyle(for route: PassengerRoute, index: Int) -> Line.Style {
        route.railOperator == .amtrak ? .palette(index % Self.passengerPaletteSize) : .railroad(route.railOperator)
    }

    private func passengerDetail(_ route: PassengerRoute, atlas: RouteAtlas, origin: AtlasCity) -> String {
        let from = atlas.city(route.originID)?.name ?? route.originID
        let to = atlas.city(route.terminusID)?.name ?? route.terminusID
        let ends = "\(from) – \(to) · \(route.miles.formatted()) mi"
        if route.originID == origin.id || route.terminusID == origin.id {
            let other = route.originID == origin.id ? route.terminusID : route.originID
            if let far = atlas.city(other) {
                return ends + " · to the \(origin.coordinate.compassWord(to: far.coordinate))"
            }
        }
        return ends + " · passes through"
    }

    private func normalizeSelection() {
        guard atlas != nil else { return }
        let choices = originChoices
        if !choices.contains(where: { $0.id == originID }), let fallback = featuredCities.first ?? choices.first {
            originID = fallback.id
            return
        }
        if let destinationID, !destinationChoices.contains(where: { $0.id == destinationID }) {
            self.destinationID = nil
        }
    }
}

extension RailCoordinate {
    /// Great-circle distance in miles.
    public func roughMiles(to other: RailCoordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 3958.8 * 2 * asin(min(1, h.squareRoot()))
    }

    /// Eight-point compass direction from this coordinate toward `other`, e.g. "southwest".
    public func compassWord(to other: RailCoordinate) -> String {
        let dx = (other.longitude - longitude) * cos((latitude + other.latitude) / 2 * .pi / 180)
        let dy = other.latitude - latitude
        let degrees = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let words = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return words[Int((degrees + 22.5) / 45) % 8]
    }
}
