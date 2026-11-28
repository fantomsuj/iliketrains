import MapKit
import Observation
import SwiftUI

/// Draws simulated freight trains over the map: one Canvas redrawn up to 30 times a second, projecting each
/// train through the map's own coordinate conversion. Map annotations can't animate a thousand points, a
/// Canvas can. It never takes touches, so the map and its markers work as usual underneath.
struct GhostTrainLayer: View {
    let simulator: GhostTrainSimulator
    let corridorIDs: Set<FreightCorridor.ID>
    let bounds: RailBounds?
    let latitudeSpan: Double
    let timeScale: Double
    let isPaused: Bool
    let clock: GhostClock
    let camera: MapCameraTicker
    let proxy: MapProxy

    /// Above this many, a stable subset is drawn so frames stay smooth on older phones.
    static let maximumTrains = 1_600
    private static let space = "ghostTrains"

    var body: some View {
        // Reading the camera tick redraws the layer while the map pans or zooms, even when paused.
        let _ = camera.tick
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { timeline in
            Canvas { context, size in
                let time = clock.tick(to: timeline.date, scale: timeScale, isPaused: isPaused)
                draw(in: &context, size: size, time: time)
            }
        }
        .coordinateSpace(.named(Self.space))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Tails cover about a third of a second of on-screen motion at any zoom.
        let tailSeconds = timeScale * 0.35
        let trains = simulator.trains(
            at: time,
            on: corridorIDs,
            within: bounds,
            tailSeconds: tailSeconds,
            limit: Self.maximumTrains
        )
        let radius = dotRadius
        let screen = CGRect(origin: .zero, size: size).insetBy(dx: -24, dy: -24)

        for train in trains {
            guard
                let head = proxy.convert(train.coordinate.mapCoordinate, to: .named(Self.space)),
                screen.contains(head),
                let tail = proxy.convert(train.tailCoordinate.mapCoordinate, to: .named(Self.space))
            else { continue }

            var layer = context
            layer.opacity = train.opacity
            let tint = train.level.tint

            if hypot(head.x - tail.x, head.y - tail.y) > 1 {
                var streak = Path()
                streak.move(to: tail)
                streak.addLine(to: head)
                layer.stroke(
                    streak,
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0), tint.opacity(0.85)]),
                        startPoint: tail,
                        endPoint: head
                    ),
                    style: StrokeStyle(lineWidth: radius * 1.5, lineCap: .round)
                )
            }

            layer.fill(Path(ellipseIn: circle(at: head, radius: radius * 2.4)), with: .color(tint.opacity(0.22)))
            layer.fill(Path(ellipseIn: circle(at: head, radius: radius)), with: .color(tint))
            layer.stroke(
                Path(ellipseIn: circle(at: head, radius: radius)),
                with: .color(.white.opacity(0.9)),
                lineWidth: max(0.75, radius * 0.35)
            )
        }
    }

    /// Smaller dots when zoomed out, so the national view reads as flow rather than clutter.
    private var dotRadius: CGFloat {
        switch latitudeSpan {
        case ..<1.5: 4.2
        case ..<5: 3.4
        case ..<15: 2.6
        default: 1.9
        }
    }

    private func circle(at point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// Bumped on every camera move. Only the ghost layer reads it, so continuous camera updates redraw that
/// one Canvas instead of the whole map view.
@Observable
final class MapCameraTicker {
    var tick = 0
}

/// The legend row for ghost trains: what they are, how fast the simulation runs, and play/pause.
struct GhostTrainLegendRow: View {
    let trainsOnScreen: Int
    let timeScale: Double
    let clock: GhostClock
    @Binding var isPaused: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("GHOST TRAINS")
                        .font(.caption2.weight(.black))
                        .tracking(1)
                        .foregroundStyle(RailTheme.signalOrange)
                    Text("SIMULATED")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.07), in: Capsule())
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RailTheme.railInk.opacity(0.8))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            Button {
                isPaused.toggle()
            } label: {
                Image(systemName: isPaused || reduceMotion ? "play.fill" : "pause.fill")
                    .font(.footnote.weight(.black))
                    .foregroundStyle(RailTheme.parchment)
                    .frame(width: 34, height: 34)
                    .background(RailTheme.railInk, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .disabled(reduceMotion)
            .accessibilityLabel(isPaused ? "Play ghost trains" : "Pause ghost trains")
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        let speed = "×\(Int(timeScale).formatted())"
        let state = reduceMotion ? "still (Reduce Motion)" : isPaused ? "paused" : speed
        return "≈\(trainsOnScreen.formatted()) trains • typical \(Self.label(clock.timeOfDay)) • \(state)"
    }

    /// "6:42 PM".
    static func label(_ time: DateComponents) -> String {
        let hour = time.hour ?? 0
        let minute = time.minute ?? 0
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelveHour):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
    }
}
