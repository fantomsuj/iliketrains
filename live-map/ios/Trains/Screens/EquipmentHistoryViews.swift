import SwiftUI
import TrainsCore

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.dim).padding(.top, 6)
    }
}

/// Flighty's "aircraft" block, for a train: the model and, when the railroad reports it, every car
/// front to back with its number and how full it is. Amtrak shows what usually runs the service.
struct EquipmentSection: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.openURL) private var openURL
    let train: TrainDetail
    @State private var selected: Car?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = train.equipment {
                if e.live { live(e) } else { typical(e) }
            } else {
                Text("Not reported for this train yet.").font(.subheadline).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func typical(_ e: Equipment) -> some View {
        Text((train.operator == .amtrak ? "Typically " : "") + (e.summary ?? "")).font(.headline)
        if let d = e.detail { Text(d).font(.caption).foregroundStyle(Theme.dim) }
        if train.operator == .amtrak {
            Text("Amtrak doesn't publish which equipment runs each train.").font(.caption2).foregroundStyle(Theme.dim)
        }
        if let s = e.source, let url = URL(string: s) { Link("Source", destination: url).font(.caption2).foregroundStyle(Theme.dim) }
    }

    @ViewBuilder private func live(_ e: Equipment) -> some View {
        let cars = e.cars ?? []
        Text(e.name ?? "Equipment").font(.headline)
        HStack(spacing: 6) {
            Text("\(e.carsRunning ?? cars.count) cars").monospacedDigit()
            if let s = e.carsScheduled { Text("(\(s) scheduled)").foregroundStyle(Theme.dim) }
            if let n = Wording.lengthNote(running: e.carsRunning, scheduled: e.carsScheduled) {
                Text(n).foregroundStyle((e.carsRunning ?? 0) > (e.carsScheduled ?? 0) ? Theme.onTime : Theme.late)
            }
            let riders = cars.compactMap(\.passengers)
            if !riders.isEmpty { Text("· \(riders.reduce(0, +)) aboard").foregroundStyle(Theme.dim) }
        }
        .font(.caption)
        if cars.isEmpty {
            Text("The railroad didn't list the cars for this run.").font(.caption).foregroundStyle(Theme.dim)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(cars) { c in
                        CarTile(car: c, isRearLoco: c.locomotive && c.position == cars.count && cars.count > 1, selected: selected == c)
                            .onTapGesture { withAnimation(.snappy) { selected = selected == c ? nil : c } }
                    }
                }
                .padding(.vertical, 2)
            }
            .sensoryFeedback(.selection, trigger: selected)
            Text(selected.map(describe) ?? "Front first. Tap a car.").font(.caption).foregroundStyle(Theme.dim)
                .contentTransition(.opacity)
        }
        Button("Raw record") { openURL(store.api.rawEquipmentURL(train.id)) }.font(.caption2).foregroundStyle(Theme.dim)
    }

    private func describe(_ c: Car) -> String {
        var s = "Car \(c.position): \(c.model) \(c.number.map(String.init) ?? "")"
        if c.locomotive { s += " (locomotive)" } else {
            s += " · " + Wording.loading(c.loading)
            if let p = c.passengers { s += ", \(p) aboard" }
            if c.restroom { s += " · restroom" }
        }
        return s
    }
}

private struct CarTile: View {
    let car: Car
    let isRearLoco: Bool
    let selected: Bool

    var fill: Color {
        if car.locomotive { return Color(white: 0.8) }
        switch car.loading {
        case "EMPTY", "MANY_SEATS": return Theme.onTime
        case "FEW_SEATS": return Theme.late
        case "STANDING_ROOM_ONLY", "FULL": return Theme.bad
        default: return Color.white.opacity(0.16)
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            UnevenRoundedRectangle(topLeadingRadius: car.locomotive && !isRearLoco ? 11 : 5, bottomLeadingRadius: car.locomotive && !isRearLoco ? 11 : 5,
                                   bottomTrailingRadius: isRearLoco ? 11 : 5, topTrailingRadius: isRearLoco ? 11 : 5)
                .fill(fill)
                .frame(width: car.locomotive ? 36 : 30, height: 22)
                .overlay { if car.restroom { Circle().fill(.black.opacity(0.55)).frame(width: 4, height: 4) } }
                .overlay { if selected { RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1.5).padding(-2) } }
            Text(car.number.map(String.init) ?? "").font(.system(size: 8).monospacedDigit()).foregroundStyle(Theme.dim)
        }
        .accessibilityElement()
        .accessibilityLabel("Car \(car.position), \(car.model), \(car.locomotive ? "locomotive" : Wording.loading(car.loading))")
    }
}

