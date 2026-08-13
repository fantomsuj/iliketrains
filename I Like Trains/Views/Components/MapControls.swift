import MapKit
import SwiftUI

struct MapControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scope: Namespace.ID
    @Binding var layers: RailLayerVisibility
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            MapUserLocationButton(scope: scope)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .tint(RailTheme.signalOrange)
                .accessibilityLabel("Show my location")

            Menu {
                Toggle("Passenger trains", isOn: $layers.passengerTrains)
                Toggle("Rail lines", isOn: $layers.infrastructure)
                Toggle("Stations", isOn: $layers.stations)
                Toggle("Freight sightings", isOn: $layers.freightSightings)
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(RailTheme.railInk)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Choose map layers")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(RailTheme.railInk)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .rotationEffect(.degrees(isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(
                        isRefreshing && !reduceMotion
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : nil,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.pressable)
            .disabled(isRefreshing)
            .accessibilityLabel("Refresh rail data")
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }
}
