import Foundation

/// A city the route atlas knows about: a passenger stop, a freight hub, or both.
public struct AtlasCity: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let region: String
    public let coordinate: RailCoordinate
    public let isFreightHub: Bool

    public init(id: String, name: String, region: String, coordinate: RailCoordinate, isFreightHub: Bool) {
        self.id = id
        self.name = name
        self.region = region
        self.coordinate = coordinate
        self.isFreightHub = isFreightHub
    }

    public var displayName: String { "\(name), \(region)" }
}

/// A named passenger service traced on real track, with the mile marker of every city it serves.
public struct PassengerRoute: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case longDistance
        case corridor
    }

    public struct Stop: Hashable, Sendable {
        public let cityID: AtlasCity.ID
        public let mile: Int

        public init(cityID: AtlasCity.ID, mile: Int) {
            self.cityID = cityID
            self.mile = mile
        }
    }

    public let id: String
    public let name: String
    public let railOperator: RailOperator
    public let kind: Kind
    public let originID: AtlasCity.ID
    public let terminusID: AtlasCity.ID
    public let miles: Int
    public let stops: [Stop]
    public let path: [RailCoordinate]

    public init(
        id: String,
        name: String,
        railOperator: RailOperator,
        kind: Kind,
        originID: AtlasCity.ID,
        terminusID: AtlasCity.ID,
        miles: Int,
        stops: [Stop],
        path: [RailCoordinate]
    ) {
        self.id = id
        self.name = name
        self.railOperator = railOperator
        self.kind = kind
        self.originID = originID
        self.terminusID = terminusID
        self.miles = miles
        self.stops = stops
        self.path = path
    }

    public func serves(_ cityID: AtlasCity.ID) -> Bool {
        stops.contains { $0.cityID == cityID }
    }

    public func mile(of cityID: AtlasCity.ID) -> Int? {
        stops.first { $0.cityID == cityID }?.mile
    }
}

/// The tree of single-railroad freight routes radiating from one hub city.
///
/// Each branch runs from the end of its parent branch (or the hub) outward. `weight` counts how
/// many destination hubs are reached through that branch, so trunks are heavier than twigs.
public struct FreightNetwork: Identifiable, Hashable, Sendable {
    public struct Branch: Hashable, Sendable {
        public let parent: Int?
        public let weight: Int
        public let endCityIDs: [AtlasCity.ID]
        public let path: [RailCoordinate]

        public init(parent: Int?, weight: Int, endCityIDs: [AtlasCity.ID], path: [RailCoordinate]) {
            self.parent = parent
            self.weight = weight
            self.endCityIDs = endCityIDs
            self.path = path
        }
    }

    public let railroad: RailOperator
    public let hubID: AtlasCity.ID
    public let branches: [Branch]

    public var id: String { "\(railroad.rawValue)-\(hubID)" }

    public init(railroad: RailOperator, hubID: AtlasCity.ID, branches: [Branch]) {
        self.railroad = railroad
        self.hubID = hubID
        self.branches = branches
    }

    public var destinationIDs: [AtlasCity.ID] {
        branches.flatMap(\.endCityIDs)
    }

    /// Track from the hub to `cityID` on this railroad, or nil when it does not reach it.
    public func path(to cityID: AtlasCity.ID) -> [RailCoordinate]? {
        guard var index = branches.firstIndex(where: { $0.endCityIDs.contains(cityID) }) else { return nil }
        var pieces: [[RailCoordinate]] = []
        var guardCount = 0
        while guardCount <= branches.count {
            pieces.append(branches[index].path)
            guard let parent = branches[index].parent else { break }
            index = parent
            guardCount += 1
        }
        return pieces.reversed().reduce(into: []) { result, piece in
            result.append(contentsOf: result.last == piece.first ? Array(piece.dropFirst()) : piece)
        }
    }
}

/// Mileage and main subdivisions of the best single-railroad route between two hubs.
public struct FreightPair: Hashable, Sendable {
    public let railroad: RailOperator
    public let fromID: AtlasCity.ID
    public let toID: AtlasCity.ID
    public let miles: Int
    public let via: [String]

    public init(railroad: RailOperator, fromID: AtlasCity.ID, toID: AtlasCity.ID, miles: Int, via: [String]) {
        self.railroad = railroad
        self.fromID = fromID
        self.toID = toID
        self.miles = miles
        self.via = via
    }
}

/// A one-seat passenger trip between two cities.
public struct PassengerConnection: Identifiable, Hashable, Sendable {
    public let route: PassengerRoute
    public let miles: Int
    public let intermediateStopIDs: [AtlasCity.ID]
    public let path: [RailCoordinate]

