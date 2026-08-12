import SwiftUI

struct TrainMarker: View {
    let train: Train
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? train.operator.tint : RailTheme.parchment)
                .frame(width: isSelected ? 54 : 46, height: isSelected ? 54 : 46)
                .shadow(color: train.operator.tint.opacity(0.34), radius: isSelected ? 12 : 6, y: 4)

            Image(systemName: "train.side.front.car")
                .font(.system(size: isSelected ? 22 : 18, weight: .black))
                .foregroundStyle(isSelected ? .white : train.operator.tint)
        }
        .overlay {
            Circle()
                .strokeBorder(train.operator.tint, lineWidth: isSelected ? 3 : 2)
        }
        .animation(.bouncy(duration: 0.4, extraBounce: 0.12), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(train.operator.displayName) train \(train.number), \(train.name)")
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
                .background(sighting.operator.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }

            Text(sighting.operator.shortName)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sighting.operator.displayName) freight sighting")
        .accessibilityValue("\(Int(sighting.confidence * 100)) percent confidence, \(sighting.direction)")
    }

    private var confidenceColor: Color {
        switch sighting.confidence {
        case 0.8...: .green
        case 0.6...: .yellow
        default: .orange
        }
    }
}
