import MapKit
import SwiftUI

struct RailMapView: View {
    @Bindable var model: RailMapViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .region(Self.nationalRegion)
    @State private var isShowingSearch = false
    @State private var isShowingFilters = false
    @Namespace private var mapScope

    var body: some View {
        ZStack {
            railMap

            VStack(spacing: 12) {
                BrandBar(
                    activeFilterCount: activeFilterCount,
                    onSearch: { isShowingSearch = true },
                    onFilters: { isShowingFilters = true }
                )

                HStack {
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

                if let train = model.selectedTrain {
                    TrainDetailCard(train: train) {
                        model.selectTrain(train)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    mapLegend
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .mapScope(mapScope)
        .animation(reduceMotion ? nil : .bouncy(duration: 0.48, extraBounce: 0.08), value: model.selectedTrainID)
        .sensoryFeedback(.selection, trigger: model.selectedTrainID)
        .sensoryFeedback(.impact(weight: .light), trigger: model.layers)
        .onChange(of: model.selectedTrainID) { _, _ in
            focusSelectedTrain()
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
    }

    private var railMap: some View {
        Map(position: $cameraPosition, scope: mapScope) {
            ForEach(model.visibleSegments) { segment in
                MapPolyline(coordinates: segment.coordinates.map(\.mapCoordinate))
                    .stroke(
                        segment.operator?.tint ?? RailTheme.railInk.opacity(0.72),
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

            ForEach(model.visibleSightings) { sighting in
                Annotation(
                    "\(sighting.operator.shortName) freight sighting",
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
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.loadState {
        case .idle, .loaded:
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
            }
            .padding(12)
            .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var mapLegend: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var activeFilterCount: Int {
        var count = model.selectedOperator == nil ? 0 : 1
        count += model.layers.passengerTrains ? 0 : 1
        count += model.layers.infrastructure ? 0 : 1
        count += model.layers.stations ? 0 : 1
        count += model.layers.freightSightings ? 0 : 1
        return count
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
            .frame(height: 38)
            .background(RailTheme.parchment, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Clear \(title) filter")
    }

    private func lineWidth(for segment: RailSegment) -> CGFloat {
        2.2 + CGFloat(segment.trafficDensity) / 45
    }

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
            freightProvider: service
        )
    )
}
