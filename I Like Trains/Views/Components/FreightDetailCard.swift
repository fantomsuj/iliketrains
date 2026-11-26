import SwiftUI

/// Bottom card for a selected freight corridor, intermodal terminal, or yard. Every card names its source,
/// because none of this is live and each source has its own caveats.
struct FreightDetailCard: View {
    enum Item {
        case corridor(FreightCorridor)
        case terminal(IntermodalTerminal)
        case yard(YardDwell)
    }

    let item: Item
    let atlas: FreightAtlas
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Text(title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(RailTheme.railInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RailTheme.railInk.opacity(0.72))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let pill {
                    Text(pill.text)
                        .font(.caption.weight(.black))
                        .foregroundStyle(pill.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(pill.color.opacity(0.14), in: Capsule())
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.08), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close details")
            }
            .padding(.bottom, 14)

            Divider()
                .overlay(RailTheme.railInk.opacity(0.14))

            HStack(spacing: 0) {
                ForEach(metrics, id: \.label) { metric in
                    FreightMetric(symbol: metric.symbol, value: metric.value, label: metric.label)
                }
            }
            .padding(.top, 14)

            if let context {
                Text(context)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RailTheme.railInk.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(18)
        .background(RailTheme.parchment, in: RoundedRectangle(cornerRadius: RailTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RailTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }

    // MARK: Content

    private struct MetricValue {
        let symbol: String
        let value: String
        let label: String
    }

    private var accent: Color {
        switch item {
        case .corridor(let corridor): corridor.railroad.tint
        case .terminal: RailTheme.signalOrange
        case .yard(let yard): yard.railroad.tint
        }
    }

    private var eyebrow: String {
        switch item {
        case .corridor(let corridor):
            "\(corridor.railroad.shortName)  •  MAIN LINE"
        case .terminal(let terminal):
            terminal.port == nil ? "INTERMODAL RAMP" : "PORT INTERMODAL RAMP"
        case .yard(let yard):
            "\(yard.railroad.shortName)  •  CLASSIFICATION YARD"
        }
    }

    private var title: String {
        switch item {
        case .corridor(let corridor):
            if let trainsPerDay = corridor.trainsPerDay {
                return "≈\(Int(trainsPerDay.rounded())) trains a day"
            }
            return "No public train count"
        case .terminal(let terminal):
            return terminal.name
        case .yard(let yard):
            return yard.name
        }
    }

    private var subtitle: String? {
        switch item {
        case .corridor(let corridor):
            [corridor.railroad.displayName, corridor.place].compactMap { $0 }.joined(separator: " • ")
        case .terminal(let terminal):
            [terminal.place, terminal.port].compactMap { $0 }.joined(separator: " • ")
        case .yard:
            nil
        }
    }

    private var pill: (text: String, color: Color)? {
        switch item {
        case .corridor(let corridor):
            let color: Color = corridor.level == .unmeasured ? .secondary : corridor.level.tint
            return (text: corridor.level.label.uppercased(), color: color)
        case .terminal:
            return nil
        case .yard(let yard):
            return (text: DwellTheme.label(hours: yard.dwellHours).uppercased(), color: DwellTheme.tint(hours: yard.dwellHours))
        }
    }

    private var metrics: [MetricValue] {
        switch item {
        case .corridor(let corridor):
            return [
                MetricValue(symbol: "speedometer", value: corridor.maxSpeedMPH.map { "\($0)" } ?? "—", label: "MAX MPH"),
                MetricValue(symbol: "equal", value: corridor.mainTracks.map { "\($0)" } ?? "—", label: corridor.mainTracks == 1 ? "MAIN TRACK" : "MAIN TRACKS"),
                MetricValue(symbol: "ruler", value: "\(Int(corridor.miles.rounded()))", label: "MILES"),
                MetricValue(symbol: "car.side", value: corridor.crossingCount > 0 ? "\(corridor.crossingCount)" : "—", label: "CROSSINGS")
            ]
        case .terminal(let terminal):
            return [
                MetricValue(symbol: "shippingbox.fill", value: terminal.handlesContainers ? "Yes" : "No", label: "CONTAINERS"),
                MetricValue(symbol: "truck.box.fill", value: terminal.handlesTrailers ? "Yes" : "No", label: "TRAILERS"),
                MetricValue(
                    symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    value: terminal.railroads.isEmpty ? "Short line" : terminal.railroads.map(\.shortName).joined(separator: ", "),
                    label: "CLASS I"
                )
            ]
        case .yard(let yard):
            let report = atlas.service(for: yard.railroad)
            let rank = report.map { report in
                report.yards.sorted { $0.dwellHours > $1.dwellHours }.firstIndex { $0.id == yard.id }.map { $0 + 1 }
            } ?? nil
            return [
                MetricValue(symbol: "hourglass", value: String(format: "%.1f", yard.dwellHours), label: "HOURS DWELL"),
                MetricValue(symbol: "chart.bar.fill", value: report.map { String(format: "%.1f", $0.systemDwellHours) } ?? "—", label: "SYSTEM AVG"),
                MetricValue(symbol: "list.number", value: rank.map { "\($0) of \(report?.yards.count ?? 10)" } ?? "—", label: "SLOWEST")
            ]
        }
    }

    private var context: String? {
        switch item {
        case .corridor(let corridor):
            guard let report = atlas.service(for: corridor.railroad), let speed = report.systemSpeedMPH else { return nil }
            let week = atlas.serviceWeekEnded.map { " in the week ending \($0.shortLabel)" } ?? " last week"
            return "\(corridor.railroad.shortName) trains averaged \(String(format: "%.1f", speed)) mph system-wide\(week), with \(String(format: "%g", report.trainsHeldPerDay)) trains a day held waiting for crews, locomotives or other causes."
        case .terminal(let terminal):
            return "Served by \(terminal.operatorsDescription)."
        case .yard(let yard):
            guard let report = atlas.service(for: yard.railroad) else { return nil }
            let difference = yard.dwellHours - report.systemDwellHours
            let direction = difference >= 0 ? "longer" : "shorter"
            return "Cars waited \(String(format: "%.1f", abs(difference))) hours \(direction) here than \(yard.railroad.shortName)'s system average."
        }
    }

    private var footnote: String {
        switch item {
        case .corridor(let corridor):
            let filled = corridor.crossingCount == 0 && corridor.trainsPerDay != nil
                ? "Estimated from neighbouring track. "
                : ""
            return "\(filled)Median freight trains reported at public crossings (FRA Crossing Inventory: through trains minus passenger and transit). A typical day, not live; railroads update counts irregularly."
        case .terminal:
            return "BTS Intermodal Freight Facilities (NTAD)."
        case .yard:
            let week = atlas.serviceWeekEnded.map { "week ending \($0.shortLabel)" } ?? "latest week"
            return "STB rail service filing, \(week). Pin location is approximate."
        }
    }
}

private struct FreightMetric: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(RailTheme.signalOrange)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
