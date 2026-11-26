import SwiftUI

/// A small square badge for a container or trailer ramp.
struct IntermodalTerminalMarker: View {
    let terminal: IntermodalTerminal
    let isSelected: Bool

    var body: some View {
        Image(systemName: terminal.port == nil ? "shippingbox.fill" : "ferry.fill")
            .font(.system(size: isSelected ? 13 : 10, weight: .black))
            .foregroundStyle(isSelected ? .white : RailTheme.railInk)
            .frame(width: isSelected ? 30 : 22, height: isSelected ? 30 : 22)
            .background(
                isSelected ? RailTheme.signalOrange : RailTheme.parchment,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? .white : RailTheme.railInk.opacity(0.55), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Intermodal terminal, \(terminal.name), \(terminal.place)")
            .accessibilityValue(terminal.equipmentLabel)
    }
}

/// A yard pin showing last week's average dwell in hours, coloured from fluid to congested.
struct YardDwellMarker: View {
    let yard: YardDwell
    let isSelected: Bool

    var body: some View {
        let tint = DwellTheme.tint(hours: yard.dwellHours)
        HStack(spacing: 3) {
            Text(yard.railroad.shortName)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(yard.railroad.tint)
            Text("\(Int(yard.dwellHours.rounded()))h")
                .font(.system(size: isSelected ? 13 : 11, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? .white : tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(RailTheme.parchment), in: Capsule())
        .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(yard.railroad.displayName) yard, \(yard.name)")
        .accessibilityValue("Cars waited \(Int(yard.dwellHours.rounded())) hours on average last week")
    }
}

/// The colour ramp for freight trains per day, as a compact strip with its break points.
struct TrafficScale: View {
    let atlas: FreightAtlas
    var minimum: TrafficLevel = .light

    private var levels: [TrafficLevel] {
        TrafficLevel.allCases.filter { $0 != .unmeasured }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                ForEach(levels, id: \.self) { level in
                    Capsule()
                        .fill(level.tint)
                        .frame(height: 6)
                        .opacity(level >= minimum ? 1 : 0.25)
                }
            }
            HStack(spacing: 0) {
                Text("0")
                ForEach(atlas.levelBounds, id: \.self) { bound in
                    Spacer(minLength: 0)
                    Text("\(Int(bound))")
                }
                Spacer(minLength: 0)
                Text("trains/day")
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Freight traffic scale")
        .accessibilityValue("Line colour runs from sand for under \(Int(atlas.levelBounds.first ?? 5)) trains a day to deep red for over \(Int(atlas.levelBounds.last ?? 80))")
    }
}
