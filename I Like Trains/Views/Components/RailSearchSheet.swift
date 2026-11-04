import SwiftUI

struct RailSearchSheet: View {
    @Bindable var model: RailMapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.filteredTrains.isEmpty {
                    ContentUnavailableView.search(text: model.searchQuery)
                } else {
                    List(model.filteredTrains) { train in
                        Button {
                            model.setSelectedTrain(train)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "train.side.front.car")
                                    .font(.title3.bold())
                                    .foregroundStyle(train.railOperator.tint)
                                    .frame(width: 38, height: 38)
                                    .background(train.railOperator.tint.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(train.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(train.railOperator.shortName) \(train.number)  •  \(train.origin) → \(train.destination)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Find a train")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Number, route, city, or operator"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
