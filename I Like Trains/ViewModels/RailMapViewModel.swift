import Foundation
import Observation

public struct RailLayerVisibility: Equatable, Sendable {
    public var passengerTrains = true
    public var infrastructure = true
    public var stations = true
    public var freightSightings = true
    /// Typical-day freight trains per line, from the FRA crossing inventory.
    public var trafficDensity = true
    /// Container and trailer ramps.
    public var intermodalTerminals = true
    /// Each Class I railroad's largest yards with last week's dwell time.
    public var yardDwell = true

    public init() {}

    /// How many layers are switched off.
    public var hiddenCount: Int {
        [passengerTrains, infrastructure, stations, freightSightings, trafficDensity, intermodalTerminals, yardDwell]
            .filter { !$0 }
            .count
    }
}

/// A freight item the user tapped on the map.
public enum FreightSelection: Hashable, Sendable {
    case corridor(FreightCorridor.ID)
    case terminal(IntermodalTerminal.ID)
    case yard(YardDwell.ID)
}

/// Only one thing, a train or a freight item, is selected at a time.
enum MapSelection: Hashable, Sendable {
    case train(Train.ID)
    case freight(FreightSelection)
}

@MainActor
@Observable
public final class RailMapViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    /// Below this many trains a day, a line is hidden at a given zoom, so a national view stays legible.
    enum DensityZoom {
        static let nationalSpan = 18.0
        static let regionalSpan = 7.0
        /// Terminals appear once the map is zoomed in past this latitude span.
        static let terminalSpan = 14.0
    }

    public private(set) var trains: [Train] = []
    public private(set) var segments: [RailSegment] = []
    public private(set) var sightings: [FreightSighting] = []
    public private(set) var freightAtlas: FreightAtlas?
    /// Set when the freight atlas fails to load; the rest of the map still works.
    public private(set) var freightAtlasError: String?
    public private(set) var loadState: LoadState = .idle
    public var searchQuery = ""
    public var selectedOperator: RailOperator?
    /// One selection for the whole map, so choosing a train clears a freight item and vice versa.
    private var selection: MapSelection?

    public var selectedTrainID: Train.ID? {
        get {
            if case .train(let id) = selection { return id }
            return nil
        }
        set {
            if let newValue {
                selection = .train(newValue)
            } else if case .train = selection {
                selection = nil
            }
        }
    }

    public var selectedFreight: FreightSelection? {
        get {
            if case .freight(let item) = selection { return item }
            return nil
        }
        set {
            if let newValue {
                selection = .freight(newValue)
            } else if case .freight = selection {
                selection = nil
            }
        }
    }
    public var layers = RailLayerVisibility()
    /// The part of the map on screen; nil means the default national view.
    public var visibleRegion: RailBounds?

    @ObservationIgnored private let trainProvider: any TrainProviding
    @ObservationIgnored private let infrastructureProvider: any RailInfrastructureProviding
    @ObservationIgnored private let freightProvider: any FreightSightingProviding
    @ObservationIgnored private let freightAtlasProvider: (any FreightAtlasProviding)?

    public init(
        trainProvider: any TrainProviding,
        infrastructureProvider: any RailInfrastructureProviding,
        freightProvider: any FreightSightingProviding,
        freightAtlasProvider: (any FreightAtlasProviding)? = nil
    ) {
        self.trainProvider = trainProvider
        self.infrastructureProvider = infrastructureProvider
        self.freightProvider = freightProvider
        self.freightAtlasProvider = freightAtlasProvider
    }

    // MARK: Passenger and mock layers

    public var filteredTrains: [Train] {
        guard layers.passengerTrains else { return [] }
        return trains.filter { train in
            let matchesOperator = selectedOperator == nil || train.railOperator == selectedOperator
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return matchesOperator }
            let searchable = [
                train.number,
                train.name,
                train.railOperator.displayName,
                train.origin,
                train.destination,
                train.nextStop
            ].joined(separator: " ")
            return matchesOperator && searchable.localizedCaseInsensitiveContains(query)
        }
    }

    public var visibleSegments: [RailSegment] {
        guard layers.infrastructure else { return [] }
        guard let selectedOperator else { return segments }
        return segments.filter { $0.railOperator == nil || $0.railOperator == selectedOperator }
    }

    public var visibleStations: [RailStation] {
        guard layers.stations else { return [] }
        var seen = Set<RailStation.ID>()
        return visibleSegments
            .flatMap(\.stations)
            .filter { seen.insert($0.id).inserted }
    }

    public var visibleSightings: [FreightSighting] {
        guard layers.freightSightings else { return [] }
        guard let selectedOperator else { return sightings }
        return sightings.filter { $0.railOperator == selectedOperator }
    }

    public var selectedTrain: Train? {
        filteredTrains.first { $0.id == selectedTrainID }
    }

    // MARK: Freight atlas layers

    /// The quietest traffic level drawn at the current zoom.
    public var minimumVisibleLevel: TrafficLevel {
        let span = visibleRegion?.latitudeSpan ?? .infinity
        if span > DensityZoom.nationalSpan { return .busy }
        if span > DensityZoom.regionalSpan { return .moderate }
        return .unmeasured
    }

    /// Freight corridors to draw: on screen, busy enough for the zoom, and matching the operator filter.
    /// Quieter lines come first so busier ones draw on top.
    public var visibleCorridors: [FreightCorridor] {
        guard layers.trafficDensity, let freightAtlas else { return [] }
        let minimum = minimumVisibleLevel
        let screen = visibleRegion?.padded(by: (visibleRegion?.latitudeSpan ?? 0) * 0.1)
        return freightAtlas.corridors
            .filter { corridor in
                corridor.level >= minimum
                    && (selectedOperator == nil || corridor.railroad == selectedOperator)
                    && (screen.map { corridor.bounds.intersects($0) } ?? true)
            }
            .sorted { $0.level < $1.level }
    }

    public var visibleTerminals: [IntermodalTerminal] {
        guard layers.intermodalTerminals, let freightAtlas else { return [] }
        let zoomedIn = (visibleRegion?.latitudeSpan ?? .infinity) <= DensityZoom.terminalSpan
        return freightAtlas.terminals.filter { terminal in
            if case .terminal(terminal.id) = selectedFreight { return true }
            guard zoomedIn else { return false }
            let matchesOperator = selectedOperator == nil || terminal.railroads.contains { $0 == selectedOperator }
            let onScreen = visibleRegion.map { $0.contains(terminal.coordinate) } ?? true
            return matchesOperator && onScreen
        }
    }

    /// True when terminals exist but are hidden only because the map is zoomed out.
    public var terminalsNeedZoom: Bool {
        layers.intermodalTerminals
            && freightAtlas?.terminals.isEmpty == false
            && (visibleRegion?.latitudeSpan ?? .infinity) > DensityZoom.terminalSpan
    }

    public var visibleYards: [YardDwell] {
        guard layers.yardDwell, let freightAtlas else { return [] }
        return freightAtlas.yards.filter { selectedOperator == nil || $0.railroad == selectedOperator }
    }

    public var selectedCorridor: FreightCorridor? {
        guard case .corridor(let id) = selectedFreight else { return nil }
        return freightAtlas?.corridors.first { $0.id == id }
    }

    public var selectedTerminal: IntermodalTerminal? {
        guard case .terminal(let id) = selectedFreight else { return nil }
        return freightAtlas?.terminals.first { $0.id == id }
    }

    public var selectedYard: YardDwell? {
        guard case .yard(let id) = selectedFreight else { return nil }
        return freightAtlas?.yards.first { $0.id == id }
    }

    public var hasVisibleContent: Bool {
        !trains.isEmpty || !segments.isEmpty || !sightings.isEmpty || freightAtlas?.corridors.isEmpty == false
    }

    // MARK: Loading

    public func load() async {
        loadState = .loading
        do {
            async let nextTrains = trainProvider.trains()
            async let nextSegments = infrastructureProvider.railSegments()
            async let nextSightings = freightProvider.freightSightings()
            let snapshot = try await (nextTrains, nextSegments, nextSightings)
            trains = snapshot.0
            segments = snapshot.1
            sightings = snapshot.2
            loadState = .loaded
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
        await loadFreightAtlasIfNeeded()
    }

    public func refresh() async {
        await load()
    }

    /// The atlas is bundled and changes only with an app update, so it loads once; a failure is retried on refresh.
    private func loadFreightAtlasIfNeeded() async {
        guard freightAtlas == nil, let freightAtlasProvider else { return }
        do {
            freightAtlas = try await freightAtlasProvider.freightAtlas()
            freightAtlasError = nil
        } catch {
            freightAtlasError = "Freight data couldn't load. Trains and routes still work."
        }
    }

    // MARK: Selection

    public func selectTrain(_ train: Train) {
        selectedTrainID = selectedTrainID == train.id ? nil : train.id
    }

    public func setSelectedTrain(_ train: Train) {
        selectedTrainID = train.id
    }

    public func toggleFreight(_ selection: FreightSelection) {
        selectedFreight = selectedFreight == selection ? nil : selection
    }

    public func clearSelection() {
        selection = nil
    }

    /// Selects the drawn corridor nearest a tapped point, or clears the selection when the tap misses.
    /// The hit radius is about 3% of the visible map height, so it feels the same at every zoom.
    @discardableResult
    public func selectCorridor(near point: RailCoordinate) -> FreightCorridor? {
        let span = visibleRegion?.latitudeSpan ?? 38
        let radiusMiles = max(0.5, span * 69 * 0.03)
        guard let corridor = freightAtlas?.nearestCorridor(to: point, within: radiusMiles, among: visibleCorridors) else {
            clearSelection()
            return nil
        }
        selectedFreight = .corridor(corridor.id)
        return corridor
    }
}
