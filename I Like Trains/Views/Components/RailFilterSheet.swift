import SwiftUI

struct RailFilterSheet: View {
    @Bindable var model: RailMapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Operator") {
                    Picker("Show", selection: $model.selectedOperator) {
                        Text("All operators").tag(nil as RailOperator?)
                        ForEach(RailOperator.allCases) { railOperator in
                            Label(railOperator.displayName, systemImage: "circle.fill")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(railOperator.tint)
                                .tag(railOperator as RailOperator?)
                        }
                    }
                }

                Section("Map layers") {
                    LayerToggle(
                        title: "Passenger trains",
                        detail: "Mock vehicle positions",
                        symbol: "train.side.front.car",
                        isOn: $model.layers.passengerTrains
                    )
                    LayerToggle(
                        title: "Rail infrastructure",
                        detail: "Intercity and freight corridors",
                        symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                        isOn: $model.layers.infrastructure
                    )
                    LayerToggle(
                        title: "Stations",
                        detail: "Selected major stops",
                        symbol: "building.2.fill",
                        isOn: $model.layers.stations
                    )
                    LayerToggle(
                        title: "Freight sightings",
                        detail: "Community reports, not live GPS",
                        symbol: "shippingbox.fill",
                        isOn: $model.layers.freightSightings
                    )
                }

                Section {
                    Label(
                        "Freight markers show reported sightings with confidence and age. They are not verified real-time positions.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Map filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct LayerToggle: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(RailTheme.signalOrange)
            }
        }
        .tint(RailTheme.signalOrange)
    }
}