    public var id: PassengerRoute.ID { route.id }
}

/// A single-railroad freight route between two hubs.
public struct FreightConnection: Identifiable, Hashable, Sendable {
    public let railroad: RailOperator
    public let miles: Int
    public let via: [String]
    public let path: [RailCoordinate]

    public var id: RailOperator { railroad }
}

/// Every passenger service and Class I freight route in the bundled dataset.
public struct RouteAtlas: Sendable {
    public let cities: [AtlasCity]
    public let passengerRoutes: [PassengerRoute]
    public let freightNetworks: [FreightNetwork]
    public let freightPairs: [FreightPair]
    public let sources: [String]

    private let cityIndex: [AtlasCity.ID: AtlasCity]

    public init(
        cities: [AtlasCity],
        passengerRoutes: [PassengerRoute],
        freightNetworks: [FreightNetwork],
        freightPairs: [FreightPair],
        sources: [String] = []
    ) {
        self.cities = cities
        self.passengerRoutes = passengerRoutes
        self.freightNetworks = freightNetworks
        self.freightPairs = freightPairs
        self.sources = sources
        self.cityIndex = Dictionary(cities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func city(_ id: AtlasCity.ID) -> AtlasCity? {
        cityIndex[id]
    }

    public func passengerRoutes(serving cityID: AtlasCity.ID) -> [PassengerRoute] {
        passengerRoutes
            .filter { $0.serves(cityID) }
            .sorted { $0.miles > $1.miles }
    }

    public func freightNetworks(from hubID: AtlasCity.ID) -> [FreightNetwork] {
        freightNetworks
            .filter { $0.hubID == hubID }
            .sorted { $0.destinationIDs.count > $1.destinationIDs.count }
    }

    /// Cities reachable without changing trains.
    public func passengerDestinations(from cityID: AtlasCity.ID) -> Set<AtlasCity.ID> {
        var result = Set(passengerRoutes(serving: cityID).flatMap { $0.stops.map(\.cityID) })
        result.remove(cityID)
        return result
    }

    /// Hubs reachable on a single railroad.
    public func freightDestinations(from hubID: AtlasCity.ID) -> Set<AtlasCity.ID> {
        Set(freightNetworks(from: hubID).flatMap(\.destinationIDs))
    }

    public func passengerConnections(from originID: AtlasCity.ID, to destinationID: AtlasCity.ID) -> [PassengerConnection] {
        guard originID != destinationID else { return [] }
        return passengerRoutes.compactMap { route in
            guard let start = route.mile(of: originID), let end = route.mile(of: destinationID) else { return nil }
            let low = min(start, end)
            let high = max(start, end)
            var between = route.stops
                .filter { $0.mile > low && $0.mile < high }
                .map(\.cityID)
            if start > end { between.reverse() }
            return PassengerConnection(
                route: route,
                miles: high - low,
                intermediateStopIDs: between,
                path: slice(route, from: originID, to: destinationID)
            )
        }
        .sorted { ($0.miles, $0.route.name) < ($1.miles, $1.route.name) }
    }

    public func freightConnections(from originID: AtlasCity.ID, to destinationID: AtlasCity.ID) -> [FreightConnection] {
        guard originID != destinationID else { return [] }
        return freightNetworks(from: originID).compactMap { network in
            guard let path = network.path(to: destinationID) else { return nil }
            let pair = freightPairs.first {
                $0.railroad == network.railroad
                    && Set([$0.fromID, $0.toID]) == Set([originID, destinationID])
            }
            return FreightConnection(
                railroad: network.railroad,
                miles: pair?.miles ?? 0,
                via: pair?.via ?? [],
                path: path
            )
        }
        .sorted { $0.miles < $1.miles }
    }

    private func slice(_ route: PassengerRoute, from originID: AtlasCity.ID, to destinationID: AtlasCity.ID) -> [RailCoordinate] {
        guard
            let origin = city(originID)?.coordinate,
            let destination = city(destinationID)?.coordinate,
            !route.path.isEmpty
        else { return route.path }
        let a = route.path.nearestIndex(to: origin)
        let b = route.path.nearestIndex(to: destination)
        let piece = Array(route.path[min(a, b) ... max(a, b)])
        return a <= b ? piece : piece.reversed()
    }
}

extension Array where Element == RailCoordinate {
    func nearestIndex(to target: RailCoordinate) -> Int {
        let scale = cos(target.latitude * .pi / 180)
        var best = 0
        var bestDistance = Double.infinity
        for (index, point) in enumerated() {
            let dx = (point.longitude - target.longitude) * scale
            let dy = point.latitude - target.latitude
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }
}
