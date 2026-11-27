import SwiftUI
import TrainsCore

/// Network map with live ticker (ATC-style overview); the train card and station board slide up over it.
struct RootView: View {
    @Environment(LiveStore.self) private var store
    @State private var sheet: Sheet?
    @State private var showSearch = false
    @State private var focus: Coordinate?

    enum Sheet: Identifiable, Equatable {
        case train(String), station(String)
        var id: String { switch self { case .train(let t): return "t:" + t; case .station(let s): return "s:" + s } }
    }

    var followId: String? { if case .train(let id) = sheet { return id }; return nil }

    var body: some View {
        ZStack(alignment: .top) {
            NetworkMapView(followTrainId: followId, focus: focus,
                           onSelectTrain: { sheet = .train($0) },
                           onSelectStation: { sheet = .station($0) })
                .ignoresSafeArea()
            TopBar(showSearch: $showSearch)
            VStack { Spacer(); TickerView(onTap: { sheet = .train($0) }) }
        }
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .train(let id): TrainCardView(trainId: id, openStation: { sheet = .station($0) })
                case .station(let id): StationBoardView(hubId: id, openTrain: { sheet = .train($0) }, focus: { focus = $0 })
                }
            }
            .presentationDetents([.height(330), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .height(330)))
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(openTrain: { showSearch = false; sheet = .train($0) },
                       openStation: { showSearch = false; sheet = .station($0) })
                .presentationDetents([.large])
        }
        .sensoryFeedback(.selection, trigger: sheet)
    }
}

private struct TopBar: View {
    @Environment(LiveStore.self) private var store
    @Binding var showSearch: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                LiveDot(color: store.connection == .live ? Theme.onTime : Theme.late)
                Text("\(store.trains.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText()).animation(.snappy, value: store.trains.count)
                Text(store.isDemo ? "trains · replay" : store.connection == .live ? "trains moving" : "reconnecting")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.headline)
                    .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Search trains and stations")
        }
        .padding(.horizontal, 14)
        .foregroundStyle(Theme.text)
    }
}

struct LiveDot: View {
    var color: Color
    @State private var pulse = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .shadow(color: color, radius: pulse ? 6 : 2)
            .opacity(pulse ? 1 : 0.45)
            .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true } }
    }
}
