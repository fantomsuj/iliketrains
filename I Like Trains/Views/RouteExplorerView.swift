import MapKit
import SwiftUI

/// "All routes lead to…" style explorer: every passenger service or freight railroad
/// leaving one city, drawn as coloured branches with a legend, and narrowed to a
/// single city pair when a destination is picked.
struct RouteExplorerView: View {
    @Bindable var model: RouteExplorerViewModel
    var onClose: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .region(Self.nationalRegion)

    var body: some View {
        ZStack {
            map

            VStack(spacing: 10) {
                header
                Spacer()
                legend
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: model.legend)
        .sensoryFeedback(.selection, trigger: model.originID)
        .sensoryFeedback(.selection, trigger: model.destinationID)
        .sensoryFeedback(.impact(weight: .light), trigger: model.mode)
        .task {
            if model.loadState == .idle {
                await model.load()
                frameLines(animated: false)
            }
        }
        .onChange(of: model.originID) { _, _ in frameLines() }
        .onChange(of: model.destinationID) { _, _ in frameLines() }
        .onChange(of: model.mode) { _, _ in frameLines() }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $cameraPosition) {
            ForEach(model.lines.filter { !$0.isHighlighted }) { line in
                polyline(line)
            }
            ForEach(model.lines.filter(\.isHighlighted)) { line in
                polyline(line)
            }

            ForEach(model.mapCities) { city in
                Annotation(city.name, coordinate: city.coordinate.mapCoordinate) {
                    Button {
                        model.destinationID = model.destinationID == city.id ? nil : city.id
                    } label: {
                        CityDot(
                            name: city.name,
                            isSelected: model.destinationID == city.id,
                            showsLabel: model.destinationID == city.id
                                || model.destinationID == nil && RouteExplorerViewModel.featuredCityIDs.contains(city.id)
                        )
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Show routes from \(model.origin?.name ?? "here") to \(city.displayName)")
                }
                .annotationTitles(.hidden)
            }

            if let origin = model.origin {
                Annotation(origin.name, coordinate: origin.coordinate.mapCoordinate) {
                    OriginMarker()
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .ignoresSafeArea()
    }

    private func polyline(_ line: RouteExplorerViewModel.Line) -> some MapContent {
        MapPolyline(coordinates: line.path.map(\.mapCoordinate))
            .stroke(
                line.style.color.opacity(line.isHighlighted ? 0.95 : 0.22),
                style: StrokeStyle(
                    lineWidth: (line.isHighlighted ? 1.6 : 1.2) + line.weight * (model.destinationID == nil ? 6.5 : 4),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.headline.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(1)
                        .foregroundStyle(RailTheme.signalOrange)
                    Text(model.title)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .foregroundStyle(RailTheme.railInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(model.summary)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(RailTheme.railInk)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Close routes")
                }
            }

            Picker("Network", selection: $model.mode) {
                ForEach(RouteExplorerViewModel.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.featuredCities) { city in
                        CityChip(title: city.name, isSelected: city.id == model.originID) {
                            model.originID = city.id
                        }
                    }
                    Menu {
                        Picker("From", selection: $model.originID) {
                            ForEach(model.originChoices) { city in
                                Text(city.displayName).tag(city.id)
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(.black.opacity(0.06), in: Capsule())
                    }
                    .accessibilityLabel("Choose any starting city")
                }
            }
            .scrollClipDisabled()

            Menu {
                Picker("To", selection: $model.destinationID) {
                    Text("Everywhere").tag(nil as AtlasCity.ID?)
                    ForEach(model.destinationChoices) { city in
                        Text(city.displayName).tag(city.id as AtlasCity.ID?)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .foregroundStyle(RailTheme.signalOrange)
                    Text(model.destination.map { "To \($0.displayName)" } ?? "To everywhere it goes")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RailTheme.railInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("Destination, \(model.destination?.displayName ?? "everywhere")")
        }
        .padding(16)
        .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    // MARK: Legend

    @ViewBuilder
    private var legend: some View {
        switch model.loadState {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView().tint(RailTheme.signalOrange)
                Text("Laying track…").font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
        case .failed(let message):
            Text(message)
                .font(.caption.weight(.semibold))
                .padding(12)
                .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.legend.isEmpty {
                            Text(model.summary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.legend) { entry in
                            LegendRow(entry: entry, showsShare: model.destinationID == nil)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 220)

                Text(model.mode == .passenger
                     ? "Each colour is one service, traced on the federal North American Rail Network. Mileage between cities is along the track."
                     : "Each colour is one Class I railroad. Lines are its shortest own-track or trackage-rights route to every hub it reaches; thicker lines carry routes to more hubs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
    }

    // MARK: Camera

    private func frameLines(animated: Bool = true) {
        let points = model.lines.filter(\.isHighlighted).flatMap(\.path)
            + [model.origin, model.destination].compactMap { $0?.coordinate }
        guard let region = MKCoordinateRegion(fitting: points) else { return }
        withAnimation(animated && !reduceMotion ? .smooth(duration: 0.7) : nil) {
            cameraPosition = .region(region)
        }
    }

    private static let nationalRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.2, longitude: -98.4),
        span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 68)
    )
}

// MARK: - Pieces

private struct LegendRow: View {
    let entry: RouteExplorerViewModel.LegendEntry
    let showsShare: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Capsule()
                .fill(entry.style.color)
                .frame(width: 22, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(RailTheme.railInk)
                    if showsShare {
                        Text(entry.share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CityChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? RailTheme.parchment : RailTheme.railInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(isSelected ? RailTheme.railInk : .black.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CityDot: View {
    let name: String
    let isSelected: Bool
    let showsLabel: Bool

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(isSelected ? RailTheme.signalOrange : RailTheme.parchment)
                .frame(width: isSelected ? 12 : 7, height: isSelected ? 12 : 7)
                .overlay(Circle().stroke(RailTheme.railInk.opacity(0.7), lineWidth: 1.5))
            if showsLabel {
                Text(name)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(RailTheme.railInk)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
    }
}

private struct OriginMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(RailTheme.parchment).frame(width: 22, height: 22)
            Circle().stroke(RailTheme.railInk, lineWidth: 3).frame(width: 18, height: 18)
            Circle().fill(RailTheme.railInk).frame(width: 7, height: 7)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

extension RouteExplorerViewModel.Line.Style {
    var color: Color {
        switch self {
        case .palette(let index): RailTheme.routePalette[index % RailTheme.routePalette.count]
        case .railroad(let railroad): railroad.tint
        }
    }
}

extension MKCoordinateRegion {
    init?(fitting coordinates: [RailCoordinate]) {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in coordinates {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        // Extra room at the bottom for the legend card and at the top for the header.
        let latSpan = max(maxLat - minLat, 1.5)
        let lonSpan = max(maxLon - minLon, 2)
        self.init(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * 0.12, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(latSpan * 2.1, 80), longitudeDelta: min(lonSpan * 1.25, 120))
        )
    }
}

#Preview("Route explorer") {
    RouteExplorerView(model: RouteExplorerViewModel(provider: BundledRouteAtlasService()))
}
