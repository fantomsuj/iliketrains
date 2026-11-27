import SwiftUI
import TrainsCore

/// "Listening in": the live event feed scrolls along the bottom like an ATC strip.
struct TickerView: View {
    @Environment(LiveStore.self) private var store
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(store.events.prefix(30)) { e in
                    Button { onTap(e.trainId) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(color(e)).frame(width: 5, height: 5)
                            Text(e.at.clockTime).foregroundStyle(Theme.dim)
                            Text(e.text).foregroundStyle(Theme.text)
                        }
                        .font(Theme.mono)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .animation(.spring(duration: 0.5), value: store.events.first?.id)
        }
        .frame(height: 34)
        .background(LinearGradient(colors: [.clear, Theme.background.opacity(0.92)], startPoint: .top, endPoint: .center))
    }

    private func color(_ e: LiveEvent) -> Color {
        switch e.kind {
        case .cancelled: return Theme.bad
        case .delay: return Theme.late
        default: return Theme.color(Wording.punctuality(delaySec: e.delaySec, status: .enroute, source: .live))
        }
    }
}

extension EpochMs {
    var clockTime: String { Date(timeIntervalSince1970: self / 1000).formatted(date: .omitted, time: .shortened) }
}
