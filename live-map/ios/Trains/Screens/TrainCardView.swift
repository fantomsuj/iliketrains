import SwiftUI
import TrainsCore

/// Flighty's live-tracking card, for a train: big status, origin to destination with a live progress
/// rail, a countdown to the next stop, and every stop with scheduled vs. expected times.
struct TrainCardView: View {
    @Environment(LiveStore.self) private var store
    let trainId: String
    var openStation: (String) -> Void
    @State private var detail: TrainDetail?
    @State private var failed = false
    @State private var showRaw = false

    var body: some View {
        Group {
            if let t = detail { content(t) }
            else if failed { ContentUnavailableView("Train not running", systemImage: "tram", description: Text("It may have just finished its trip.")) }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
        }
        .task(id: trainId) { await load() }
        // refresh whenever this train's live record changes
        .onChange(of: store.trains[trainId]?.updatedAt) { Task { await load() } }
        .sensoryFeedback(.impact(weight: .medium), trigger: store.lastEventByTrain[trainId]?.id)
        .sheet(isPresented: $showRaw) { RawRecordView(trainId: trainId) }
    }

    private func load() async {
        do { detail = try await store.api.train(trainId); failed = false } catch { if detail == nil { failed = true } }
    }

    @ViewBuilder private func content(_ t: TrainDetail) -> some View {
        let punct = t.punctuality
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(t)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Wording.headline(t, now: store.now))
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(t.status == .cancelled ? "Cancelled" : t.source == .scheduled ? "Scheduled" : (Wording.lateness(t.delaySec) ?? "Tracking"))
                        .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.color(punct))
                        .contentTransition(.numericText()).animation(.snappy, value: t.delaySec)
                    Spacer()
                    Tag(text: Wording.fixLabel(t.fix, source: t.source))
                }
                endpoints(t, punct: punct)
                SectionHeader("Equipment")
                EquipmentSection(train: t)
                SectionHeader("Last 14 days")
                HistorySection(train: t)
                SectionHeader("Stops")
                stopsList(t, punct: punct)
                Button("View raw record") { showRaw = true }
                    .font(.footnote).foregroundStyle(Theme.dim).padding(.top, 4)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ t: TrainDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: t.color)).frame(width: 10, height: 10)
                Text("\(t.operator.displayName.uppercased()) · \(t.routeName.uppercased())")
                    .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.dim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t.trainNumber).font(.system(size: 30, weight: .bold, design: .rounded))
                Text("to \(t.destination)").font(.headline).foregroundStyle(Theme.dim)
            }
        }
    }

    private func endpoints(_ t: TrainDetail, punct: Punctuality) -> some View {
        let first = t.stops.first, last = t.stops.last
        return VStack(spacing: 6) {
            HStack {
                endpoint(first?.stationId ?? "", first?.name ?? t.origin, time: first?.estDep ?? first?.schDep, align: .leading)
                Spacer()
                if let next = t.next, let eta = next.eta {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(spacing: 0) {
                            Text(Wording.countdown(to: eta, now: store.now)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("to \(next.name)").font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                    }
                }
                Spacer()
                endpoint(last?.stationId ?? "", last?.name ?? t.destination, time: last?.estArr ?? last?.schArr, align: .trailing)
            }
            // progress follows the marker drawn on the map, frame by frame
            TimelineView(.animation) { _ in
                ProgressRail(progress: store.liveProgress(t), color: Theme.color(punct))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface.opacity(0.6)))
    }

    private func endpoint(_ code: String, _ name: String, time: EpochMs?, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(code.count <= 4 ? code : String(name.prefix(14))).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(time?.clockTime ?? "").font(.subheadline).monospacedDigit().foregroundStyle(Theme.dim)
        }
    }

    private func stopsList(_ t: TrainDetail, punct: Punctuality) -> some View {
        VStack(spacing: 0) {
            ForEach(t.stops) { s in
                Button { openStation(s.hubId) } label: { StopRow(stop: s, isNext: s.stationId == t.next?.stationId, color: Theme.color(punct)) }
                    .buttonStyle(.plain)
                Divider().overlay(Theme.hairline)
            }
        }
    }
}

private struct StopRow: View {
    let stop: TrainStop
    let isNext: Bool
    let color: Color

    var body: some View {
        let passed = stop.status == .departed
        let sch = stop.schArr ?? stop.schDep, est = stop.estArr ?? stop.estDep
        HStack(spacing: 12) {
            Circle().fill(passed ? Theme.dim : isNext ? color : Color.clear)
                .overlay(Circle().stroke(passed ? Theme.dim : color, lineWidth: 1.5)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stop.name).font(isNext ? .body.weight(.semibold) : .body)
                    if let tr = stop.track { Tag(text: "Trk \(tr)") }
                    if stop.status == .skipped { Tag(text: "Skips", color: Theme.late) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let sch, let est, abs(est - sch) > 90_000 {
                    Text(sch.clockTime).font(.caption).strikethrough().foregroundStyle(Theme.dim)
                }
                Text((est ?? sch)?.clockTime ?? "").font(.subheadline.weight(.medium)).monospacedDigit()
                    .foregroundStyle(passed ? Theme.dim : color)
            }
        }
        .foregroundStyle(passed ? Theme.dim : Theme.text)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// The unprocessed server record for a train, pretty-printed.
struct RawRecordView: View {
    @Environment(LiveStore.self) private var store
    let trainId: String
    @State private var text = ""
    var body: some View {
        NavigationStack {
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                .navigationTitle("Raw record").navigationBarTitleDisplayMode(.inline)
                .task { text = (try? await store.api.rawTrain(trainId)) ?? "Unavailable" }
        }
    }
}
