import SwiftUI
import TrainsCore

/// Flighty's "all flights at this airport", for a station: every train in the next three hours across
/// all operators, live trains first-class, timetable filling the gaps.
struct StationBoardView: View {
    @Environment(LiveStore.self) private var store
    let hubId: String
    var openTrain: (String) -> Void
    var focus: (Coordinate) -> Void
    @State private var board: Board?
    @State private var mode: BoardRow.Kind = .departure

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = board {
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.hub.operators.map(\.displayName).joined(separator: " · ").uppercased())
                        .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.dim)
                    Text(b.hub.name).font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Picker("", selection: $mode) {
                    Text("Departures").tag(BoardRow.Kind.departure)
                    Text("Arrivals").tag(BoardRow.Kind.arrival)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: mode)
                let rows = b.rows.filter { $0.kind == mode && ($0.estimated ?? $0.scheduled) >= store.now - 5 * 60_000 }
                if rows.isEmpty {
                    ContentUnavailableView("Quiet right now", systemImage: "moon.zzz", description: Text("No \(mode == .departure ? "departures" : "arrivals") in the next three hours."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { r in
                                Button { if let id = r.trainId { openTrain(id) } } label: { BoardRowView(row: r) }
                                    .buttonStyle(.plain).disabled(r.trainId == nil)
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(20)
        .task(id: hubId) {
            // refresh every 30 s while open
            while !Task.isCancelled {
                if let b = try? await store.api.board(hubId) {
                    if board == nil { focus(Coordinate(lat: b.hub.lat, lon: b.hub.lon)) }
                    withAnimation(.snappy) { board = b }
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct BoardRowView: View {
    let row: BoardRow
    var body: some View {
        let punct: Punctuality = row.status == "Cancelled" ? .cancelled : Wording.punctuality(delaySec: row.delaySec, status: .enroute, source: row.source)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text((row.estimated ?? row.scheduled).clockTime).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(Theme.color(punct))
                if let est = row.estimated, abs(est - row.scheduled) > 90_000 {
                    Text(row.scheduled.clockTime).font(.caption).strikethrough().foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.kind == .departure ? row.destination : row.origin).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: row.color)).frame(width: 8, height: 8)
                    Text(row.label).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                    if let tr = row.track { Tag(text: "Trk \(tr)") }
                }
            }
            Spacer()
            Text(row.status).font(.caption.weight(.semibold)).foregroundStyle(Theme.color(punct)).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .opacity(row.status == "Departed" || row.status == "Arrived" ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}
