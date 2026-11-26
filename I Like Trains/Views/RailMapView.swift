import MapKit
import SwiftUI

struct RailMapView: View {
    @Bindable var model: RailMapViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .region(Self.nationalRegion)
    @State private var isShowingSearch = false
    @State private var isShowingFilters = false
    @State private var isShowingRoutes = false
    @State private var isShowingFreightPulse = false
    @State private var routeModel = RouteExplorerViewModel(provider: BundledRouteAtlasService())
    @Namespace private var mapScope

    var body: some View {
        ZStack {
            railMap

            VStack(spacing: 12) {
                BrandBar(
                    activeFilterCount: activeFilterCount,
                    onRoutes: { isShowingRoutes = true },
                    onSearch: { isShowingSearch = true },
                    onFilters: { isShowingFilters = true }
                )

                HStack(alignment: .top) {
                    if let filterLabel {
                        filterChip(filterLabel)
                    }
                    Spacer()
                    MapControls(
                        scope: mapScope,
                        layers: $model.layers,
                        isRefreshing: model.loadState == .loading,
                        onRefresh: { Task { await model.refresh() } }
                    )
                }

                Spacer()

                statusOverlay

                bottomCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .mapScope(mapScope)
        .animation(reduceMotion ? nil : .bouncy(duration: 0.48, extraBounce: 0.08), value: model.selectedTrainID)
        .animation(reduceMotion ? nil : .bouncy(duration: 0.48, extraBounce: 0.08), value: model.selectedFreight)
        .sensoryFeedback(.selection, trigger: model.selectedTrainID)
        .sensoryFeedback(.selection, trigger: model.selectedFreight)
        .sensoryFeedback(.impact(weight: .light), trigger: model.layers)
        .onChange(of: model.selectedTrainID) { _, _ in
            focusSelectedTrain()
        }
        .onChange(of: model.selectedFreight) { _, _ in
            focusSelectedFreight()
        }
        .task {
            if model.loadState == .idle {
                await model.load()
            }
        }
        .sheet(isPresented: $isShowingSearch) {
            RailSearchSheet(model: model)
        }
        .sheet(isPresented: $isShowingFilters) {
            RailFilterSheet(model: model)
        }
        .sheet(isPresented: $isShowingFreightPulse) {
            if let atlas = model.freightAtlas {
                FreightPulseSheet(
                    atlas: atlas,
                    onShowCorridor: { corridor in
                        model.layers.trafficDensity = true
                        model.selectedFreight = .corridor(corridor.id)
                    },
                    onFilterRailroad: { railroad in
                        model.selectedOperator = railroad
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $isShowingRoutes) {
            RouteExplorerView(model: routeModel) {
                isShowingRoutes = false
            }
        }
    }

    // MARK: Map

    private var railMap: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, scope: mapScope) {
                ForEach(model.visibleCorridors) { corridor in
                    MapPolyline(coordinates: corridor.path.map(\.mapCoordinate))
                        .stroke(corridor.level.tint, style: corridorStroke(for: corridor.level))
                }

                if let corridor = model.selectedCorridor {
                    MapPolyline(coordinates: corridor.path.map(\.mapCoordinate))
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: corridor.level.lineWidth + 7, lineCap: .round, lineJoin: .round)
                        )
                    MapPolyline(coordinates: corridor.path.map(\.mapCoordinate))
                        .stroke(
                            corridor.level == .unmeasured ? RailTheme.railInk : corridor.level.tint,
                            style: StrokeStyle(lineWidth: corridor.level.lineWidth + 3, lineCap: .round, lineJoin: .round)
                        )
                }

                ForEach(model.visibleSegments) { segment in
                    MapPolyline(coordinates: segment.coordinates.map(\.mapCoordinate))
                        .stroke(
                            segment.railOperator?.tint ?? RailTheme.railInk.opacity(0.72),
                            style: StrokeStyle(
                                lineWidth: lineWidth(for: segment),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                ForEach(model.visibleStations) { station in
                    Annotation(station.name, coordinate: station.coordinate.mapCoordinate, anchor: .bottom) {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(RailTheme.railInk)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(RailTheme.parchment, lineWidth: 2))
                            Text(station.code)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(RailTheme.railInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(station.name), \(station.city)")
                    }
                }

                ForEach(model.visibleTerminals) { terminal in
                    Annotation(terminal.name, coordinate: terminal.coordinate.mapCoordinate) {
                        Button {
                            model.toggleFreight(.terminal(terminal.id))
                        } label: {
                            IntermodalTerminalMarker(
                                terminal: terminal,
                                isSelected: model.selectedFreight == .terminal(terminal.id)
                            )
                        }
                        .buttonStyle(.pressable)
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(model.visibleYards) { yard in
                    Annotation(yard.name, coordinate: yard.coordinate.mapCoordinate) {
                        Button {
                            model.toggleFreight(.yard(yard.id))
                        } label: {
                            YardDwellMarker(yard: yard, isSelected: model.selectedFreight == .yard(yard.id))
                        }
                        .buttonStyle(.pressable)
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(model.visibleSightings) { sighting in
                    Annotation(
                        "\(sighting.railOperator.shortName) freight sighting",
                        coordinate: sighting.coordinate.mapCoordinate
                    ) {
                        FreightSightingMarker(sighting: sighting)
                    }
                }

                ForEach(model.filteredTrains) { train in
                    Annotation(train.name, coordinate: train.coordinate.mapCoordinate) {
                        Button {
                            model.selectTrain(train)
                        } label: {
                            TrainMarker(train: train, isSelected: model.selectedTrainID == train.id)
                        }
                        .buttonStyle(.pressable)
                    }
                }

                UserAnnotation()
            }
            .mapStyle(
                .standard(
                    elevation: .flat,
                    emphasis: .muted,
                    pointsOfInterest: .excludingAll,
                    showsTraffic: false
                )
            )
            .mapControls {
                MapCompass(scope: mapScope)
                MapScaleView(scope: mapScope)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                let region = context.region
                model.visibleRegion = RailBounds(
                    center: RailCoordinate(latitude: region.center.latitude, longitude: region.center.longitude),
                    latitudeDelta: region.span.latitudeDelta,
                    longitudeDelta: region.span.longitudeDelta
                )
            }
            .onTapGesture { location in
                handleMapTap(at: location, proxy: proxy)
            }
            .ignoresSafeArea()
        }
    }

    /// Lines can't be tapped directly in MapKit for SwiftUI, so a tap on open map picks the nearest drawn
    /// corridor (or clears the selection). Taps on or right next to a marker are left to that marker's button.
    private func handleMapTap(at location: CGPoint, proxy: MapProxy) {
        let markers = model.visibleTerminals.map(\.coordinate)
            + model.visibleYards.map(\.coordinate)
            + model.filteredTrains.map(\.coordinate)
            + model.visibleSightings.map(\.coordinate)
        let onMarker = markers.contains { coordinate in
            guard let point = proxy.convert(coordinate.mapCoordinate, to: .local) else { return false }
            return hypot(point.x - location.x, point.y - location.y) < 26
        }
        guard !onMarker, let coordinate = proxy.convert(location, from: .local) else { return }
        guard model.layers.trafficDensity else {
            model.clearSelection()
            return
        }
        model.selectCorridor(near: RailCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func corridorStroke(for level: TrafficLevel) -> StrokeStyle {
        StrokeStyle(
            lineWidth: level.lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: level == .unmeasured ? [3, 5] : []
        )
    }

    private func lineWidth(for segment: RailSegment) -> CGFloat {
        2.2 + CGFloat(segment.trafficDensity) / 45
    }

    // MARK: Bottom card

    @ViewBuilder
    private var bottomCard: some View {
        if let train = model.selectedTrain {
            TrainDetailCard(train: train) {
                model.selectTrain(train)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let atlas = model.freightAtlas, let item = selectedFreightItem {
            FreightDetailCard(item: item, atlas: atlas) {
                model.clearSelection()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            mapLegend
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var selectedFreightItem: FreightDetailCard.Item? {
        if let corridor = model.selectedCorridor { return .corridor(corridor) }
        if let terminal = model.selectedTerminal { return .terminal(terminal) }
        if let yard = model.selectedYard { return .yard(yard) }
        return nil
    }

    private var mapLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIVE RAIL MAP")
                        .font(.caption2.weight(.black))
                        .tracking(1)
                        .foregroundStyle(RailTheme.signalOrange)
                    Text("\(model.filteredTrains.count) trains • \(model.visibleSightings.count) freight sightings")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(RailTheme.railInk)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("MOCK")
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let atlas = model.freightAtlas {
                Divider()
                    .overlay(RailTheme.railInk.opacity(0.12))
                freightLegend(atlas)
            } else if let error = model.freightAtlasError {
                Text(error)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

    private func freightLegend(_ atlas: FreightAtlas) -> some View {
        Button {
            isShowingFreightPulse = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FREIGHT THIS WEEK")
                            .font(.caption2.weight(.black))
                            .tracking(1)
                            .foregroundStyle(RailTheme.signalOrange)
                        Text(freightHeadline(atlas))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(RailTheme.railInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                if model.layers.trafficDensity {
                    TrafficScale(atlas: atlas, minimum: model.minimumVisibleLevel)
                }
                if model.terminalsNeedZoom || (model.layers.trafficDensity && model.minimumVisibleLevel > .light) {
                    Text(zoomHint)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this week's freight numbers and sources")
    }

    private func freightHeadline(_ atlas: FreightAtlas) -> String {
        guard let volume = atlas.volume else {
            return "\(atlas.corridors.count) freight lines • \(atlas.terminals.count) ramps"
        }
        let total = Int((Double(volume.totalTraffic.count) / 1000).rounded())
        let sign = volume.totalTraffic.changePercent >= 0 ? "+" : "−"
        let change = "\(sign)\(String(format: "%.1f", abs(volume.totalTraffic.changePercent)))%"
        return "\(total)k U.S. cars & containers • \(change) y/y"
    }

    private var zoomHint: String {
        var parts: [String] = []
        if model.layers.trafficDensity && model.minimumVisibleLevel > .light {
            parts.append("quieter lines")
        }
        if model.terminalsNeedZoom {
            parts.append("intermodal ramps")
        }
        return "Zoom in to see \(parts.joined(separator: " and ")). Tap a line for its train count."
    }

    // MARK: Status

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.loadState {
        case .idle:
            EmptyView()
        case .loaded where !model.hasVisibleContent:
            VStack(spacing: 8) {
                Image(systemName: "train.side.front.car")
                    .font(.title2.bold())
                    .foregroundStyle(RailTheme.signalOrange)
                Text("No trains on the board")
                    .font(.headline)
                Text("The feeds returned an empty snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reload") {
                    Task { await model.refresh() }
                }
                .font(.subheadline.bold())
                .frame(minWidth: 88, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .tint(RailTheme.signalOrange)
            }
            .padding(18)
            .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .loaded:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(RailTheme.signalOrange)
                Text(model.trains.isEmpty ? "Calling the dispatcher…" : "Refreshing the board…")
                    .font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(RailTheme.signalOrange)
                Text(message)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Button("Retry") {
                    Task { await model.refresh() }
                }
                .font(.caption.bold())
                .frame(minWidth: 64, minHeight: 44)
            }
            .padding(12)
            .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Filters

    private var activeFilterCount: Int {
        (model.selectedOperator == nil ? 0 : 1) + model.layers.hiddenCount
    }

    private var filterLabel: String? {
        model.selectedOperator?.displayName
    }

    private func filterChip(_ title: String) -> some View {
        Button {
            model.selectedOperator = nil
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.bold())
            }
            .font(.caption.bold())
            .foregroundStyle(RailTheme.railInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RailTheme.parchment, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Clear \(title) filter")
    }

    // MARK: Camera

    private func focusSelectedTrain() {
        guard let train = model.selectedTrain else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.75)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: train.coordinate.mapCoordinate,
                    distance: 85_000,
                    heading: 0,
                    pitch: 32
                )
            )
        }
    }

    /// Frames a selected line, or centres on a terminal or yard, leaving room for the detail card below.
    private func focusSelectedFreight() {
        let region: MKCoordinateRegion
        if let corridor = model.selectedCorridor {
            let bounds = corridor.bounds
            let latitudeSpan = max(bounds.latitudeSpan * 1.8, 0.4)
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (bounds.minLatitude + bounds.maxLatitude) / 2 - latitudeSpan * 0.18,
                    longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: latitudeSpan,
                    longitudeDelta: max((bounds.maxLongitude - bounds.minLongitude) * 1.4, 0.4)
                )
            )
        } else if let coordinate = model.selectedTerminal?.coordinate ?? model.selectedYard?.coordinate {
            // Keep the current zoom if already close, so tapping between nearby pins doesn't bounce the map.
            let span = min(model.visibleRegion?.latitudeSpan ?? 6, 6)
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude - span * 0.18, longitude: coordinate.longitude),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.2)
            )
        } else {
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.75)) {
            cameraPosition = .region(region)
        }
    }

    private static let nationalRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.2, longitude: -98.4),
        span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 68)
    )
}

#Preview("National rail map") {
    let service = MockRailDataService()
    RailMapView(
        model: RailMapViewModel(
            trainProvider: service,
            infrastructureProvider: service,
            freightProvider: service,
            freightAtlasProvider: BundledFreightAtlasService()
        )
    )
}
