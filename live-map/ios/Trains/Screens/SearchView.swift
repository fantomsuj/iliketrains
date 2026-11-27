import SwiftUI
import TrainsCore

/// Search by train number ("2153") or station name ("Penn", "NYP").
struct SearchView: View {
    @Environment(LiveStore.self) private var store
    var openTrain: (String) -> Void
    var openStation: (String) -> Void
    @State private var query = ""
    @State private var result: SearchResult?

    var body: some View {
        NavigationStack {
            List {
                if let r = result {
                    if !r.trains.isEmpty {
                        Section("Trains") {
                            ForEach(r.trains) { t in
                                Button { openTrain(t.id) } label: {
                                    HStack {
                                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: t.color)).frame(width: 10, height: 10)
                                        VStack(alignment: .leading) {
                                            Text(Wording.trainLabel(operator: t.operator, routeName: t.routeName, number: t.trainNumber)).font(.body.weight(.semibold))
                                            Text("to \(t.destination)").font(.caption).foregroundStyle(Theme.dim)
                                        }
                                        Spacer()
                                        Text(Wording.lateness(t.delaySec) ?? "Scheduled").font(.caption.weight(.semibold)).foregroundStyle(Theme.color(t.punctuality))
                                    }
                                }
                            }
                        }
                    }
                    if !r.stations.isEmpty {
                        Section("Stations") {
                            ForEach(r.stations) { s in
                                Button { openStation(s.id) } label: {
                                    VStack(alignment: .leading) {
                                        Text(s.name).font(.body.weight(.semibold))
                                        Text(s.operators.map(\.displayName).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim)
                                    }
                                }
                            }
                        }
                    }
                    if r.trains.isEmpty && r.stations.isEmpty { Text("Nothing matches \"\(query)\"").foregroundStyle(Theme.dim) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Find a train")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Train number or station")
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { result = nil; return }
                try? await Task.sleep(for: .milliseconds(180)) // debounce
                if !Task.isCancelled { result = try? await store.api.search(q) }
            }
            .foregroundStyle(Theme.text)
        }
    }
}