/// Flighty's on-time history for a flight, for a train number: on-time rate, average and worst
/// delay, and one bar per day (taller = later; striped = shown but not counted).
struct HistorySection: View {
    @Environment(LiveStore.self) private var store
    @Environment(\.openURL) private var openURL
    let train: TrainDetail
    @State private var history: HistorySummary?
    @State private var picked: HistoryDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let h = history {
                if h.scoredRuns > 0 {
                    HStack(spacing: 22) {
                        stat("\(Int((Double(h.onTimeRuns) / Double(h.scoredRuns) * 100).rounded()))%", "on time (\(h.onTimeRuns) of \(h.scoredRuns))",
                             color: Double(h.onTimeRuns) / Double(h.scoredRuns) >= 0.8 ? Theme.onTime : Theme.late)
                        stat(Wording.minutes(h.avgDelayMin.map { Int($0.rounded()) }), "average")
                        stat(Wording.minutes(h.worstDelayMin), "worst")
                    }
                } else {
                    Text(h.backfilling ? "Filling in past runs…" : "No completed runs recorded yet.").font(.subheadline).foregroundStyle(Theme.dim)
                }
                bars(h)
                Text(caption(h)).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if let d = picked, d.source != nil {
                    HStack(spacing: 14) {
                        Button("Raw record") { openURL(store.api.rawHistoryURL(train.operator, train.trainNumber, d.date)) }
                        if let s = d.sourceUrl, let url = URL(string: s) { Button("Open in archive") { openURL(url) } }
                    }
                    .font(.caption2).foregroundStyle(Theme.dim)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: train.trainNumber) {
            // the server fills past Amtrak days in the background; check back a few times while it does
            for _ in 0..<6 {
                if let h = try? await store.api.history(train.operator, train.trainNumber) { withAnimation(.snappy) { history = h }; if !h.backfilling { break } }
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func bars(_ h: HistorySummary) -> some View {
        let days = Array(h.days.reversed())
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { d in
                    DayBar(day: d, threshold: h.thresholdMin, picked: picked == d)
                        .onTapGesture { withAnimation(.snappy) { picked = picked == d ? nil : d } }
                }
            }
            .frame(height: 46, alignment: .bottom)
            .sensoryFeedback(.selection, trigger: picked)
            HStack { Text(String(days.first?.date.dropFirst(5) ?? "")); Spacer(); Text("today") }.font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func caption(_ h: HistorySummary) -> String {
        guard let d = picked else {
            return (h.note.map { $0 + " " } ?? "") + "On time means within \(h.thresholdMin) min. Striped days aren't counted. Tap a day."
        }
        switch d.status {
        case "no_record": return "\(d.date): did not run"
        case "unknown": return "\(d.date): no record yet"
        default:
            var s = "\(d.date): \(d.status == "cancelled" ? "cancelled" : Wording.minutes(d.delayMin))"
            if let m = d.measuredAt { s += " at \(m)" }
            if d.status == "running" { s += " (still running)" }
            if let f = d.flag, d.status != "cancelled" { s += " · not counted: \(f)" }
            if let c = d.consist { s += "\n\(c)" }
            return s
        }
    }
}

private struct DayBar: View {
    let day: HistoryDay
    let threshold: Int
    let picked: Bool

    var empty: Bool { day.status == "unknown" || day.status == "no_record" || (day.delayMin == nil && day.status != "cancelled") }
    var color: Color {
        if day.status == "cancelled" { return Theme.bad }
        guard let m = day.delayMin else { return Color.white.opacity(0.12) }
        return m <= threshold ? Theme.onTime : m <= 15 ? Theme.late : Theme.bad
    }
    var height: CGFloat {
        if empty { return 6 }
        if day.status == "cancelled" { return 46 }
        return CGFloat(max(12, min(46, 16 + max(0, day.delayMin ?? 0) * 2)))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(empty ? Color.white.opacity(0.08) : day.scored ? color : color.opacity(0.25))
            .overlay {
                if !empty && !day.scored { RoundedRectangle(cornerRadius: 3).stroke(Theme.dim.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2])) }
            }
            .overlay { if picked { RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 1.5).padding(-2) } }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityLabel("\(day.date), \(empty ? "no run" : Wording.minutes(day.delayMin))")
    }
}
