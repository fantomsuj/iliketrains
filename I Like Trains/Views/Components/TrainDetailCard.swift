import SwiftUI

struct TrainDetailCard: View {
    let train: Train
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(train.railOperator.shortName)  •  \(train.number)")
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(train.railOperator.tint)

                    Text(train.name)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(RailTheme.railInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                StatusPill(train: train)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.08), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close train details")
            }
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Text(train.origin)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(RailTheme.signalOrange)
                Text(train.destination)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RailTheme.railInk.opacity(0.78))
            .padding(.bottom, 16)

            Divider()
                .overlay(RailTheme.railInk.opacity(0.14))

            HStack(spacing: 0) {
                Metric(symbol: "speedometer", value: "\(train.speedMPH)", label: "MPH")
                Metric(symbol: "clock.fill", value: train.nextStopETA.formatted(date: .omitted, time: .shortened), label: train.nextStopCode)
                Metric(symbol: "location.fill", value: train.nextStop, label: "NEXT")
            }
            .padding(.top, 14)

            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("Updated \(train.updatedAt.formatted(.relative(presentation: .named)))")
                Spacer()
                Text("MOCK FEED")
                    .fontWeight(.black)
                    .tracking(0.7)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 14)
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
}

private struct StatusPill: View {
    let train: Train

    var body: some View {
        Text(statusText)
            .font(.caption.weight(.black))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.13), in: Capsule())
    }

    private var statusText: String {
        guard train.delayMinutes != 0 else { return train.status.label }
        return train.delayMinutes > 0 ? "+\(train.delayMinutes) MIN" : "\(train.delayMinutes) MIN"
    }

    private var statusColor: Color {
        switch train.status {
        case .onTime, .early: .green
        case .delayed: RailTheme.signalOrange
        case .stopped: .blue
        }
    }
}

private struct Metric: View {
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
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZStack {
        Color.gray
        TrainDetailCard(
            train: Train(
                id: "preview-6",
                number: "6",
                name: "California Zephyr",
                railOperator: .amtrak,
                origin: "Emeryville",
                destination: "Chicago",
                coordinate: .init(latitude: 39.74, longitude: -104.99),
                heading: 72,
                speedMPH: 68,
                delayMinutes: 12,
                nextStop: "Fort Morgan",
                nextStopCode: "FMG",
                nextStopETA: .now.addingTimeInterval(1_800),
                updatedAt: .now.addingTimeInterval(-120),
                status: .delayed
            ),
            onClose: {}
        )
        .padding()
    }
}
