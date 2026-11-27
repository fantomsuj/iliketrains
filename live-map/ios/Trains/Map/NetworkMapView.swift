import SwiftUI
import MapLibre
import CoreLocation
import TrainsCore

/// The network map: our OSM vector tiles, glowing route lines, stations, and every train moving at
/// display rate. Trains are one GeoJSON source rewritten each frame from TrainAnimator.
struct NetworkMapView: UIViewRepresentable {
    @Environment(LiveStore.self) private var store
    var followTrainId: String?
    var focus: Coordinate?
    var onSelectTrain: (String) -> Void
    var onSelectStation: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store, onSelectTrain: onSelectTrain, onSelectStation: onSelectStation) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: store.config.styleURL)
        map.delegate = context.coordinator
        map.backgroundColor = UIColor(Theme.background)
        map.setCenter(CLLocationCoordinate2D(latitude: 40.85, longitude: -73.9), zoomLevel: 7.2, animated: false)
        map.logoView.isHidden = true            // MapLibre logo not required; OSM attribution stays visible
        map.attributionButtonPosition = .bottomLeft
        map.compassViewPosition = .topRight
        map.maximumZoomLevel = 16
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        for g in map.gestureRecognizers ?? [] where (g as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 { tap.require(toFail: g) }
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.onSelectTrain = onSelectTrain
        c.onSelectStation = onSelectStation
        c.followTrainId = followTrainId
        if let f = focus, f != c.lastFocus {
            c.lastFocus = f
            map.setCenter(CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon), zoomLevel: max(map.zoomLevel, 11), animated: true)
        }
        c.refreshStaticLayersIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        let store: LiveStore
        var onSelectTrain: (String) -> Void
        var onSelectStation: (String) -> Void
        var followTrainId: String?
        var lastFocus: Coordinate?
        weak var map: MLNMapView?
        private var trainSource: MLNShapeSource?
        private var routeSource: MLNShapeSource?
        private var stationSource: MLNShapeSource?
        private var link: CADisplayLink?
        private var lastFrame: CFTimeInterval = 0
        private var drewRoutes = false, drewStations = false

        init(store: LiveStore, onSelectTrain: @escaping (String) -> Void, onSelectStation: @escaping (String) -> Void) {
            self.store = store; self.onSelectTrain = onSelectTrain; self.onSelectStation = onSelectStation
        }

        // MARK: style

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let routes = MLNShapeSource(identifier: "routes", shape: nil, options: nil)
            let stations = MLNShapeSource(identifier: "hubs", shape: nil, options: nil)
            let trains = MLNShapeSource(identifier: "live-trains", shape: nil, options: nil)
            [routes, stations, trains].forEach(style.addSource)
            routeSource = routes; stationSource = stations; trainSource = trains
            let below = style.layer(withIdentifier: "places")

            let glow = MLNLineStyleLayer(identifier: "route-glow", source: routes)
            glow.lineColor = Self.expr(["to-color", ["get", "color"]])
            glow.lineWidth = Self.expr(["interpolate", ["linear"], ["zoom"], 6, 5, 12, 12])
            glow.lineBlur = Self.expr(["interpolate", ["linear"], ["zoom"], 6, 4, 12, 9])
            glow.lineOpacity = NSExpression(forConstantValue: 0.22)
            let core = MLNLineStyleLayer(identifier: "route-core", source: routes)
            core.lineColor = Self.expr(["to-color", ["get", "color"]])
            core.lineWidth = Self.expr(["interpolate", ["linear"], ["zoom"], 6, 1, 12, 2.2])
            core.lineOpacity = NSExpression(forConstantValue: 0.85)
            for l in [glow, core] { if let below { style.insertLayer(l, below: below) } else { style.addLayer(l) } }

            let hubDots = MLNCircleStyleLayer(identifier: "hub-dots", source: stations)
            hubDots.minimumZoomLevel = 8
            hubDots.circleRadius = Self.expr(["interpolate", ["linear"], ["zoom"], 8, ["+", 1, ["get", "n"]], 13, ["+", 3, ["*", 1.5, ["get", "n"]]]])
            hubDots.circleColor = NSExpression(forConstantValue: UIColor(Theme.background))
            hubDots.circleStrokeColor = NSExpression(forConstantValue: UIColor(white: 0.8, alpha: 1))
            hubDots.circleStrokeWidth = NSExpression(forConstantValue: 1.2)
            style.addLayer(hubDots)
            let hubLabels = MLNSymbolStyleLayer(identifier: "hub-labels", source: stations)
            hubLabels.minimumZoomLevel = 10
            hubLabels.text = NSExpression(forKeyPath: "name")
            hubLabels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            hubLabels.textFontSize = NSExpression(forConstantValue: 11)
            hubLabels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.1)))
            hubLabels.textAnchor = NSExpression(forConstantValue: "top")
            hubLabels.textOptional = NSExpression(forConstantValue: true)
            hubLabels.textColor = NSExpression(forConstantValue: UIColor(Theme.dim))
            hubLabels.textHaloColor = NSExpression(forConstantValue: UIColor(Theme.background))
            hubLabels.textHaloWidth = NSExpression(forConstantValue: 1.2)
            style.addLayer(hubLabels)

            // Train dot = the line's colour; amber/red ring only when late; hollow when timetable-only.
            let halo = MLNCircleStyleLayer(identifier: "train-halo", source: trains)
            halo.circleRadius = Self.expr(["interpolate", ["linear"], ["zoom"], 6, 7, 13, 16])
            halo.circleColor = Self.expr(["to-color", ["get", "color"]])
            halo.circleOpacity = Self.expr(["*", 0.22, ["get", "opacity"]])
            halo.circleBlur = NSExpression(forConstantValue: 0.7)
            let dot = MLNCircleStyleLayer(identifier: "train-dot", source: trains)
            dot.circleRadius = Self.expr(["interpolate", ["linear"], ["zoom"], 6, 2.6, 13, 6])
            dot.circleColor = Self.expr(["case", ["get", "scheduled"], Theme.background.hexString, ["to-color", ["get", "color"]]])
            dot.circleStrokeColor = Self.expr(["case", ["get", "alert"], ["to-color", ["get", "status"]], ["get", "scheduled"], ["to-color", ["get", "color"]], "#e6edf3"])
            dot.circleStrokeWidth = Self.expr(["interpolate", ["linear"], ["zoom"], 6, ["case", ["get", "alert"], 1.6, 0.6], 13, ["case", ["get", "alert"], 3, 1.4]])
            dot.circleOpacity = NSExpression(forKeyPath: "opacity")
            dot.circleStrokeOpacity = NSExpression(forKeyPath: "opacity")
            let label = MLNSymbolStyleLayer(identifier: "train-label", source: trains)
            label.minimumZoomLevel = 10
            label.text = NSExpression(forKeyPath: "label")
            label.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            label.textFontSize = NSExpression(forConstantValue: 10)
            label.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -1.3)))
            label.textColor = NSExpression(forConstantValue: UIColor(Theme.text))
            label.textHaloColor = NSExpression(forConstantValue: UIColor(Theme.background))
            label.textHaloWidth = NSExpression(forConstantValue: 1.2)
            [halo, dot, label].forEach(style.addLayer)

            refreshStaticLayersIfNeeded()
            startDisplayLink()
        }

        static func expr(_ json: Any) -> NSExpression { NSExpression(mlnJSONObject: json) }

        func refreshStaticLayersIfNeeded() {
            if !drewRoutes, let src = routeSource, let ov = store.overview {
                src.shape = MLNShapeCollectionFeature(shapes: ov.routes.compactMap { r -> MLNPolylineFeature? in
                    guard let line = store.line(r.key) else { return nil }
                    var coords = line.coords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                    f.attributes = ["color": r.color, "operator": r.operator.rawValue]
                    return f
                })
                drewRoutes = true
            }
            if !drewStations, let src = stationSource, !store.stations.isEmpty {
                src.shape = MLNShapeCollectionFeature(shapes: store.stations.map { s in
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon)
                    f.attributes = ["id": s.id, "name": s.name, "n": s.operators.count]
                    return f
                })
                drewStations = true
            }
        }

        // MARK: animation

        private func startDisplayLink() {
            link?.invalidate()
            let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            l.add(to: .main, forMode: .common)
            link = l
        }

        @objc private func frame(_ link: CADisplayLink) {
            let dt = lastFrame == 0 ? 1.0 / 60 : min(0.25, link.timestamp - lastFrame)
            lastFrame = link.timestamp
            guard let src = trainSource else { return }
            if !drewRoutes || !drewStations { refreshStaticLayersIfNeeded() }
            let trains = Array(store.trains.values)
            let byId = store.trains
            let frames = store.animator.step(now: store.now, dt: dt, trains: trains, lines: { [store] in store.line($0) })
            var features: [MLNPointFeature] = []
            features.reserveCapacity(frames.count)
            for f in frames {
                guard let t = byId[f.id] else { continue }
                let p = MLNPointFeature()
                p.coordinate = CLLocationCoordinate2D(latitude: f.coordinate.lat, longitude: f.coordinate.lon)
                let punct = t.punctuality
                p.attributes = ["id": f.id, "color": t.color, "status": Theme.hex(punct), "alert": punct == .late || punct == .veryLate || punct == .cancelled,
                                "scheduled": t.source == .scheduled, "opacity": f.opacity, "label": t.trainNumber]
                features.append(p)
                if f.id == followTrainId, let map {
                    map.setCenter(p.coordinate, animated: false) // camera rides along with the selected train
                }
            }
            src.shape = MLNShapeCollectionFeature(shapes: features)
        }

        // MARK: taps

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let map, g.state == .ended else { return }
            let pt = g.location(in: map)
            let rect = CGRect(x: pt.x - 14, y: pt.y - 14, width: 28, height: 28)
            if let f = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["train-dot"]).first, let id = f.attribute(forKey: "id") as? String {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelectTrain(id); return
            }
            if let f = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["hub-dots"]).first, let id = f.attribute(forKey: "id") as? String {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSelectStation(id)
            }
        }
    }
}

extension Color {
    var hexString: String {
        let c = UIColor(self).cgColor.components ?? [0, 0, 0]
        let r = c.count > 2 ? c[0] : c[0], gg = c.count > 2 ? c[1] : c[0], b = c.count > 2 ? c[2] : c[0]
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(gg * 255), Int(b * 255))
    }
}
