import SwiftUI

struct TrainMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let train: Train
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? train.railOperator.tint : RailTheme.parchment)
                .frame(width: isSelected ? 54 : 46, height: isSelected ? 54 : 46)
                .shadow(color: train.railOperator.tint.opacity(0.34), radius: isSelected ? 12 : 6, y: 4)

            Image(systemName: "train.side.front.car")
                .font(.system(size: isSelected ? 22 : 18, weight: .black))
                .foregroundStyle(isSelected ? .white : train.railOperator.tint)
        }
        .overlay {
            Circle()
                .strokeBorder(train.railOperator.tint, lineWidth: isSelected ? 3 : 2)
        }
        .animation(
            reduceMotion ? nil : .bouncy(duration: 0.4, extraBounce: 0.12),
            value: isSelected
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(train.railOperator.displayName) train \(train.number), \(train.name)")
        .accessibilityValue("\(train.status.label), \(train.speedMPH) miles per hour")
    }
}

struct FreightSightingMarker: View {
    let sighting: FreightSighting

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(sighting.railOperator.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }

            Text(sighting.railOperator.shortName)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())

            Text("\(Int(sighting.confidence * 100))% • \(sighting.reporterCount) reports")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())

            Text(sighting.observedAt.formatted(.relative(presentation: .numeric)))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sighting.railOperator.displayName) freight sighting")
        .accessibilityValue(
            "\(Int(sighting.confidence * 100)) percent confidence, " +
            "\(sighting.reporterCount) reporters, " +
            "\(sighting.observedAt.formatted(.relative(presentation: .named))), " +
            sighting.direction
        )
    }

    private var confidenceColor: Color {
        switch sighting.confidence {
        case 0.8...: .green
        case 0.6...: .yellow
        default: .orange
        }
    }
}
