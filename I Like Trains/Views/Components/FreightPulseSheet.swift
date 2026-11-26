import SwiftUI

/// "How is freight doing this week": national volume from the AAR, each Class I railroad's STB service
/// filing, the busiest lines on the map, and where every number comes from.
struct FreightPulseSheet: View {
    let atlas: FreightAtlas
    let onShowCorridor: (FreightCorridor) -> Void
    let onFilterRailroad: (RailOperator) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let volume = atlas.volume {
                    volumeSection(volume)
                    commoditySection(volume)
                }
                if !atlas.service.isEmpty {
                    serviceSection
                }
                busiestSection
                sourcesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Freight this week")
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

    // MARK: Volume

    private func volumeSection(_ volume: FreightVolumeReport) -> some View {
        Section {
            HStack(spacing: 0) {
                VolumeFigure(title: "CARLOADS", figure: volume.carloads)
                VolumeFigure(title: "INTERMODAL", figure: volume.intermodalUnits)
                VolumeFigure(title: "TOTAL", figure: volume.totalTraffic)
            }
            .padding(.vertical, 4)
        } header: {
            Text("U.S. rail traffic • week \(volume.week), ended \(volume.weekEnded.shortLabel)")
        } footer: {
            Text("Change versus the same week last year. Excludes U.S. operations of CPKC, CN and GMXT.")
        }
    }

    private func commoditySection(_ volume: FreightVolumeReport) -> some View {
        let largest = Double(volume.commodities.map(\.carloads).max() ?? 1)
        return Section("What moved") {
            ForEach(volume.commodities) { commodity in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(commodity.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(commodity.carloads.formatted())
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        ChangeLabel(percent: commodity.changePercent)
                            .frame(width: 58, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(RailTheme.signalOrange.opacity(0.75))
                            .frame(width: max(4, proxy.size.width * Double(commodity.carloads) / largest))
                    }
                    .frame(height: 5)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Service

    private var serviceSection: some View {
        Section {
            ForEach(atlas.service) { report in
                Button {
                    onFilterRailroad(report.railroad)
                    dismiss()
                } label: {
                    ServiceRow(report: report)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows only \(report.railroad.displayName) on the map")
            }
        } header: {
            Text("Railroads • week ended \(atlas.serviceWeekEnded?.shortLabel ?? "—")")
        } footer: {
            Text("Average train speed and car dwell time in yards, as each railroad reported to the STB. Tap a railroad to show only its lines and yards.")
        }
    }

    // MARK: Busiest lines

    private var busiestSection: some View {
        Section {
            ForEach(atlas.busiestCorridors(limit: 6)) { corridor in
                Button {
                    onShowCorridor(corridor)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(corridor.level.tint)
                            .frame(width: 6, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(corridor.railroad.displayName)
                                .font(.subheadline.weight(.bold))
                            Text(corridor.place ?? "\(Int(corridor.miles.rounded())) mi of track")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("≈\(Int((corridor.trainsPerDay ?? 0).rounded()))")
                            .font(.system(.title3, design: .rounded, weight: .black))
                            .monospacedDigit()
                        Text("trains\n/day")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Shows this line on the map")
            }
        } header: {
            Text("Busiest freight lines")
        } footer: {
            Text("Typical-day through trains reported at public crossings. Crossing counts are self-reported and can lag reality.")
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        Section("Sources") {
            ForEach(atlas.sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    if let url = source.url {
                        Link(source.name, destination: url)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(source.name)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("\(source.publisher) • \(source.asOf)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(source.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct VolumeFigure: View {
    let title: String
    let figure: FreightVolumeReport.Figure

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.black))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(compact(figure.count))
                .font(.system(.title2, design: .rounded, weight: .black))
                .monospacedDigit()
            ChangeLabel(percent: figure.changePercent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func compact(_ count: Int) -> String {
        count >= 10_000 ? "\(Int((Double(count) / 1000).rounded()))k" : count.formatted()
    }
}

private struct ChangeLabel: View {
    let percent: Double

    var body: some View {
        Text("\(percent >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(percent)))%")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(percent >= 0 ? Color(red: 0.10, green: 0.55, blue: 0.40) : RailTheme.signalOrange)
            .accessibilityLabel("\(percent >= 0 ? "up" : "down") \(String(format: "%.1f", abs(percent))) percent")
    }
}

private struct ServiceRow: View {
    let report: RailroadServiceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(report.railroad.tint)
                    .frame(width: 10, height: 10)
                Text(report.railroad.displayName)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 0) {
                stat(report.systemSpeedMPH.map { String(format: "%.1f", $0) } ?? "—", "MPH")
                stat(String(format: "%.1f", report.systemDwellHours), "HRS DWELL")
                stat("\(Int((Double(report.carsOnline) / 1000).rounded()))k", "CARS ONLINE")
                stat(String(format: "%g", report.trainsHeldPerDay), "HELD/DAY")
            }
            if let slowest = report.slowestYard {
                Text("Slowest yard: \(slowest.name), \(String(format: "%.1f", slowest.dwellHours)) h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
